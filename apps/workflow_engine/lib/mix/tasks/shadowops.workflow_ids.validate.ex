defmodule Mix.Tasks.Shadowops.WorkflowIds.Validate do
  @moduledoc false

  use Mix.Task

  @shortdoc "Validates canonical ShadowOps workflow IDs"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case WorkflowEngine.WorkflowIds.all() do
      {:ok, workflows} ->
        {:ok, data} = WorkflowEngine.WorkflowIds.load()
        external_sets = map_size(data["external_runtime_sets"])

        Mix.shell().info(
          "workflow IDs valid: #{length(workflows)} workflows / #{external_sets} external runtime sets"
        )

      {:error, reason} ->
        Mix.raise("workflow ID validation failed: #{inspect(reason)}")
    end
  end
end
