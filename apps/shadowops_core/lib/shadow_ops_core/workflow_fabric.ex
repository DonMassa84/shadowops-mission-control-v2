defmodule ShadowOpsCore.WorkflowFabric do
  @moduledoc "Canonical read-through fabric over registry, adapters, resources, events and drift evidence."

  alias ShadowOpsCore.Adapters.{
    AgentAdapter,
    GitHubActionsAdapter,
    OpenCodeAdapter,
    ScriptAdapter,
    SystemdAdapter,
    TccAdapter
  }

  alias ShadowOpsCore.{
    EventBus,
    Evidence,
    Resource,
    RuntimeSources,
    WorkflowManifest,
    WorkflowSource
  }

  @adapters %{
    systemd: SystemdAdapter,
    tcc: TccAdapter,
    opencode: OpenCodeAdapter,
    script: ScriptAdapter,
    agent: AgentAdapter,
    github_actions: GitHubActionsAdapter
  }

  def summary do
    workflows = workflows()
    adapter_states = Map.new(@adapters, fn {id, adapter} -> {id, safe_status(adapter)} end)

    %{
      status:
        if(workflows != [] and Enum.all?(workflows, &(&1.state == "READY")),
          do: "READY",
          else: "DEGRADED"
        ),
      source: "canonical workflow registry plus runtime adapters",
      synthetic: false,
      workflows_discovered: length(workflows),
      workflows_connected: Enum.count(workflows, &(&1.state == "READY")),
      adapters: adapter_states,
      events_buffered: length(events()),
      drift: drift()
    }
  end

  def workflows do
    with {:ok, registry} <- WorkflowSource.load() do
      registry["workflows"]
      |> Enum.map(fn {id, workflow} -> workflow_resource(id, workflow) end)
      |> Enum.sort_by(& &1.id)
    else
      _ -> []
    end
  end

  def resources do
    workflow_resources = workflows()
    node_resources = Enum.map(RuntimeSources.nodes().records, &runtime_resource(&1, "node"))

    service_resources =
      Enum.map(RuntimeSources.services().services, &runtime_resource(&1, "service"))

    agent_resources = Enum.map(RuntimeSources.agents().records, &runtime_resource(&1, "agent"))
    workflow_resources ++ node_resources ++ service_resources ++ agent_resources
  end

  def events(filters \\ %{}), do: EventBus.list(filters)

  def drift do
    services = RuntimeSources.services().services

    with {:ok, registry} <- WorkflowSource.load() do
      registry["workflows"]
      |> Enum.flat_map(fn {id, workflow} ->
        definition = workflow["definition"] || ""

        if String.ends_with?(definition, ".service") do
          unit = Path.basename(definition)
          actual = Enum.find(services, &(&1.name == unit))
          desired_state = desired_service_state(workflow)

          actual_state =
            if(actual && actual.active_state == "active", do: "RUNNING", else: "STOPPED")

          suggested_action = if(desired_state == "RUNNING", do: "restart", else: "stop")

          [
            %{resource_id: "workflow:" <> id, unit: unit}
            |> Map.merge(Evidence.drift(desired_state, actual_state, suggested_action, "L1"))
          ]
        else
          []
        end
      end)
    else
      _ -> []
    end
  end

  defp workflow_resource(id, workflow) do
    case WorkflowManifest.from_registry(id, workflow) do
      {:ok, manifest} ->
        {adapter, valid} = workflow_adapter(manifest)
        evidence = workflow_evidence(adapter, manifest, valid)
        state = if(valid and evidence.result == "PASS", do: "READY", else: "DEGRADED")

        resource!(%{
          id: "workflow:" <> id,
          kind: "workflow",
          name: manifest.name,
          source: manifest.source,
          state: state,
          health: if(state == "READY", do: "PASS", else: "FAIL"),
          risk: manifest.risk_level,
          synthetic: manifest.synthetic,
          privacy: "metadata_only",
          provenance: evidence.provenance,
          last_verified_at: evidence.verified_at,
          evidence_ref: evidence.id,
          metadata: %{manifest: manifest, evidence: evidence}
        })

      {:error, reason} ->
        evidence =
          workflow_evidence(nil, %{id: id}, false)

        resource!(%{
          id: "workflow:" <> id,
          kind: "workflow",
          name: id,
          source: "canonical_registry",
          state: "DEGRADED",
          health: "FAIL",
          risk: "L3",
          synthetic: false,
          privacy: "metadata_only",
          provenance: evidence.provenance,
          last_verified_at: evidence.verified_at,
          evidence_ref: evidence.id,
          metadata: %{error: inspect(reason), evidence: evidence}
        })
    end
  end

  defp workflow_adapter(%{metadata: %{registry_status: "DISABLED_BY_CONFIGURATION"}}),
    do: {nil, false}

  defp workflow_adapter(%{source: "github_actions"} = manifest),
    do: {GitHubActionsAdapter, GitHubActionsAdapter.validate(manifest) == :ok}

  defp workflow_adapter(%{source: source} = manifest) when source in ["local_script", "systemd"],
    do: {ScriptAdapter, ScriptAdapter.validate(manifest) == :ok}

  defp workflow_adapter(_), do: {nil, false}

  defp desired_service_state(%{"status" => "DISABLED_BY_CONFIGURATION"}), do: "STOPPED"
  defp desired_service_state(_), do: "RUNNING"

  defp workflow_evidence(nil, manifest, _valid) do
    {:ok, evidence} =
      Evidence.build(
        "workflow:" <> manifest.id,
        "adapter",
        [%{gate: "adapter", result: "FAIL", evidence_ref: "registry:" <> manifest.id}],
        "canonical workflow registry"
      )

    evidence
  end

  defp workflow_evidence(adapter, manifest, _valid) do
    case adapter.evidence(manifest) do
      {:ok, evidence} -> evidence
      _ -> workflow_evidence(nil, manifest, false)
    end
  end

  defp runtime_resource(row, kind) do
    id = value(row, :id) || value(row, :name) || "unknown"
    status = value(row, :status) || "UNKNOWN"
    ready = status == "READY"

    evidence =
      Evidence.build(
        kind <> ":" <> id,
        "runtime",
        [
          %{
            gate: "state",
            result: if(ready, do: "PASS", else: "FAIL"),
            evidence_ref: value(row, :source) || "runtime"
          },
          %{
            gate: "real_data",
            result: if(value(row, :synthetic) == false, do: "PASS", else: "FAIL"),
            evidence_ref: "runtime_contract"
          }
        ],
        "authorized local runtime probe"
      )
      |> elem(1)

    resource!(%{
      id: kind <> ":" <> id,
      kind: kind,
      name: value(row, :name) || id,
      source: value(row, :source) || "runtime",
      state: if(ready and evidence.result == "PASS", do: "READY", else: "DEGRADED"),
      health: if(ready and evidence.result == "PASS", do: "PASS", else: "FAIL"),
      risk: "L0",
      synthetic: value(row, :synthetic) == true,
      privacy: "metadata_only",
      provenance: evidence.provenance,
      last_verified_at: evidence.verified_at,
      evidence_ref: evidence.id,
      metadata: %{runtime: row, evidence: evidence}
    })
  end

  defp safe_status(adapter) do
    adapter.status()
  rescue
    error -> %{state: "UNAVAILABLE", reason: Exception.message(error)}
  catch
    :exit, _ -> %{state: "UNAVAILABLE", reason: "runtime_probe_failed"}
  end

  defp resource!(attrs) do
    case Resource.new(attrs) do
      {:ok, resource} -> resource
      {:error, reason} -> raise "canonical resource invalid: #{inspect(reason)}"
    end
  end

  defp value(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
