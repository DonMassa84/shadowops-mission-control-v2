defmodule ShadowOpsApi do
  @moduledoc "Real source-backed API context for the local ShadowOps control plane."

  alias ShadowOpsCore.{
    ApprovalStore,
    Audit,
    RunStore,
    RuntimeSources,
    SocialRuntime,
    WorkflowExecutor
  }

  alias ShadowOps.Social.FacebookCommunicationBalance
  alias WorkflowEngine.Registry

  def health do
    with {:ok, summary} <- Registry.summary() do
      {:ok, %{status: "ok", service: "shadowops_web", registry: summary}}
    end
  end

  def system_overview do
    workflows = result_or_unavailable(list_workflows(), :workflows)
    services = RuntimeSources.services()
    connectors = connectors(services)

    %{
      readiness: readiness_status(),
      system: RuntimeSources.system(),
      workflows: workflows,
      runs: run_overview(),
      services: services,
      nodes: RuntimeSources.nodes(),
      agents: RuntimeSources.agents(),
      ai: RuntimeSources.ai(),
      approvals: approval_overview(),
      audit: audit_status(),
      security: ShadowOpsWeb.SecurityStatus.check(),
      knowledge: RuntimeSources.knowledge(),
      evidence: RuntimeSources.evidence(),
      connectors: connectors,
      career: RuntimeSources.career(),
      backups: RuntimeSources.backups()
    }
  end

  def list_workflows do
    with {:ok, registry} <- Registry.load() do
      {:ok,
       registry["workflows"]
       |> Enum.map(fn {id, workflow} -> workflow_view(id, workflow) end)
       |> Enum.sort_by(& &1["id"])}
    end
  end

  def get_workflow(id) do
    with {:ok, registry} <- Registry.load() do
      case Map.fetch(registry["workflows"], id) do
        {:ok, workflow} -> {:ok, workflow_view(id, workflow)}
        :error -> {:error, :not_found}
      end
    end
  end

  def list_runs, do: {:ok, Enum.map(RunStore.list(), &run_view/1)}
  def runs, do: run_overview()
  def audit, do: audit_status()

  def get_run(id) do
    case RunStore.get(id) do
      {:ok, run} -> {:ok, run_view(run)}
      error -> error
    end
  end

  def list_nodes, do: {:ok, RuntimeSources.nodes().records}
  def get_node(id), do: RuntimeSources.node(id)
  def list_audit_events, do: {:ok, Audit.list()}
  def list_approvals, do: {:ok, ApprovalStore.list()}
  def approvals, do: approval_overview()
  def get_approval(id), do: ApprovalStore.get(id)
  def create_approval(attrs), do: ApprovalStore.create(attrs)
  def approve(id, approver), do: ApprovalStore.approve(id, approver)
  def reject(id, approver), do: ApprovalStore.reject(id, approver)
  def services, do: RuntimeSources.services()
  def get_service(id), do: RuntimeSources.service(id)
  def system, do: RuntimeSources.system()
  def nodes, do: RuntimeSources.nodes()
  def agents, do: RuntimeSources.agents()
  def ai, do: RuntimeSources.ai()
  def knowledge, do: RuntimeSources.knowledge()
  def evidence, do: RuntimeSources.evidence()
  def legal, do: ShadowOpsWeb.LegalRegistry.snapshot()
  def logs(filters \\ %{}), do: RuntimeSources.logs(filters)
  def career, do: RuntimeSources.career()
  def backups, do: RuntimeSources.backups()
  def social, do: RuntimeSources.social() |> SocialRuntime.overlay()
  def whatsapp, do: RuntimeSources.whatsapp()

  def facebook_balance do
    case FacebookCommunicationBalance.snapshot() do
      {:ok, snapshot} ->
        snapshot

      {:error, reason} ->
        %{
          "status" => "UNAVAILABLE",
          "reason" => to_string(reason),
          "counts" => %{},
          "sufficient_data_count" => nil,
          "proportions" => %{},
          "chats" => [],
          "knowledge_aggregates" => %{},
          "privacy" => %{
            "classification" => "PSEUDONYMIZED_AGGREGATE",
            "raw_messages" => false,
            "raw_names" => false,
            "identity_maps" => false,
            "nlp_interpretation" => false
          }
        }
    end
  end

  def connectors do
    connectors(RuntimeSources.services())
  end

  def connector(id) do
    case Enum.find(connectors().records, &(&1.id == id)) do
      nil -> {:error, :not_found}
      connector -> {:ok, connector}
    end
  end

  def reporting do
    records = connectors().records ++ [career(), knowledge(), backups()]
    RuntimeSources.reporting(records)
  end

  def execute_workflow(workflow_id, actor, input, context \\ %{}) do
    approval_id = context[:approval_id] || context["approval_id"]

    with {:ok, workflow} <- get_workflow(workflow_id),
         :ok <- executable_workflow(workflow),
         {:ok, run} <-
           RunStore.queue(workflow_id, actor, %{
             evidence_ref: input["evidence_ref"],
             trigger: input["trigger"] || "api",
             node: "local-ryzen"
           }) do
      case authorize_execution(approval_id, workflow_id) do
        {:ok, _approval} ->
          execute_queued(run, workflow, actor, input)

        {:error, _reason} ->
          {:ok, blocked} = RunStore.block(run.id, actor, "approval required")
          {:error, {:approval_required, blocked}}
      end
    end
  end

  def execute_node_action(node_id, action, actor, _context \\ %{}) do
    case RuntimeSources.node_action(node_id, action) do
      {:ok, result} ->
        Audit.record(:node_action, actor, node_id, :success, %{action: action})
        {:ok, result}

      {:error, reason} ->
        Audit.record(:node_action, actor, node_id, :blocked, %{
          action: action,
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  def execute_service_action(id, action, actor) do
    case RuntimeSources.service_action(id, action) do
      {:ok, result} ->
        Audit.record(:service_action, actor, id, :success, %{action: action})
        {:ok, result}

      {:error, reason} ->
        Audit.record(:service_action, actor, id, :blocked, %{
          action: action,
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  defp authorize_execution(nil, _workflow_id), do: {:error, :approval_required}

  defp authorize_execution(approval_id, workflow_id),
    do: ApprovalStore.validate(approval_id, "workflow.execute", workflow_id, "L2")

  defp execute_queued(run, workflow, actor, input) do
    with {:ok, running} <- RunStore.start(run.id, actor) do
      case WorkflowExecutor.execute(workflow, input) do
        {:ok, result} -> RunStore.succeed(running.id, actor, result.summary, result.exit_code)
        {:error, result} -> RunStore.fail(running.id, actor, result.summary, result.exit_code)
      end
    end
  end

  defp audit_status do
    case Audit.verify() do
      {:ok, result} ->
        Map.merge(result, %{
          id: "audit",
          name: "Audit chain",
          kind: "audit",
          status: "READY",
          health: "HEALTHY",
          availability: "AVAILABLE",
          state: "VALID",
          source: "audit hash chain",
          source_type: "LOCAL_HASH_CHAIN",
          real_data: true,
          synthetic: false,
          enabled: true,
          reachable: true,
          last_sync_at: nil,
          last_success_at:
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
          latency_ms: nil,
          record_count: result.entries,
          error_code: nil,
          error_message: nil,
          metadata: %{}
        })

      {:error, result} ->
        Map.merge(result, %{
          id: "audit",
          name: "Audit chain",
          kind: "audit",
          status: "ERROR",
          health: "ERROR",
          availability: "AVAILABLE",
          state: "INVALID",
          source: "audit hash chain",
          source_type: "LOCAL_HASH_CHAIN",
          real_data: true,
          synthetic: false,
          enabled: true,
          reachable: true,
          last_sync_at: nil,
          last_success_at: nil,
          latency_ms: nil,
          record_count: result[:entries],
          error_code: "AUDIT_CHAIN_INVALID",
          error_message: "Audit hash-chain verification failed",
          metadata: %{}
        })
    end
  end

  defp readiness_status do
    registry = match?({:ok, _}, Registry.summary())
    audit = match?({:ok, %{valid: true}}, Audit.verify())
    {:ok, learning} = ShadowOpsCore.LearningFocus.load()
    ready = registry and audit and learning["availability"] == "AVAILABLE"

    %{
      availability: "AVAILABLE",
      state: if(ready, do: "READY", else: "FAIL"),
      detail: %{registry: registry, audit_chain: audit, learning_focus: learning["availability"]}
    }
  end

  defp connectors(services) do
    social = ShadowOpsCore.OperationalSources.social(services) |> SocialRuntime.overlay()
    ai = RuntimeSources.ai()
    records = social.records ++ ai.records

    RuntimeSources.reporting(records)
    |> Map.merge(%{
      id: "connectors",
      name: "Module connectors",
      kind: "connectors",
      records: records,
      record_count: length(records),
      source: "canonical operational adapters"
    })
  end

  defp workflow_view(id, workflow) do
    runs = RunStore.list() |> Enum.filter(&(&1.workflow_id == id)) |> Enum.map(&run_view/1)
    last_run = List.first(runs)
    execution_status = workflow_execution_status(id, workflow)

    workflow
    |> Map.put("id", id)
    |> Map.put("execution_status", execution_status)
    |> Map.put("executable", execution_status == "EXECUTABLE")
    |> Map.put("runs", runs)
    |> Map.put("last_run", last_run)
    |> Map.put("dependencies", workflow["dependencies"] || [])
    |> Map.put("evidence", workflow["evidence"] || workflow["documentation"])
  end

  defp workflow_execution_status(
         "career_funnel_ihk",
         %{"status" => "DISABLED_BY_CONFIGURATION"}
       ),
       do: "DISABLED_BY_CONFIGURATION"

  defp workflow_execution_status("career_funnel_ihk", _workflow),
    do: RuntimeSources.career().status

  defp workflow_execution_status(_id, %{"status" => "DISABLED"}), do: "DISABLED"

  defp workflow_execution_status(_id, %{"status" => "VERIFIED_EXECUTABLE", "runtime" => runtime}) do
    if is_binary(runtime) and Path.type(runtime) == :absolute and executable?(runtime),
      do: "EXECUTABLE",
      else: "BLOCKED_CONFIGURATION"
  end

  defp workflow_execution_status(_id, _workflow), do: "REGISTERED"

  defp executable_workflow(%{"status" => status})
       when status in ["REGISTRY_ONLY", "DISABLED", "DISABLED_BY_CONFIGURATION"],
       do: {:error, {:workflow_not_executable, status}}

  defp executable_workflow(%{"runtime" => runtime}) when is_binary(runtime) and runtime != "",
    do: :ok

  defp executable_workflow(workflow),
    do: {:error, {:workflow_not_executable, workflow["execution_status"]}}

  defp executable?(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.type == :regular and Bitwise.band(stat.mode, 0o111) != 0
      _ -> false
    end
  end

  defp run_view(run) do
    run
    |> Map.from_struct()
    |> Map.put(:duration_ms, duration_ms(run.started_at, run.finished_at))
    |> Map.put(:stdout_reference, run.stdout_ref)
    |> Map.put(:stderr_reference, run.stderr_ref)
    |> Map.put(:evidence, run.evidence_ref)
  end

  defp duration_ms(%DateTime{} = started, %DateTime{} = finished),
    do: DateTime.diff(finished, started, :millisecond)

  defp duration_ms(_, _), do: nil

  defp run_overview do
    records = Enum.map(RunStore.list(), &run_view/1)

    %{
      id: "runs",
      name: "Workflow runs",
      kind: "run_store",
      availability: "AVAILABLE",
      status: "READY",
      health: "HEALTHY",
      source: "run event store",
      source_type: "LOCAL_EVENT_STORE",
      real_data: true,
      synthetic: false,
      enabled: true,
      reachable: true,
      last_sync_at: nil,
      last_success_at: nil,
      latency_ms: nil,
      records: records,
      record_count: length(records),
      error_code: nil,
      error_message: nil,
      metadata: %{}
    }
  end

  defp approval_overview do
    records = ApprovalStore.list()

    %{
      id: "approvals",
      name: "Approvals",
      kind: "approval_store",
      availability: "AVAILABLE",
      status: "READY",
      health: "HEALTHY",
      real_data: true,
      synthetic: false,
      enabled: true,
      reachable: true,
      last_sync_at: nil,
      last_success_at: nil,
      latency_ms: nil,
      records: records,
      record_count: length(records),
      error_code: nil,
      error_message: nil,
      source: "approval event store",
      source_type: "LOCAL_EVENT_STORE",
      metadata: %{}
    }
  rescue
    error ->
      %{
        id: "approvals",
        name: "Approvals",
        kind: "approval_store",
        availability: "ERROR",
        status: "ERROR",
        health: "ERROR",
        real_data: false,
        synthetic: false,
        enabled: true,
        reachable: false,
        last_sync_at: nil,
        last_success_at: nil,
        latency_ms: nil,
        records: [],
        record_count: nil,
        source: "approval event store",
        source_type: "LOCAL_EVENT_STORE",
        error_code: "APPROVAL_STORE_READ_FAILED",
        error_message: Exception.message(error),
        metadata: %{}
      }
  end

  defp result_or_unavailable({:ok, records}, key),
    do: %{
      availability: "AVAILABLE",
      records: records,
      count: length(records),
      source: to_string(key)
    }

  defp result_or_unavailable({:error, reason}, key),
    do: %{availability: "UNAVAILABLE", reason: inspect(reason), source: to_string(key)}
end
