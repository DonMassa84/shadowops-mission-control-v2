defmodule ShadowOpsCore.Adapters.TccAdapter do
  @moduledoc "Read-through adapter for the existing TCC workflow registry."
  @behaviour ShadowOpsCore.Adapters.RuntimeAdapter

  alias ShadowOpsCore.Evidence

  @default_path "/home/schattenmacher/.config/shadowmaker-tasks/workflows.json"

  @impl true
  def discover(opts \\ []) do
    path =
      Keyword.get(
        opts,
        :path,
        Application.get_env(:shadowops_core, :tcc_registry_path, @default_path)
      )

    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body),
         workflows when is_list(workflows) <- Map.get(decoded, "workflows") do
      {:ok, Enum.map(workflows, &canonical/1)}
    else
      {:error, reason} -> {:error, {:tcc_registry_unavailable, reason}}
      _ -> {:error, :invalid_tcc_registry}
    end
  end

  @impl true
  def status(opts \\ []) do
    case discover(opts) do
      {:ok, workflows} ->
        %{
          state: "DEGRADED",
          discovered: length(workflows),
          source: "tcc",
          discovery: "PASS",
          reason: "tcc_execution_not_connected"
        }

      {:error, reason} ->
        %{state: "UNAVAILABLE", discovered: 0, source: "tcc", reason: inspect(reason)}
    end
  end

  @impl true
  def validate(%{id: id, risk_level: risk}) when is_binary(id) and risk in ~w(L0 L1 L2 L3),
    do: :ok

  def validate(_), do: {:error, :invalid_tcc_workflow}

  @impl true
  def run(_, _, _), do: {:error, :tcc_execution_not_connected}
  @impl true
  def stop(_, _), do: {:error, :tcc_execution_not_connected}
  @impl true
  def health(workflow), do: %{status: if(validate(workflow) == :ok, do: "PASS", else: "FAIL")}

  @impl true
  def evidence(%{id: id} = workflow) do
    Evidence.build(
      "workflow:" <> id,
      "tcc_registry",
      [
        %{
          gate: "manifest",
          result: if(validate(workflow) == :ok, do: "PASS", else: "FAIL"),
          evidence_ref: "tcc:" <> id
        }
      ],
      "local TCC registry"
    )
  end

  defp canonical(workflow) do
    %{
      id: workflow["id"] || workflow["name"],
      name: workflow["name"] || workflow["id"],
      source: "tcc",
      runtime: "tcc",
      executor: workflow["executor"],
      target: List.first(workflow["allowed_targets"] || []),
      risk_level: workflow["risk_level"] || workflow["risk"] || workflow["approval_level"],
      approval_required:
        (workflow["risk_level"] || workflow["risk"] || workflow["approval_level"]) in ~w(L2 L3),
      inputs: workflow["inputs"] || [],
      outputs: workflow["outputs"] || [],
      connectors: workflow["connectors"] || %{},
      privacy: workflow["privacy"] || "local_only",
      evidence_required: true,
      synthetic: false
    }
  end
end
