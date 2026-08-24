defmodule ShadowOpsCore.Audit do
  @moduledoc "Append-only, hash-chained local audit journal."
  @event_types [
    :requested,
    :policy_evaluated,
    :approval_requested,
    :approval_granted,
    :approval_rejected,
    :execution_started,
    :execution_finished,
    :execution_blocked,
    :evidence_recorded,
    :run_queued,
    :run_started,
    :run_finished,
    :whatsapp_import,
    :whatsapp_analysis,
    :whatsapp_connector,
    :whatsapp_page_view,
    :whatsapp_ingest,
    :gmail_read,
    :gmail_classification,
    :gmail_draft,
    :gmail_send,
    :gmail_forward,
    :gmail_label,
    :gmail_delete,
    :workflow_run,
    :workflow_failure,
    :github_export,
    :github_sync,
    :node_action,
    :service_action
  ]
  @path Path.expand("../../../../var/audit.jsonl", __DIR__)
  @enforce_keys [:id, :timestamp, :actor, :event, :target, :result, :metadata]
  defstruct [:id, :timestamp, :actor, :event, :target, :result, :metadata]

  def event_types, do: @event_types
  def path, do: Application.get_env(:shadowops_core, :audit_path, @path)

  def valid?(%__MODULE__{event: event, result: result}),
    do: event in @event_types and result in [:success, :failure, :blocked]

  def new(event, actor, target, result, metadata \\ %{})

  def new(event, actor, target, result, metadata)
      when event in @event_types and is_binary(actor) and byte_size(actor) > 0,
      do:
        {:ok,
         %__MODULE__{
           id: "audit_" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower),
           timestamp: DateTime.utc_now(),
           actor: actor,
           event: event,
           target: target,
           result: result,
           metadata: redact(metadata)
         }}

  def new(event, _actor, _target, _result, _metadata), do: {:error, {:invalid_event, event}}

  def record(event, actor, target, result, metadata \\ %{}) do
    :global.trans({{__MODULE__, path()}, self()}, fn ->
      with {:ok, item} <- new(event, actor || "unknown", target, result, metadata),
           :ok <- append(item) do
        {:ok, item}
      end
    end)
  end

  def list(limit \\ 100) do
    case File.read(path()) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)
        |> Enum.take(-limit)
        |> Enum.reverse()

      _ ->
        []
    end
  end

  def verify do
    case Enum.reduce_while(list(100_000) |> Enum.reverse(), {true, nil}, fn row, {_, previous} ->
           expected = hash(Map.drop(row, ["current_hash"]))

           if row["previous_hash"] == previous and row["current_hash"] == expected,
             do: {:cont, {true, row["current_hash"]}},
             else: {:halt, {false, row["id"]}}
         end) do
      {true, _} -> {:ok, %{valid: true, entries: length(list(100_000))}}
      {false, id} -> {:error, %{valid: false, invalid_entry: id}}
    end
  end

  defp append(item) do
    File.mkdir_p!(Path.dirname(path()))

    previous =
      case list(1) do
        [%{"current_hash" => value}] -> value
        _ -> nil
      end

    row = %{
      id: item.id,
      timestamp: DateTime.to_iso8601(item.timestamp),
      actor: item.actor,
      action: Atom.to_string(item.event),
      resource: to_string(item.target),
      result: Atom.to_string(item.result),
      evidence_ref:
        Map.get(item.metadata, :evidence_ref) || Map.get(item.metadata, "evidence_ref"),
      privacy: "aggregate_only",
      metadata: item.metadata,
      previous_hash: previous
    }

    File.write(path(), Jason.encode!(Map.put(row, :current_hash, hash(row))) <> "\n", [:append])
  end

  defp hash(data) do
    data
    |> stringify()
    |> Enum.sort_by(fn {key, _} -> key end)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp stringify(map) when is_map(map),
    do: map |> Map.new(fn {k, v} -> {to_string(k), stringify(v)} end) |> Map.to_list()

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value), do: value

  defp redact(map) when is_map(map),
    do:
      Map.new(map, fn {k, v} ->
        if sensitive_key?(k),
          do: {k, "[REDACTED]"},
          else: {k, redact(v)}
      end)

  defp redact(list) when is_list(list), do: Enum.map(list, &redact/1)

  defp redact(value) when is_binary(value) do
    value
    |> String.replace(
      ~r/(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|Bearer\s+[A-Za-z0-9._-]{12,})/i,
      "[REDACTED]"
    )
    |> String.replace(~r/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i, "[REDACTED]")
    |> String.replace(
      ~r/(?<![A-Za-z0-9])(?:\+|00)[0-9][0-9 ()\/-]{6,18}[0-9](?![A-Za-z0-9])/,
      "[REDACTED]"
    )
  end

  defp redact(value), do: value

  defp sensitive_key?(key) do
    normalized = key |> to_string() |> String.downcase()

    Regex.match?(~r/(secret|token|password|credential)/, normalized) or
      normalized in ~w(body content text message messages subject snippet sender recipient phone email attachment attachments raw raw_messages)
  end
end
