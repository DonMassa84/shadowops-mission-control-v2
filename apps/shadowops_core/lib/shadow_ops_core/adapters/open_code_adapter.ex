defmodule ShadowOpsCore.Adapters.OpenCodeAdapter do
  @moduledoc "Evidence-only adapter for the existing OpenCode external runtime set."
  @behaviour ShadowOpsCore.Adapters.RuntimeAdapter

  alias ShadowOpsCore.{Evidence, WorkflowSource}

  @impl true
  def discover(_opts \\ []) do
    with {:ok, registry} <- WorkflowSource.load(),
         set when is_map(set) <- registry["external_runtime_sets"]["opencode_standard"] do
      {:ok,
       [
         %{
           id: "opencode_standard",
           source: "opencode",
           workflow_count: set["workflow_count"],
           workflow_ids: set["workflow_ids"]
         }
       ]}
    else
      _ -> {:error, :opencode_runtime_set_unavailable}
    end
  end

  @impl true
  def status(opts \\ []),
    do:
      case(discover(opts),
        do: (
          {:ok, rows} ->
            %{state: "DEGRADED", discovered: length(rows), reason: "workflow_ids_not_imported"}

          {:error, reason} ->
            %{state: "UNAVAILABLE", discovered: 0, reason: inspect(reason)}
        )
      )

  @impl true
  def validate(%{workflow_ids: ids}) when is_list(ids), do: :ok
  def validate(_), do: {:error, :workflow_ids_not_imported}
  @impl true
  def run(_, _, _), do: {:error, :opencode_execution_not_connected}
  @impl true
  def stop(_, _), do: {:error, :opencode_execution_not_connected}
  @impl true
  def health(row), do: %{status: if(validate(row) == :ok, do: "PASS", else: "FAIL")}
  @impl true
  def evidence(row),
    do:
      Evidence.build(
        "workflow:opencode_standard",
        "registry",
        [
          %{
            gate: "workflow_ids",
            result: if(validate(row) == :ok, do: "PASS", else: "FAIL"),
            evidence_ref: "registry:opencode_standard"
          }
        ],
        "canonical workflow registry"
      )
end
