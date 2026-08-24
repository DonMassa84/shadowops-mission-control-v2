defmodule ShadowOps.Social.WhatsAppAnalytics do
  @moduledoc """
  Privacy-preserving ingestion and aggregate analysis for a local WhatsApp export.

  Raw sender names and message bodies exist only while parsing. The durable artifact
  contains source provenance, stable pseudonymous evidence hashes, and aggregates.
  """

  import Bitwise

  alias ShadowOpsCore.{Audit, EventBus}

  @default_source "/home/schattenmacher/social-exports/whatsapp/WhatsApp Chat Existing Workflow.txt"
  @default_state Path.expand("../../../../../var/whatsapp_aggregate.json", __DIR__)
  @line_regex ~r/^\[(?<date>\d{1,2}[.\/-]\d{1,2}[.\/-]\d{2,4}),\s*(?<time>\d{1,2}:\d{2}(?::\d{2})?)\]\s+(?<sender>[^:]+):\s?(?<body>.*)$/u
  @synthetic_patterns [
    ~r/wamid\.test/i,
    ~r/\[DRY_RUN\]/i,
    ~r/\+4915200000000/,
    ~r/wamid\.livetest/i,
    ~r/wamid\.seed/i
  ]

  @type result :: map()

  @spec load(keyword()) :: {:ok, result()} | {:error, map()}
  def load(opts \\ []) do
    source_path = Keyword.get(opts, :source_path, configured_source())
    state_path = Keyword.get(opts, :state_path, configured_state())
    audit? = Keyword.get(opts, :audit?, true)

    with {:ok, source} <- read_source(source_path),
         {:ok, parsed} <- parse_export(source.body),
         {:ok, normalized} <- normalize(parsed, source.sha256),
         {:ok, analysis} <- analyze(normalized),
         {:ok, result} <- persist(source, normalized, analysis, state_path, audit?),
         :ok <- publish_events(result) do
      {:ok, result}
    else
      {:error, %{code: _code} = error} -> {:error, error}
      {:error, reason} -> {:error, failure("INGEST_FAILED", reason, source_path)}
    end
  rescue
    error -> {:error, failure("INGEST_FAILED", Exception.message(error), nil)}
  end

  @doc false
  def parse_export(body) when is_binary(body) do
    lines = String.split(body, ~r/\R/u, trim: true)

    cond do
      not String.valid?(body) ->
        {:error, %{code: "SOURCE_ENCODING_INVALID", message: "Source is not valid UTF-8"}}

      :binary.match(body, <<0>>) != :nomatch ->
        {:error, %{code: "SOURCE_BINARY_INVALID", message: "Source contains binary NUL bytes"}}

      lines == [] ->
        {:error, %{code: "SOURCE_EMPTY", message: "Source contains no records"}}

      true ->
        lines
        |> Enum.with_index(1)
        |> Enum.reduce_while({:ok, []}, fn {line, line_number}, {:ok, records} ->
          case parse_line(line, line_number) do
            {:ok, record} -> {:cont, {:ok, [record | records]}}
            {:error, error} -> {:halt, {:error, error}}
          end
        end)
        |> case do
          {:ok, records} -> {:ok, Enum.reverse(records)}
          error -> error
        end
    end
  end

  def parse_export(_body),
    do: {:error, %{code: "SOURCE_ENCODING_INVALID", message: "Source is not text"}}

  defp configured_source,
    do: Application.get_env(:shadowops_core, :whatsapp_export_source, @default_source)

  defp configured_state,
    do: Application.get_env(:shadowops_core, :whatsapp_aggregate_path, @default_state)

  defp read_source(path) when is_binary(path) do
    with {:ok, stat} <- File.stat(path),
         true <- stat.type == :regular,
         {:ok, body} <- File.read(path),
         false <- synthetic?(body) do
      {:ok,
       %{
         body: body,
         basename: Path.basename(path),
         sha256: digest(body),
         size_bytes: stat.size,
         mtime: stat.mtime |> NaiveDateTime.from_erl!() |> NaiveDateTime.to_iso8601(),
         mode: stat.mode |> band(0o777) |> Integer.to_string(8)
       }}
    else
      {:error, :enoent} ->
        {:error, failure("SOURCE_MISSING", "Configured WhatsApp export does not exist", path)}

      {:error, reason} ->
        {:error, failure("SOURCE_UNREADABLE", reason, path)}

      false ->
        {:error, failure("SOURCE_NOT_REGULAR", "Configured source is not a regular file", path)}

      true ->
        {:error, failure("SYNTHETIC_SOURCE", "Known synthetic fixture signature detected", path)}
    end
  end

  defp read_source(path),
    do: {:error, failure("SOURCE_MISSING", "No WhatsApp export is configured", path)}

  defp parse_line(line, line_number) do
    case Regex.named_captures(@line_regex, line) do
      %{"date" => date, "time" => time, "sender" => sender} ->
        with {:ok, timestamp} <- parse_timestamp(date, time),
             true <- String.trim(sender) != "" do
          {:ok, %{line_number: line_number, timestamp: timestamp, sender: sender}}
        else
          _ -> parse_error(line_number)
        end

      _ ->
        parse_error(line_number)
    end
  end

  defp parse_error(line_number),
    do:
      {:error,
       %{
         code: "SOURCE_PARSE_FAILED",
         message: "WhatsApp export structure is invalid",
         line_number: line_number
       }}

  defp parse_timestamp(date, time) do
    with [day, month, year] <- String.split(date, ~r/[.\/-]/),
         {day, ""} <- Integer.parse(day),
         {month, ""} <- Integer.parse(month),
         {year, ""} <- Integer.parse(year),
         year <- if(year < 100, do: 2000 + year, else: year),
         {:ok, date} <- Date.new(year, month, day),
         {:ok, time} <- parse_time(time),
         {:ok, timestamp} <- NaiveDateTime.new(date, time) do
      {:ok, NaiveDateTime.to_iso8601(timestamp)}
    else
      _ -> {:error, :invalid_timestamp}
    end
  end

  defp parse_time(value) do
    case value |> String.split(":") |> Enum.map(&Integer.parse/1) do
      [{hour, ""}, {minute, ""}] -> Time.new(hour, minute, 0)
      [{hour, ""}, {minute, ""}, {second, ""}] -> Time.new(hour, minute, second)
      _ -> {:error, :invalid_time}
    end
  end

  defp normalize(records, source_sha256) do
    conversation_id = pseudonym("conversation", source_sha256)

    normalized =
      records
      |> Enum.map(fn record ->
        %{
          source: "whatsapp_export",
          source_ref: "sha256:" <> source_sha256,
          timestamp: record.timestamp,
          direction: "unknown",
          conversation_id: conversation_id,
          message_id: pseudonym("message", source_sha256 <> ":" <> to_string(record.line_number)),
          participant_id: pseudonym("participant", source_sha256 <> ":" <> record.sender)
        }
      end)

    if normalized == [],
      do: {:error, %{code: "NORMALIZE_EMPTY", message: "No normalized records were produced"}},
      else: {:ok, normalized}
  end

  defp analyze(records) do
    timestamps = Enum.map(records, & &1.timestamp)
    direction_counts = Enum.frequencies_by(records, & &1.direction)

    {:ok,
     %{
       message_count: length(records),
       conversation_count:
         records |> Enum.map(& &1.conversation_id) |> MapSet.new() |> MapSet.size(),
       participant_count:
         records |> Enum.map(& &1.participant_id) |> MapSet.new() |> MapSet.size(),
       inbound_count: Map.get(direction_counts, "inbound", 0),
       outbound_count: Map.get(direction_counts, "outbound", 0),
       direction_unknown_count: Map.get(direction_counts, "unknown", 0),
       timestamp_start: Enum.min(timestamps),
       timestamp_end: Enum.max(timestamps)
     }}
  end

  defp persist(source, normalized, analysis, state_path, audit?) do
    normalized_digest = digest(Jason.encode!(normalized))
    trace_id = "wa_trace_" <> String.slice(digest(source.sha256 <> normalized_digest), 0, 24)

    derived = %{
      schema_version: 2,
      privacy: "aggregate_only",
      source: %{
        name: source.basename,
        sha256: source.sha256,
        size_bytes: source.size_bytes,
        mtime: source.mtime,
        mode: source.mode,
        synthetic: false,
        parseable: true
      },
      provenance: %{
        source_ref: "sha256:" <> source.sha256,
        trace_id: trace_id,
        normalized_digest: normalized_digest,
        correlation_id: "corr_" <> String.slice(digest("whatsapp:" <> source.sha256), 0, 32)
      },
      ingest: %{status: "PASS", idempotency_key: source.sha256, record_count: length(normalized)},
      normalize: %{status: "PASS", record_count: length(normalized)},
      analysis: Map.put(analysis, :status, "PASS")
    }

    case current_artifact(state_path, source.sha256, normalized_digest) do
      {:ok, current} ->
        unchanged(derived, current, audit?)

      :new ->
        ingest_new(derived, state_path, audit?)
    end
  end

  defp current_artifact(path, source_sha256, normalized_digest) do
    with {:ok, body} <- File.read(path),
         {:ok, current} <- Jason.decode(body),
         2 <- current["schema_version"],
         ^source_sha256 <- get_in(current, ["source", "sha256"]),
         ^normalized_digest <- get_in(current, ["provenance", "normalized_digest"]),
         "aggregate_only" <- current["privacy"] do
      {:ok, current}
    else
      _ -> :new
    end
  end

  defp unchanged(derived, current, true) do
    case Audit.verify() do
      {:ok, verification} ->
        with {:ok, event_ids} <- verify_whatsapp_audit_evidence(current, derived) do
          {:ok,
           finish(derived, "UNCHANGED", current["last_ingest_at"], %{
             status: "PASS",
             hash_chain: "PASS",
             entries: verification.entries,
             event_ids: event_ids
           })}
        else
          _ ->
            {:error,
             %{
               code: "WHATSAPP_AUDIT_EVIDENCE_INVALID",
               message: "Canonical WhatsApp audit evidence is missing or inconsistent"
             }}
        end

      {:error, _reason} ->
        {:error, %{code: "AUDIT_CHAIN_INVALID", message: "Canonical audit chain is invalid"}}
    end
  end

  defp unchanged(derived, current, false) do
    {:ok,
     finish(derived, "UNCHANGED", current["last_ingest_at"], %{
       status: "SKIPPED",
       hash_chain: "UNVERIFIED",
       entries: nil,
       event_ids: []
     })}
  end

  defp verify_whatsapp_audit_evidence(current, derived) do
    event_ids = get_in(current, ["audit", "event_ids"])
    expected_resources = MapSet.new(~w(whatsapp_import whatsapp_analysis whatsapp_connector))

    rows_by_id =
      Audit.list(100_000)
      |> Map.new(&{&1["id"], &1})

    rows =
      if is_list(event_ids) and length(event_ids) == 3 and
           MapSet.size(MapSet.new(event_ids)) == 3 do
        Enum.map(event_ids, &Map.get(rows_by_id, &1))
      else
        []
      end

    resources =
      rows
      |> Enum.filter(&is_map/1)
      |> Enum.map(& &1["resource"])
      |> MapSet.new()

    valid? =
      length(rows) == 3 and Enum.all?(rows, &is_map/1) and resources == expected_resources and
        Enum.all?(rows, fn row ->
          metadata = row["metadata"] || %{}

          row["action"] == row["resource"] and row["result"] == "success" and
            row["evidence_ref"] == derived.provenance.source_ref and
            metadata["privacy"] == "aggregate_only" and
            metadata["trace_id"] == derived.provenance.trace_id and
            metadata["evidence_ref"] == derived.provenance.source_ref and
            metadata["source_sha256"] == derived.source.sha256 and
            metadata["normalized_digest"] == derived.provenance.normalized_digest and
            metadata["message_count"] == derived.analysis.message_count and
            metadata["conversation_count"] == derived.analysis.conversation_count
        end)

    if valid?, do: {:ok, event_ids}, else: {:error, :invalid_whatsapp_audit_evidence}
  end

  defp ingest_new(derived, state_path, audit?) do
    ingested_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    pending =
      finish(derived, "IMPORTED", ingested_at, %{
        status: "PENDING",
        hash_chain: "UNVERIFIED",
        entries: nil,
        event_ids: []
      })

    with :ok <- atomic_write(state_path, pending),
         {:ok, audit} <- audit(derived, audit?),
         final <- finish(derived, "IMPORTED", ingested_at, audit),
         :ok <- atomic_write(state_path, final) do
      {:ok, final}
    else
      {:error, %{code: _code} = error} -> {:error, error}
      {:error, reason} -> {:error, failure("AGGREGATE_PERSIST_FAILED", reason, state_path)}
    end
  end

  defp audit(_derived, false) do
    {:ok, %{status: "SKIPPED", hash_chain: "UNVERIFIED", entries: nil, event_ids: []}}
  end

  defp audit(derived, true) do
    metadata = %{
      privacy: "aggregate_only",
      trace_id: derived.provenance.trace_id,
      evidence_ref: derived.provenance.source_ref,
      source_sha256: derived.source.sha256,
      message_count: derived.analysis.message_count,
      conversation_count: derived.analysis.conversation_count,
      normalized_digest: derived.provenance.normalized_digest,
      correlation_id: derived.provenance.correlation_id
    }

    with {:ok, import} <-
           Audit.record(:whatsapp_import, "shadowops_core", "whatsapp_import", :success, metadata),
         {:ok, analysis} <-
           Audit.record(
             :whatsapp_analysis,
             "shadowops_core",
             "whatsapp_analysis",
             :success,
             metadata
           ),
         {:ok, connector} <-
           Audit.record(
             :whatsapp_connector,
             "shadowops_core",
             "whatsapp_connector",
             :success,
             metadata
           ),
         {:ok, verification} <- Audit.verify() do
      {:ok,
       %{
         status: "PASS",
         hash_chain: "PASS",
         entries: verification.entries,
         event_ids: [import.id, analysis.id, connector.id]
       }}
    else
      _ -> {:error, %{code: "WHATSAPP_AUDIT_FAILED", message: "Audit recording failed"}}
    end
  end

  defp finish(derived, ingest_result, last_ingest_at, audit) do
    payload =
      derived
      |> Map.put(:ingest_result, ingest_result)
      |> Map.put(:last_ingest_at, last_ingest_at)
      |> Map.put(:audit, audit)

    stable_payload = update_in(payload, [:audit], &Map.delete(&1, :entries))
    Map.put(payload, :artifact_sha256, digest(Jason.encode!(stable_payload)))
  end

  defp publish_events(result) do
    common = %{
      source: "whatsapp",
      resource_id: "connector:whatsapp",
      correlation_id: result.provenance.correlation_id,
      privacy: "aggregate_only",
      synthetic: false,
      evidence_ref: result.provenance.source_ref,
      metadata: %{
        message_count: result.analysis.message_count,
        conversation_count: result.analysis.conversation_count,
        trace_id: result.provenance.trace_id
      }
    }

    with {:ok, _} <- EventBus.publish(Map.put(common, :type, "whatsapp.ingested")),
         {:ok, _} <- EventBus.publish(Map.put(common, :type, "whatsapp.analysis_completed")) do
      :ok
    end
  end

  defp atomic_write(path, payload) do
    directory = Path.dirname(path)
    temporary = path <> ".tmp-" <> Integer.to_string(System.unique_integer([:positive]))

    with :ok <- File.mkdir_p(directory),
         :ok <- File.write(temporary, "", [:exclusive]),
         :ok <- File.chmod(temporary, 0o600),
         :ok <- File.write(temporary, Jason.encode!(payload)),
         :ok <- File.rename(temporary, path) do
      :ok
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp synthetic?(body), do: Enum.any?(@synthetic_patterns, &Regex.match?(&1, body))

  defp pseudonym(namespace, value),
    do: namespace <> "_" <> String.slice(digest(namespace <> ":" <> value), 0, 24)

  defp digest(value),
    do: :sha256 |> :crypto.hash(value) |> Base.encode16(case: :lower)

  defp failure(code, reason, path) do
    %{
      code: code,
      message: safe_reason(reason),
      source: if(is_binary(path), do: Path.basename(path), else: nil)
    }
  end

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason(reason) when is_binary(reason), do: reason
  defp safe_reason(_reason), do: "WhatsApp source operation failed"
end
