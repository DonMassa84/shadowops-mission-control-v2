defmodule ShadowOpsCore.WorkflowSource do
  @moduledoc "Read-through access to the existing workflow_engine registry path."

  def load, do: load(nil)

  def load(overlay_path) do
    with {:ok, base} <- load_base() do
      merge_local_overlay(base, overlay_path)
    end
  end

  @doc false
  def load_base do
    try do
      registry =
        YamlElixir.read_from_file!(Application.fetch_env!(:workflow_engine, :registry_path))

      {:ok, normalize(registry)}
    rescue
      error -> {:error, {:registry_unavailable, Exception.message(error)}}
    end
  end

  defp normalize(%{"workflows" => workflows} = registry) when is_list(workflows) do
    runs = registry["workflow_runs"] || []

    registry
    |> Map.put("workflows", Map.new(workflows, &{&1["id"], Map.delete(&1, "id")}))
    |> Map.put("workflow_runs", Map.new(runs, &{&1["id"], Map.delete(&1, "id")}))
  end

  defp normalize(registry), do: registry

  defp merge_local_overlay(base, overlay_path) do
    path = overlay_path || System.get_env("SHADOWOPS_LOCAL_WORKFLOW_OVERLAY")

    case path do
      nil -> {:ok, base}
      "" -> {:ok, base}
      path -> load_local_overlay(base, path)
    end
  end

  defp load_local_overlay(base, path) do
    with {:ok, body} <- File.read(path),
         {:ok, overlay} <- Jason.decode(body),
         workflows when is_map(workflows) <-
           Map.get(overlay, "workflows") do
      base_workflows =
        Map.get(base, "workflows", %{})

      # Canonical Git registry always wins collisions.
      workflows =
        Map.merge(
          workflows,
          base_workflows
        )

      {:ok,
       base
       |> Map.put(
         "workflows",
         workflows
       )
       |> Map.put(
         "local_overlay_status",
         %{
           "status" => "LOADED",
           "path" => path,
           "workflow_count" =>
             map_size(
               Map.get(
                 overlay,
                 "workflows",
                 %{}
               )
             )
         }
       )}
    else
      {:error, reason} ->
        {:ok,
         Map.put(
           base,
           "local_overlay_status",
           %{
             "status" => "UNAVAILABLE",
             "reason" => inspect(reason),
             "path" => path
           }
         )}

      _ ->
        {:ok,
         Map.put(
           base,
           "local_overlay_status",
           %{
             "status" => "INVALID",
             "path" => path
           }
         )}
    end
  end
end
