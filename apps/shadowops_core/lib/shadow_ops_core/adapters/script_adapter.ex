defmodule ShadowOpsCore.Adapters.ScriptAdapter do
  @moduledoc "Adapter over script-backed definitions in the canonical workflow registry."
  @behaviour ShadowOpsCore.Adapters.RuntimeAdapter

  alias ShadowOpsCore.{Evidence, WorkflowExecutor, WorkflowManifest, WorkflowSource}

  @impl true
  def discover(_opts \\ []) do
    with {:ok, registry} <- WorkflowSource.load() do
      manifests =
        registry["workflows"]
        |> Enum.flat_map(fn {id, workflow} ->
          case WorkflowManifest.from_registry(id, workflow) do
            {:ok, %{source: source} = manifest} when source in ["local_script", "systemd"] ->
              [manifest]

            _ ->
              []
          end
        end)

      {:ok, manifests}
    end
  end

  @impl true
  def status(opts \\ []) do
    case discover(opts) do
      {:ok, manifests} ->
        available = Enum.count(manifests, &(validate(&1) == :ok))

        %{
          state:
            if(available == length(manifests) and available > 0, do: "READY", else: "DEGRADED"),
          discovered: length(manifests),
          available: available
        }

      {:error, reason} ->
        %{state: "UNAVAILABLE", discovered: 0, available: 0, reason: inspect(reason)}
    end
  end

  @impl true
  def validate(%WorkflowManifest{metadata: %{registry_status: "DISABLED_BY_CONFIGURATION"}}),
    do: {:error, :disabled_by_configuration}

  def validate(%WorkflowManifest{runtime: %{value: runtime}}) when is_binary(runtime) do
    if File.regular?(runtime), do: :ok, else: {:error, :runtime_unavailable}
  end

  def validate(_), do: {:error, :invalid_manifest}

  @impl true
  def run(%WorkflowManifest{} = manifest, input, %{policy_decision: decision})
      when decision in ["AUTO", "APPROVED"] do
    workflow = %{
      "runtime" => manifest.runtime.value,
      "status" => manifest.metadata.registry_status
    }

    workflow =
      if manifest.metadata.trusted_argv?,
        do: Map.put(workflow, "argv", manifest.metadata.trusted_argv),
        else: workflow

    WorkflowExecutor.execute(workflow, stringify(input))
  end

  def run(_, _, _), do: {:error, :policy_decision_required}

  @impl true
  def stop(_, _), do: {:error, :stop_not_supported}

  @impl true
  def health(manifest), do: %{status: if(validate(manifest) == :ok, do: "PASS", else: "FAIL")}

  @impl true
  def evidence(%WorkflowManifest{id: id} = manifest) do
    Evidence.build(
      "workflow:" <> id,
      "local_runtime",
      [
        %{
          gate: "registry_status",
          result: pass(manifest.metadata.registry_status in ["active", "VERIFIED_EXECUTABLE"]),
          evidence_ref: "registry:" <> id
        },
        %{
          gate: "runtime",
          result: pass(validate(manifest) == :ok),
          evidence_ref: manifest.runtime.value
        }
      ],
      "canonical workflow registry plus File.stat"
    )
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
  defp pass(true), do: "PASS"
  defp pass(false), do: "FAIL"
end
