defmodule ShadowOpsWeb.RuntimeOverview do
  @moduledoc "Bounded, fail-closed projection of real ShadowOps runtime sources."

  alias ShadowOpsCore.{Audit, LearningFocus}
  alias ShadowOpsWeb.{AIStatus, NodeCatalog, RuntimeSnapshotCache, SecurityStatus}
  alias WorkflowEngine.Registry

  @probe_timeout_ms 3_500

  def snapshot do
    if Process.whereis(RuntimeSnapshotCache) do
      RuntimeSnapshotCache.fetch(:runtime_overview, &build_snapshot/0)
    else
      build_snapshot()
    end
  end

  @doc false
  def build_snapshot do
    probes = [
      system: &ShadowOpsApi.system/0,
      workflows: &workflow_overview/0,
      runs: &ShadowOpsApi.runs/0,
      services: &ShadowOpsApi.services/0,
      nodes: &NodeCatalog.snapshot/0,
      agents: &ShadowOpsApi.agents/0,
      ai: &AIStatus.snapshot/0,
      approvals: &ShadowOpsApi.approvals/0,
      audit: &ShadowOpsApi.audit/0,
      security: &SecurityStatus.check/0,
      knowledge: &ShadowOpsApi.knowledge/0,
      evidence: &ShadowOpsApi.evidence/0,
      connectors: &ShadowOpsApi.connectors/0,
      career: &ShadowOpsApi.career/0,
      backups: &ShadowOpsApi.backups/0,
      legal: &ShadowOpsApi.legal/0
    ]

    stream =
      Task.async_stream(
        probes,
        fn {_key, fun} -> safe_probe(fun) end,
        ordered: true,
        timeout: @probe_timeout_ms,
        on_timeout: :kill_task,
        max_concurrency: length(probes)
      )

    overview =
      probes
      |> Enum.zip(stream)
      |> Enum.reduce(%{}, fn {{key, _fun}, result}, acc ->
        Map.put(acc, key, probe_result(key, result))
      end)

    Map.put(overview, :readiness, readiness_status())
  end

  defp safe_probe(fun) do
    try do
      {:ok, fun.()}
    rescue
      error -> {:error, {:exception, Exception.message(error)}}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp probe_result(_key, {:ok, {:ok, payload}}) when is_map(payload), do: payload
  defp probe_result(key, {:ok, {:error, reason}}), do: unavailable(key, "SOURCE_ERROR", reason)
  defp probe_result(key, {:exit, reason}), do: unavailable(key, "SOURCE_TIMEOUT", reason)
  defp probe_result(key, other), do: unavailable(key, "SOURCE_INVALID", other)

  defp workflow_overview do
    case ShadowOpsApi.list_workflows() do
      {:ok, records} ->
        %{
          id: "workflows",
          name: "Workflows",
          kind: "workflow_registry",
          availability: "AVAILABLE",
          status: "READY",
          health: "HEALTHY",
          source: "workflow registry v2",
          source_type: "LOCAL_REGISTRY",
          real_data: true,
          synthetic: false,
          enabled: true,
          reachable: true,
          records: records,
          count: length(records),
          record_count: length(records),
          error_code: nil,
          error_message: nil,
          metadata: %{}
        }

      {:error, reason} ->
        unavailable(:workflows, "REGISTRY_READ_FAILED", reason)
    end
  end

  defp readiness_status do
    registry = match?({:ok, _}, Registry.summary())
    audit = match?({:ok, %{valid: true}}, Audit.verify())
    {:ok, learning_focus} = LearningFocus.load()
    learning = learning_focus["availability"]

    ready = registry and audit and learning == "AVAILABLE"

    %{
      availability: "AVAILABLE",
      state: if(ready, do: "READY", else: "FAIL"),
      detail: %{registry: registry, audit_chain: audit, learning_focus: learning}
    }
  rescue
    _ ->
      %{
        availability: "UNAVAILABLE",
        state: "FAIL",
        detail: %{registry: false, audit_chain: false, learning_focus: "UNAVAILABLE"}
      }
  end

  defp unavailable(key, code, reason) do
    name = key |> to_string() |> String.replace("_", " ") |> String.capitalize()

    %{
      id: to_string(key),
      name: name,
      kind: to_string(key),
      availability: "UNAVAILABLE",
      status: "UNAVAILABLE",
      state: "UNAVAILABLE",
      overall: "UNAVAILABLE",
      health: "UNKNOWN",
      source: "bounded local runtime probe",
      source_type: "CONTROL_PLANE_PROBE",
      real_data: false,
      synthetic: false,
      enabled: true,
      reachable: false,
      records: [],
      services: [],
      count: nil,
      record_count: nil,
      error_code: code,
      error_message: inspect(reason),
      metadata: %{}
    }
  end
end
