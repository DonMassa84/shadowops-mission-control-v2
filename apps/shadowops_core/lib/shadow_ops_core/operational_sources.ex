defmodule ShadowOpsCore.OperationalSources do
  @moduledoc "Evidence-backed adapters for Mission Control operational modules."

  alias ShadowOps.Social.WhatsAppAnalytics
  alias ShadowOpsCore.{Audit, ConnectorState, RunStore}

  @i7_status "/home/schattenmacher/.local/bin/i7-status"
  @i7_start "/home/schattenmacher/.local/bin/i7-on"
  @i7_ssh_host "shadowserver-i7"
  @i7_inventory_source "ssh shadowserver-i7 -- ollama list"
  @whatsapp_db "/home/schattenmacher/whatsapp-agent/data/whatsapp_agent.db"
  @whatsapp_backups "/home/schattenmacher/whatsapp-agent/backups"
  @career_runtime "/home/schattenmacher/.local/bin/career-funnel"
  @career_root "/home/schattenmacher/openclaw_training/career_funnel"
  @career_report "/home/schattenmacher/openclaw_training/career_funnel/reports/LATEST.json"
  @career_project "/home/schattenmacher/ihk-projektarbeit-zero-trust"
  @knowledge_store "/home/schattenmacher/DokumentenSystem/06_BACKUP/chroma_db/chroma.sqlite3"
  @knowledge_collection "dokumentensystem"
  @facebook_source "/home/schattenmacher/ProofFlow-Obsidian-Vault/30_Analytics/Facebook/facebook_ranking_deep.json"
  @agent_pattern ~r/(agent|opencode|codex|ollama|shadow-ai)/i
  @secret_pattern ~r/(bearer\s+|token["'=:\s]+|password["'=:\s]+)[^\s,;]+/i

  def system do
    started = System.monotonic_time(:millisecond)
    hostname = read_trim("/etc/hostname")
    os = os_release()
    uptime_seconds = first_number("/proc/uptime")
    memory = meminfo()

    payload = %{
      hostname: hostname,
      os: os,
      kernel: elem(System.cmd("uname", ["-r"], stderr_to_stdout: true), 0) |> String.trim(),
      cpu: cpu_info(),
      load: load_info(),
      ram: memory_values(memory, "Mem"),
      swap: memory_values(memory, "Swap"),
      disk: disk_info(),
      uptime_seconds: uptime_seconds,
      temperatures_c: temperatures(),
      network: network_info(),
      process_count: process_count(),
      updated_at: now()
    }

    state(
      "system-local",
      "Local system",
      "system",
      "ONLINE",
      "/proc, /sys and /etc/os-release",
      "LOCAL_RUNTIME",
      true,
      true,
      latency_ms: elapsed(started),
      last_success_at: now(),
      metadata: %{node: "local-ryzen"}
    )
    |> ConnectorState.attach(payload)
  rescue
    error ->
      state(
        "system-local",
        "Local system",
        "system",
        "ERROR",
        "/proc",
        "LOCAL_RUNTIME",
        false,
        false,
        error_code: "LOCAL_SYSTEM_READ_FAILED",
        error_message: Exception.message(error)
      )
      |> ConnectorState.attach(%{updated_at: now()})
  end

  def nodes do
    local = system() |> Map.put(:node_id, "local-ryzen")
    remote = i7_node()
    records = [local, remote]

    collection("nodes", "Infrastructure nodes", "nodes", records, "local probes and i7-status")
  end

  def node(id) do
    case Enum.find(nodes().records, &(&1.node_id == id)) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  def node_action("local-ryzen", "status"), do: {:ok, system()}
  def node_action("i7", "status"), do: {:ok, i7_node()}

  def node_action("i7", "start") do
    if File.regular?(@i7_start) do
      case System.cmd(@i7_start, [], stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, %{action: "start", accepted: true, source: @i7_start, output: redact(output)}}

        {_output, code} ->
          {:error, {:i7_start_failed, code}}
      end
    else
      {:error, :i7_start_unavailable}
    end
  rescue
    error -> {:error, {:i7_start_failed, Exception.message(error)}}
  end

  def node_action(_id, _action), do: {:error, :action_not_allowed}

  def agents(services) do
    records =
      services
      |> Map.get(:services, [])
      |> Enum.filter(&Regex.match?(@agent_pattern, &1.name))
      |> Enum.map(fn service ->
        status =
          cond do
            service.status == "READY" -> "READY"
            service.optional -> "OPTIONAL_UNAVAILABLE"
            true -> "DEGRADED"
          end

        state(
          "agent-" <> service.scope <> "-" <> service.name,
          service.name,
          "agent",
          status,
          service.source,
          "SYSTEMD_DISCOVERY",
          true,
          status == "READY",
          metadata: %{
            scope: service.scope,
            sub_state: service.sub_state,
            optional: service.optional
          }
        )
        |> ConnectorState.attach(%{
          runtime: service.name,
          model: nil,
          node: "local-ryzen",
          last_activity: service[:updated_at],
          current_task: nil,
          queue: nil,
          error: service[:last_error]
        })
      end)

    collection(
      "agents",
      "Detected automation agents",
      "agents",
      records,
      "systemd service discovery"
    )
  end

  def ai do
    local = ollama_local()
    remote = i7_ai()
    records = [local, remote]
    models = Enum.flat_map(records, &Map.get(&1, :models, []))

    collection("ai", "AI runtimes", "ai", records, "ollama CLI and i7 reachability")
    |> Map.put(
      :availability,
      if(Enum.any?(records, & &1.reachable), do: "AVAILABLE", else: "UNAVAILABLE")
    )
    |> Map.put(:source, "ollama list")
    |> Map.put(:models, models)
    |> Map.put(:loaded_models, Enum.flat_map(records, &Map.get(&1, :loaded_models, [])))
  end

  def whatsapp do
    runtime = whatsapp_at(@whatsapp_db, DateTime.utc_now())

    case WhatsAppAnalytics.load() do
      {:ok, analytics} -> whatsapp_export_state(analytics, runtime)
      {:error, error} -> whatsapp_export_error(error, runtime)
    end
  end

  @doc false
  def whatsapp_at(path, current_time) do
    cond do
      not File.regular?(path) ->
        state("whatsapp", "WhatsApp", "social", "NOT_CONNECTED", path, "LIVE", false, false,
          error_code: "SOURCE_MISSING",
          error_message: "Current local WhatsApp source does not exist"
        )

      true ->
        whatsapp_database(path, current_time)
    end
  end

  defp whatsapp_export_state(analytics, runtime) do
    analysis = analytics.analysis

    state(
      "whatsapp",
      "WhatsApp",
      "social",
      if(analytics.audit.status == "PASS", do: "CONNECTED", else: "DEGRADED"),
      analytics.source.name,
      "LOCAL_EXPORT",
      analytics.audit.status == "PASS",
      true,
      last_sync_at: analytics.last_ingest_at,
      last_success_at: analytics.last_ingest_at,
      record_count: analysis.message_count,
      error_code: if(analytics.audit.status == "PASS", do: nil, else: "AUDIT_UNVERIFIED"),
      error_message:
        if(analytics.audit.status == "PASS", do: nil, else: "WhatsApp audit is not verified"),
      metadata: %{
        privacy: "aggregate_only",
        source_exists: true,
        source_parseable: analytics.source.parseable,
        source_synthetic: analytics.source.synthetic,
        source_sha256: analytics.source.sha256,
        source_size_bytes: analytics.source.size_bytes,
        source_mtime: analytics.source.mtime,
        source_mode: analytics.source.mode,
        provenance_status: "PASS",
        trace_id: analytics.provenance.trace_id,
        normalized_digest: analytics.provenance.normalized_digest,
        aggregate_artifact_sha256: analytics.artifact_sha256,
        ingest_status: analytics.ingest.status,
        ingest_result: analytics.ingest_result,
        normalize_status: analytics.normalize.status,
        normalized_record_count: analytics.normalize.record_count,
        analysis_status: analysis.status,
        message_count: analysis.message_count,
        conversation_count: analysis.conversation_count,
        participant_count: analysis.participant_count,
        inbound_count: analysis.inbound_count,
        outbound_count: analysis.outbound_count,
        direction_unknown_count: analysis.direction_unknown_count,
        timestamp_start: analysis.timestamp_start,
        timestamp_end: analysis.timestamp_end,
        audit_status: analytics.audit.status,
        audit_hash_chain: analytics.audit.hash_chain,
        agent_runtime_status: runtime.status,
        agent_runtime_real_records: runtime.record_count
      }
    )
  end

  defp whatsapp_export_error(error, runtime) do
    state(
      "whatsapp",
      "WhatsApp",
      "social",
      "NOT_CONNECTED",
      error[:source] || "configured WhatsApp export",
      "LOCAL_EXPORT",
      false,
      false,
      error_code: error[:code] || "WHATSAPP_INGEST_FAILED",
      error_message: error[:message] || "WhatsApp export ingest failed",
      metadata: %{
        privacy: "aggregate_only",
        source_exists: error[:code] != "SOURCE_MISSING",
        source_parseable: false,
        source_synthetic: error[:code] == "SYNTHETIC_SOURCE",
        ingest_status: "FAIL",
        normalize_status: "BLOCKED",
        analysis_status: "BLOCKED",
        audit_status: "BLOCKED",
        agent_runtime_status: runtime.status,
        agent_runtime_real_records: runtime.record_count
      }
    )
  end

  def social(services) do
    whatsapp = whatsapp()
    facebook = facebook()
    telegram = telegram(services)

    messenger =
      state("messenger", "Messenger", "social", "OPTIONAL_UNAVAILABLE", nil, "LIVE", false, false,
        error_code: "SOURCE_MISSING",
        error_message: "No current local Messenger source is configured",
        metadata: %{optional: true}
      )

    records = [whatsapp, facebook, telegram, messenger]

    collection(
      "social",
      "Social connectors",
      "social",
      records,
      "privacy-reviewed local adapters"
    )
  end

  def career,
    do: career_at(@career_runtime, @career_root, @career_report, @career_project)

  @doc false
  def career_at(runtime, root, report, ihk_project) do
    runtime? = executable?(runtime)
    root? = File.dir?(root)
    report_data = json_file(report)
    report? = career_report_valid?(report_data)
    project? = File.dir?(ihk_project)
    report_stat = file_stat(report)

    status =
      cond do
        not runtime? -> "ERROR"
        not root? -> "ERROR"
        not report? -> "DEGRADED"
        true -> "READY"
      end

    error_code =
      cond do
        not runtime? -> "CAREER_RUNTIME_MISSING"
        not root? -> "CAREER_ROOT_MISSING"
        not report? -> "CAREER_HEALTH_EVIDENCE_MISSING"
        true -> nil
      end

    state(
      "career",
      "Career funnel",
      "career",
      status,
      report,
      "LOCAL_RUNTIME",
      report?,
      runtime? and root?,
      record_count: get_in(report_data || %{}, ["status", "runs"]),
      last_sync_at: stat_time(report_stat),
      last_success_at: if(status == "READY", do: stat_time(report_stat)),
      error_code: error_code,
      error_message: career_error_message(error_code),
      metadata: %{
        root_exists: root?,
        runtime_exists: runtime?,
        health_report_valid: report?,
        execution_performed: false,
        ihk_workflow: %{
          id: "career_funnel_ihk",
          optional: true,
          configuration_status: if(project?, do: "CONFIGURED", else: "NOT_CONFIGURED"),
          execution_status: if(project?, do: "REGISTERED", else: "DISABLED_BY_CONFIGURATION"),
          project_dir_exists: project?
        }
      }
    )
  end

  def knowledge(sources), do: knowledge_at(sources, @knowledge_store, @knowledge_collection)

  @doc false
  def knowledge_at(sources, store, collection \\ @knowledge_collection) do
    counts = Enum.map(sources, &Map.get(&1, :document_count, 0))
    documents = Enum.sum(counts)
    available = Enum.any?(sources, &(&1.availability == "AVAILABLE"))
    vector_store = vector_store(store, collection)

    status =
      if(available and vector_store.status in ["READY", "CONNECTED"],
        do: "READY",
        else: "DEGRADED"
      )

    state(
      "knowledge",
      "Knowledge and RAG",
      "knowledge",
      status,
      "configured knowledge paths and OpenClaw ChromaDB",
      "LOCAL_FILES",
      available and vector_store.status == "READY",
      available and vector_store.status == "READY",
      record_count: vector_store[:document_count],
      last_sync_at: latest_source_time(sources),
      last_success_at: if(vector_store.status == "READY", do: vector_store.last_index_at),
      error_code: knowledge_error_code(vector_store.status),
      error_message: knowledge_error_message(vector_store.status),
      metadata: %{vector_store: vector_store}
    )
    |> ConnectorState.attach(%{
      sources: sources,
      source_documents_count: documents,
      indexed_documents_count: vector_store[:document_count],
      indexed_chunks_count: vector_store[:record_count],
      vector_store: vector_store
    })
  end

  def backups, do: backups_at(@whatsapp_backups)

  @doc false
  def backups_at(directory) do
    files =
      if File.dir?(directory) do
        directory
        |> File.ls!()
        |> Enum.map(&Path.join(directory, &1))
        |> Enum.filter(&(File.regular?(&1) and backup_artifact?(&1)))
      else
        []
      end

    case newest(files) do
      nil ->
        state(
          "backups",
          "Backups",
          "backup",
          "NOT_CONNECTED",
          directory,
          "LOCAL_FILES",
          false,
          false,
          error_code: "BACKUP_NOT_FOUND",
          error_message: "No backup artifact was found"
        )

      path ->
        backup_state(path, length(files))
    end
  end

  def logs(filters \\ %{}) do
    audit_records =
      Audit.list()
      |> Enum.map(fn row ->
        action = field(row, :action) || field(row, :event)
        resource = field(row, :resource) || field(row, :target)
        result = field(row, :result)

        %{
          id: field(row, :id),
          time: iso(field(row, :timestamp)),
          module: "audit",
          severity: severity(result),
          message: redact("#{action} #{resource} #{result}"),
          workflow: workflow_target(resource),
          node: nil,
          service: nil,
          source: "audit hash chain"
        }
      end)

    run_records =
      RunStore.list()
      |> Enum.map(fn row ->
        %{
          id: row.id,
          time: iso(row.finished_at || row.started_at || row.queued_at),
          module: "workflow",
          severity: severity(row.status),
          message: redact("workflow #{row.workflow_id} #{row.status}: #{row.result}"),
          workflow: row.workflow_id,
          node: Map.get(row, :node),
          service: nil,
          source: "run event store"
        }
      end)

    records = (audit_records ++ run_records) |> filter_logs(filters) |> Enum.take(200)

    state(
      "logs",
      "Operational logs",
      "logs",
      "READY",
      "audit and run event stores",
      "LOCAL_EVENT_STORE",
      true,
      true,
      record_count: length(records),
      last_success_at: now()
    )
    |> ConnectorState.attach(%{records: records, filters: filters, updated_at: now()})
  rescue
    error ->
      state(
        "logs",
        "Operational logs",
        "logs",
        "ERROR",
        "audit and run event stores",
        "LOCAL_EVENT_STORE",
        false,
        false,
        error_code: "LOG_READ_FAILED",
        error_message: Exception.message(error)
      )
      |> ConnectorState.attach(%{records: [], updated_at: now()})
  end

  def reporting(modules) when is_list(modules) do
    counts = Enum.frequencies_by(modules, & &1.status)

    state(
      "reporting",
      "Runtime reporting",
      "reporting",
      "READY",
      "live module connector states",
      "DERIVED_LIVE",
      true,
      true,
      record_count: length(modules),
      last_success_at: now(),
      metadata: %{status_counts: counts}
    )
    |> ConnectorState.attach(%{modules: modules, status_counts: counts, generated_at: now()})
  end

  defp i7_node do
    started = System.monotonic_time(:millisecond)

    with true <- File.regular?(@i7_status),
         {output, code} <- System.cmd(@i7_status, [], stderr_to_stdout: true),
         true <- code == 0 and online_text?(output) do
      state(
        "node-i7",
        "i7 node",
        "node",
        "ONLINE",
        @i7_status,
        "AUTHORIZED_LOCAL_PROBE",
        true,
        true,
        latency_ms: elapsed(started),
        last_success_at: now(),
        metadata: %{probe_output: String.trim(redact(output))}
      )
      |> ConnectorState.attach(%{
        node_id: "i7",
        hostname: "i7",
        load: nil,
        ram: nil,
        uptime_seconds: nil,
        services: []
      })
    else
      _ ->
        state(
          "node-i7",
          "i7 node",
          "node",
          "OPTIONAL_UNAVAILABLE",
          @i7_status,
          "AUTHORIZED_LOCAL_PROBE",
          false,
          false,
          latency_ms: elapsed(started),
          error_code: "NODE_UNREACHABLE",
          error_message: "Authorized i7 status probe did not confirm reachability",
          metadata: %{optional: true}
        )
        |> ConnectorState.attach(%{
          node_id: "i7",
          hostname: nil,
          load: nil,
          ram: nil,
          uptime_seconds: nil,
          services: []
        })
    end
  rescue
    error ->
      state(
        "node-i7",
        "i7 node",
        "node",
        "ERROR",
        @i7_status,
        "AUTHORIZED_LOCAL_PROBE",
        false,
        false,
        error_code: "NODE_PROBE_FAILED",
        error_message: Exception.message(error)
      )
      |> ConnectorState.attach(%{node_id: "i7", services: []})
  end

  defp ollama_local do
    started = System.monotonic_time(:millisecond)

    case System.cmd("ollama", ["list"], stderr_to_stdout: true) do
      {body, 0} ->
        models = parse_models(body, "local-ryzen")
        loaded = loaded_models()

        state(
          "ollama-local",
          "Local Ollama",
          "ai_runtime",
          "ONLINE",
          "ollama list / ollama ps",
          "LOCAL_RUNTIME",
          true,
          true,
          latency_ms: elapsed(started),
          record_count: length(models),
          last_success_at: now(),
          metadata: %{
            endpoint: "local CLI",
            node: "local-ryzen",
            memory_usage: nil,
            last_inference: nil
          }
        )
        |> ConnectorState.attach(%{
          models: models,
          loaded_models: loaded,
          endpoint: "local CLI",
          node: "local-ryzen"
        })

      {body, _} ->
        state(
          "ollama-local",
          "Local Ollama",
          "ai_runtime",
          "OPTIONAL_UNAVAILABLE",
          "ollama list",
          "LOCAL_RUNTIME",
          false,
          false,
          latency_ms: elapsed(started),
          error_code: "OLLAMA_UNAVAILABLE",
          error_message: String.slice(redact(body), 0, 300)
        )
        |> ConnectorState.attach(%{
          models: [],
          loaded_models: [],
          endpoint: "local CLI",
          node: "local-ryzen"
        })
    end
  rescue
    _ ->
      state(
        "ollama-local",
        "Local Ollama",
        "ai_runtime",
        "UNAVAILABLE",
        "ollama list",
        "LOCAL_RUNTIME",
        false,
        false,
        error_code: "OLLAMA_COMMAND_UNAVAILABLE",
        error_message: "Ollama command could not be executed"
      )
      |> ConnectorState.attach(%{
        models: [],
        loaded_models: [],
        endpoint: "local CLI",
        node: "local-ryzen"
      })
  end

  defp i7_ai do
    node = i7_node()
    inventory_result = if node.status == "READY", do: i7_inventory_probe(), else: :not_run
    i7_ai_from(node, inventory_result)
  end

  @doc false
  def i7_ai_from(node, inventory_result) do
    case {node, inventory_result} do
      {%{status: status}, {:ok, body, %{real_data: true, synthetic: false}}}
      when status in ["READY", "ONLINE"] and is_binary(body) ->
        models = parse_remote_models(body)

        if models == [] do
          i7_inventory_degraded("MODEL_INVENTORY_EMPTY", "Remote Ollama returned no models")
        else
          state(
            "ollama-i7",
            "i7 Ollama",
            "ai_runtime",
            "ONLINE",
            @i7_inventory_source,
            "REMOTE_RUNTIME",
            true,
            true,
            record_count: length(models),
            last_success_at: now(),
            metadata: %{endpoint: "remote CLI", node: "i7"}
          )
          |> ConnectorState.attach(%{
            models: models,
            loaded_models: [],
            endpoint: "remote CLI",
            node: "i7"
          })
        end

      {%{status: status}, {:error, reason}} when status in ["READY", "ONLINE"] ->
        i7_inventory_degraded(
          "MODEL_INVENTORY_PROBE_FAILED",
          "Remote Ollama inventory probe failed: #{inventory_error(reason)}"
        )

      {%{status: status}, _} when status in ["READY", "ONLINE"] ->
        i7_inventory_degraded(
          "MODEL_INVENTORY_EVIDENCE_INVALID",
          "Remote Ollama inventory did not provide real, non-synthetic CLI evidence"
        )

      _ ->
        state(
          "ollama-i7",
          "i7 Ollama",
          "ai_runtime",
          "UNAVAILABLE",
          @i7_status,
          "REMOTE_RUNTIME",
          false,
          false,
          error_code: "NODE_UNREACHABLE",
          error_message: "i7 node is not reachable",
          metadata: %{optional: true}
        )
        |> ConnectorState.attach(%{models: [], loaded_models: [], endpoint: nil, node: "i7"})
    end
  end

  defp i7_inventory_probe do
    case System.cmd(
           "ssh",
           [
             "-o",
             "BatchMode=yes",
             "-o",
             "ConnectTimeout=5",
             @i7_ssh_host,
             "ollama",
             "list"
           ],
           stderr_to_stdout: true
         ) do
      {body, 0} -> {:ok, body, %{real_data: true, synthetic: false}}
      {body, code} -> {:error, {:exit_status, code, String.slice(redact(body), 0, 300)}}
    end
  rescue
    error -> {:error, {:command_failed, Exception.message(error)}}
  end

  defp i7_inventory_degraded(error_code, error_message) do
    state(
      "ollama-i7",
      "i7 Ollama",
      "ai_runtime",
      "DEGRADED",
      @i7_inventory_source,
      "REMOTE_RUNTIME",
      false,
      true,
      error_code: error_code,
      error_message: error_message
    )
    |> ConnectorState.attach(%{
      models: [],
      loaded_models: [],
      endpoint: "remote CLI",
      node: "i7"
    })
  end

  defp whatsapp_database(path, current_time) do
    started = System.monotonic_time(:millisecond)
    stat = File.stat!(path, time: :posix)
    mode_ok = Bitwise.band(stat.mode, 0o077) == 0
    integrity = sqlite(path, "PRAGMA quick_check;") == {:ok, "ok"}
    captured = sqlite_integer(path, "SELECT COUNT(*) FROM captured_messages;")
    real = sqlite_integer(path, "SELECT COUNT(*) FROM captured_messages WHERE synthetic = 0;")

    synthetic =
      sqlite_integer(path, "SELECT COUNT(*) FROM captured_messages WHERE synthetic != 0;")

    schema = captured != nil and real != nil and synthetic != nil
    age = DateTime.to_unix(current_time) - stat.mtime
    current = age <= 7 * 24 * 60 * 60
    conditions = integrity and schema and mode_ok and current and is_integer(real) and real > 0

    status =
      if conditions, do: "CONNECTED", else: whatsapp_failure_status(integrity, schema, current)

    state(
      "whatsapp",
      "WhatsApp",
      "social",
      status,
      path,
      "LIVE",
      is_integer(real) and real > 0,
      false,
      reachable: integrity,
      latency_ms: elapsed(started),
      record_count: real,
      last_sync_at: iso_unix(stat.mtime),
      last_success_at: if(conditions, do: now()),
      error_code: whatsapp_error(integrity, schema, mode_ok, current, real),
      error_message: whatsapp_message(integrity, schema, mode_ok, current, real),
      metadata: %{
        source_exists: true,
        source_current: current,
        privacy_review: if(mode_ok, do: "PASS", else: "FAIL"),
        contract_valid: schema,
        healthcheck: if(integrity, do: "PASS", else: "FAIL"),
        synthetic_excluded: true,
        synthetic_records_present: synthetic,
        source_age_seconds: age,
        source_mode: Integer.to_string(Bitwise.band(stat.mode, 0o777), 8)
      }
    )
  rescue
    error ->
      state("whatsapp", "WhatsApp", "social", "ERROR", path, "LIVE", false, false,
        error_code: "SOURCE_READ_FAILED",
        error_message: Exception.message(error)
      )
  end

  defp facebook do
    if File.regular?(@facebook_source) do
      state(
        "facebook",
        "Facebook",
        "social",
        "DEGRADED",
        @facebook_source,
        "ANALYTICS_ONLY",
        true,
        false,
        reachable: true,
        error_code: "ANALYTICS_ONLY",
        error_message: "Aggregate analytics source is not a live connector",
        metadata: %{classification: "ANALYTICS_ONLY"}
      )
    else
      state(
        "facebook",
        "Facebook",
        "social",
        "NOT_CONNECTED",
        @facebook_source,
        "ANALYTICS_ONLY",
        false,
        false,
        error_code: "SOURCE_MISSING",
        error_message: "Configured aggregate analytics source is absent",
        metadata: %{classification: "ANALYTICS_ONLY"}
      )
    end
  end

  defp telegram(services) do
    candidates =
      services
      |> Map.get(:services, [])
      |> Enum.filter(&String.contains?(String.downcase(&1.name), "telegram"))

    active = Enum.filter(candidates, &(&1.active_state == "active"))
    status = if(active == [], do: "NOT_CONNECTED", else: "ONLINE")

    state(
      "telegram",
      "Telegram",
      "social",
      status,
      "systemd service discovery",
      "LIVE",
      active != [],
      active != [],
      record_count: length(active),
      last_success_at: if(active == [], do: nil, else: now()),
      error_code: if(active == [], do: "NO_ACTIVE_CONNECTOR"),
      error_message: if(active == [], do: "No active Telegram service was detected"),
      metadata: %{classification: "LIVE", detected_services: Enum.map(candidates, & &1.name)}
    )
  end

  defp backup_state(path, count) do
    stat = File.stat!(path, time: :posix)
    integrity = sqlite(path, "PRAGMA quick_check;")
    schema = sqlite(path, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
    content_count = sqlite_integer(path, "SELECT COUNT(*) FROM captured_messages;")

    verified =
      integrity == {:ok, "ok"} and schema_contains?(schema, "captured_messages") and
        is_integer(content_count)

    checksum = if(verified, do: sha256(path))

    state(
      "backups",
      "Backups",
      "backup",
      if(verified, do: "READY", else: "DEGRADED"),
      path,
      "LOCAL_BACKUP",
      true,
      true,
      record_count: count,
      last_sync_at: iso_unix(stat.mtime),
      last_success_at: if(verified, do: now()),
      error_code: if(verified, do: nil, else: "CONTENT_VERIFICATION_INCOMPLETE"),
      error_message:
        if(verified, do: nil, else: "Latest database artifact failed integrity or content checks"),
      metadata: %{
        last_backup: Path.basename(path),
        target: Path.dirname(path),
        size_bytes: stat.size,
        checksum_sha256: checksum,
        manifest: "NOT_AVAILABLE",
        content_records: content_count,
        verification_result: if(verified, do: "PASS", else: "INCOMPLETE"),
        verification_method: "sqlite quick_check + schema probe + content query + sha256",
        verified_at: if(verified, do: now())
      }
    )
  end

  defp vector_store(path, collection) do
    if File.regular?(path) do
      stat = File.stat!(path, time: :posix)
      escaped = String.replace(collection, "'", "''")

      record_count =
        sqlite_integer(
          path,
          "SELECT COUNT(*) FROM embeddings WHERE segment_id IN (SELECT s.id FROM segments s JOIN collections c ON c.id=s.collection WHERE c.name='#{escaped}');"
        )

      document_count =
        sqlite_integer(
          path,
          "SELECT COUNT(DISTINCT COALESCE(CAST(m.int_value AS TEXT), m.string_value)) FROM embeddings e JOIN embedding_metadata m ON m.id=e.id WHERE m.key='document_id' AND e.segment_id IN (SELECT s.id FROM segments s JOIN collections c ON c.id=s.collection WHERE c.name='#{escaped}');"
        )

      query_probe =
        sqlite(
          path,
          "SELECT id FROM embeddings WHERE segment_id IN (SELECT s.id FROM segments s JOIN collections c ON c.id=s.collection WHERE c.name='#{escaped}') LIMIT 1;"
        )

      valid =
        is_integer(document_count) and document_count > 0 and
          is_integer(record_count) and record_count > 0 and
          match?({:ok, value} when value != "", query_probe)

      %{
        status: if(valid, do: "READY", else: "ERROR"),
        source: Path.basename(path),
        health: if(valid, do: "AVAILABLE", else: "ERROR"),
        collection: collection,
        index_valid: valid,
        query_probe: if(valid, do: "PASS", else: "FAIL"),
        document_count: document_count,
        record_count: record_count,
        last_index_at: iso_unix(stat.mtime),
        verification: "collection record probe"
      }
    else
      %{
        status: "NOT_CONNECTED",
        source: nil,
        health: "UNKNOWN",
        collection: collection,
        index_valid: false,
        query_probe: "NOT_RUN",
        document_count: nil,
        record_count: nil,
        last_index_at: nil
      }
    end
  end

  defp collection(id, name, kind, records, source) do
    positive = Enum.any?(records, &(&1.status == "READY"))
    degraded = Enum.any?(records, &(&1.status == "DEGRADED"))

    required_unavailable =
      Enum.any?(records, &(&1.status in ["UNAVAILABLE", "UNKNOWN", "CONFIGURATION_REQUIRED"]))

    status =
      cond do
        positive and (degraded or required_unavailable) -> "DEGRADED"
        positive -> "READY"
        degraded -> "DEGRADED"
        Enum.any?(records, &(&1.status == "UNKNOWN")) -> "UNKNOWN"
        true -> "UNAVAILABLE"
      end

    state(id, name, kind, status, source, "AGGREGATE", positive, positive,
      record_count: length(records),
      last_success_at: if(positive, do: now()),
      metadata: %{status_counts: Enum.frequencies_by(records, & &1.status)}
    )
    |> ConnectorState.attach(%{
      records: records,
      updated_at: now(),
      availability: availability(status)
    })
  end

  defp field(row, key) when is_map(row),
    do: Map.get(row, key) || Map.get(row, Atom.to_string(key))

  defp state(id, name, kind, status, source, source_type, real_data, reachable, opts) do
    ConnectorState.build(%{
      id: id,
      name: name,
      kind: kind,
      status: status,
      health: health(status),
      source: source,
      source_type: source_type,
      real_data: real_data,
      synthetic: Keyword.get(opts, :synthetic, false),
      enabled: Keyword.get(opts, :enabled, true),
      reachable: Keyword.get(opts, :reachable, reachable),
      last_sync_at: Keyword.get(opts, :last_sync_at),
      last_success_at: Keyword.get(opts, :last_success_at),
      latency_ms: Keyword.get(opts, :latency_ms),
      record_count: Keyword.get(opts, :record_count),
      error_code: Keyword.get(opts, :error_code),
      error_message: Keyword.get(opts, :error_message),
      metadata: Keyword.get(opts, :metadata, %{})
    })
  end

  defp health(status) when status in ["CONNECTED", "ONLINE", "READY"], do: "HEALTHY"
  defp health("DEGRADED"), do: "DEGRADED"
  defp health("CONFIGURATION_REQUIRED"), do: "DEGRADED"
  defp health("OPTIONAL_UNAVAILABLE"), do: "UNAVAILABLE"
  defp health("UNKNOWN"), do: "UNKNOWN"
  defp health(status), do: status

  defp availability(status) when status in ["CONNECTED", "ONLINE", "READY", "DEGRADED"],
    do: "AVAILABLE"

  defp availability(status), do: status

  defp os_release do
    "/etc/os-release"
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&String.split(&1, "=", parts: 2))
    |> Enum.filter(&(length(&1) == 2))
    |> Map.new(fn [key, value] -> {String.downcase(key), String.trim(value, "\"")} end)
    |> Map.take(["name", "version", "pretty_name"])
  end

  defp cpu_info do
    body = File.read!("/proc/cpuinfo")
    model = Regex.run(~r/^model name\s*:\s*(.+)$/m, body, capture: :all_but_first) |> first()
    %{model: model, logical_processors: Regex.scan(~r/^processor\s*:/m, body) |> length()}
  end

  defp load_info do
    case File.read!("/proc/loadavg") |> String.split() do
      [one, five, fifteen | _] ->
        %{one: number(one), five: number(five), fifteen: number(fifteen)}

      _ ->
        %{}
    end
  end

  defp meminfo do
    "/proc/meminfo"
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Map.new(fn line ->
      [key, value | _] = String.split(line)
      {String.trim_trailing(key, ":"), String.to_integer(value) * 1024}
    end)
  end

  defp memory_values(values, "Mem") do
    total = values["MemTotal"]
    available = values["MemAvailable"]
    %{total_bytes: total, available_bytes: available, used_bytes: subtract(total, available)}
  end

  defp memory_values(values, "Swap") do
    total = values["SwapTotal"]
    free = values["SwapFree"]
    %{total_bytes: total, free_bytes: free, used_bytes: subtract(total, free)}
  end

  defp disk_info do
    case System.cmd("df", ["-B1", "--output=size,used,avail,pcent", "/"], stderr_to_stdout: true) do
      {body, 0} ->
        case body |> String.split("\n", trim: true) |> List.last() |> String.split() do
          [total, used, available, percent] ->
            %{
              total_bytes: String.to_integer(total),
              used_bytes: String.to_integer(used),
              available_bytes: String.to_integer(available),
              used_percent: percent
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp temperatures do
    "/sys/class/thermal/thermal_zone*/temp"
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case File.read(path) do
        {:ok, raw} -> [{Path.basename(Path.dirname(path)), number(String.trim(raw)) / 1000}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp network_info do
    "/sys/class/net/*/operstate"
    |> Path.wildcard()
    |> Map.new(fn path -> {Path.basename(Path.dirname(path)), read_trim(path)} end)
  end

  defp process_count do
    case File.ls("/proc") do
      {:ok, names} -> Enum.count(names, &Regex.match?(~r/^\d+$/, &1))
      _ -> nil
    end
  end

  defp loaded_models do
    case System.cmd("ollama", ["ps"], stderr_to_stdout: true) do
      {body, 0} -> parse_models(body, "local-ryzen")
      _ -> []
    end
  rescue
    _ -> []
  end

  defp parse_models(body, node) do
    parse_models(body, node, "ollama CLI")
  end

  defp parse_remote_models(body) do
    case String.split(body, "\n", trim: true) do
      [header | _] ->
        if Regex.match?(~r/^NAME\s+ID\s+SIZE\s+MODIFIED\s*$/, header) do
          parse_models(body, "i7", "remote ollama CLI")
        else
          []
        end

      _ ->
        []
    end
  end

  defp parse_models(body, node, source) do
    body
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.flat_map(fn line ->
      case String.split(line, ~r/\s{2,}/, trim: true) do
        [name | fields] when name != "" ->
          [%{name: name, node: node, details: Enum.join(fields, " | "), source: source}]

        _ ->
          []
      end
    end)
  end

  defp inventory_error({:exit_status, code, body}), do: "exit #{code}: #{body}"
  defp inventory_error({:command_failed, message}), do: message
  defp inventory_error(reason), do: inspect(reason)

  defp sqlite(path, sql) do
    case System.cmd("sqlite3", ["-readonly", "-batch", "-noheader", path, sql],
           stderr_to_stdout: true
         ) do
      {body, 0} -> {:ok, String.trim(body)}
      {body, code} -> {:error, {code, String.slice(redact(body), 0, 200)}}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp sqlite_integer(path, sql) do
    case sqlite(path, sql) do
      {:ok, value} ->
        case Integer.parse(value) do
          {integer, ""} -> integer
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp json_file(path) do
    with {:ok, body} <- File.read(path),
         {:ok, data} when is_map(data) <- Jason.decode(body) do
      data
    else
      _ -> nil
    end
  end

  defp career_report_valid?(report) when is_map(report) do
    get_in(report, ["doctor", "passed"]) == true and
      get_in(report, ["status", "fail_closed"]) == true and
      get_in(report, ["status", "external_actions"]) == "BLOCKED" and
      is_integer(get_in(report, ["status", "runs"]))
  end

  defp career_report_valid?(_), do: false

  defp career_error_message("CAREER_RUNTIME_MISSING"), do: "Career runtime is not executable"
  defp career_error_message("CAREER_ROOT_MISSING"), do: "Career root does not exist"

  defp career_error_message("CAREER_HEALTH_EVIDENCE_MISSING"),
    do: "Latest Career health report is missing or invalid"

  defp career_error_message(_), do: nil

  defp knowledge_error_code("NOT_CONNECTED"), do: "VECTOR_STORE_NOT_CONNECTED"
  defp knowledge_error_code("ERROR"), do: "VECTOR_STORE_HEALTHCHECK_FAILED"
  defp knowledge_error_code(_), do: nil

  defp knowledge_error_message("NOT_CONNECTED"), do: "No configured vector store was detected"
  defp knowledge_error_message("ERROR"), do: "Configured vector store failed validation"
  defp knowledge_error_message(_), do: nil

  defp backup_artifact?(path), do: Path.extname(path) in [".db", ".sqlite", ".sqlite3"]

  defp schema_contains?({:ok, tables}, table),
    do: tables |> String.split("\n", trim: true) |> Enum.member?(table)

  defp schema_contains?(_, _), do: false

  defp sha256(path) do
    path
    |> File.stream!(64 * 1024, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp file_stat(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> stat
      _ -> nil
    end
  end

  defp stat_time(nil), do: nil
  defp stat_time(stat), do: iso_unix(stat.mtime)

  defp newest([]), do: nil
  defp newest(paths), do: Enum.max_by(paths, fn path -> File.stat!(path, time: :posix).mtime end)

  defp executable?(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.type == :regular and Bitwise.band(stat.mode, 0o111) != 0
      _ -> false
    end
  end

  defp online_text?(text),
    do: Regex.match?(~r/(ONLINE|EIN|ON\b)/i, text) and not Regex.match?(~r/(OFFLINE|AUS)/i, text)

  defp whatsapp_failure_status(false, _schema, _current), do: "ERROR"
  defp whatsapp_failure_status(_integrity, false, _current), do: "ERROR"
  defp whatsapp_failure_status(_integrity, _schema, false), do: "DEGRADED"
  defp whatsapp_failure_status(_, _, _), do: "NOT_CONNECTED"

  defp whatsapp_error(false, _, _, _, _), do: "HEALTHCHECK_FAILED"
  defp whatsapp_error(_, false, _, _, _), do: "CONTRACT_INVALID"
  defp whatsapp_error(_, _, false, _, _), do: "PRIVACY_REVIEW_FAILED"
  defp whatsapp_error(_, _, _, false, _), do: "SOURCE_STALE"

  defp whatsapp_error(_, _, _, _, count) when not is_integer(count) or count <= 0,
    do: "REAL_DATA_ABSENT"

  defp whatsapp_error(_, _, _, _, _), do: nil

  defp whatsapp_message(false, _, _, _, _), do: "SQLite integrity check failed"
  defp whatsapp_message(_, false, _, _, _), do: "Required aggregate capture schema is unavailable"
  defp whatsapp_message(_, _, false, _, _), do: "Source permissions expose private data"
  defp whatsapp_message(_, _, _, false, _), do: "Current local source is stale"

  defp whatsapp_message(_, _, _, _, count) when not is_integer(count) or count <= 0,
    do: "No real non-synthetic records are present"

  defp whatsapp_message(_, _, _, _, _), do: nil

  defp filter_logs(records, filters) do
    Enum.filter(records, fn row ->
      Enum.all?([:module, :severity, :workflow, :node, :service], fn field ->
        requested = Map.get(filters, field) || Map.get(filters, Atom.to_string(field))
        requested in [nil, ""] or to_string(Map.get(row, field) || "") == to_string(requested)
      end)
    end)
  end

  defp severity(value) when value in [:failure, :blocked, "FAILED", "BLOCKED", "ERROR"],
    do: "ERROR"

  defp severity(value) when value in ["RUNNING", "QUEUED"], do: "INFO"
  defp severity(_), do: "INFO"
  defp workflow_target(target) when is_binary(target), do: target
  defp workflow_target(_), do: nil

  defp latest_source_time(sources),
    do:
      sources
      |> Enum.map(&Map.get(&1, :last_update))
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> nil end)

  defp first([value | _]), do: value
  defp first(_), do: nil
  defp first_number(path), do: path |> File.read!() |> String.split() |> hd() |> number()

  defp number(value) do
    case Float.parse(value) do
      {number, _} -> number
      _ -> nil
    end
  end

  defp subtract(a, b) when is_integer(a) and is_integer(b), do: a - b
  defp subtract(_, _), do: nil

  defp read_trim(path) do
    case File.read(path) do
      {:ok, value} -> String.trim(value)
      _ -> nil
    end
  end

  defp redact(value) when is_binary(value),
    do: Regex.replace(@secret_pattern, value, "[REDACTED]")

  defp redact(value), do: inspect(value)
  defp iso(nil), do: nil
  defp iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp iso(value), do: to_string(value)
  defp iso_unix(value), do: value |> DateTime.from_unix!() |> DateTime.to_iso8601()
  defp elapsed(started), do: max(System.monotonic_time(:millisecond) - started, 0)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
