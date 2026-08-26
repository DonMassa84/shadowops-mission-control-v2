defmodule ShadowOpsWeb.NodeCatalog do
  @moduledoc """
  Read-only node projection combining physical runtime nodes with logical project nodes.

  Provider-specific node semantics live in `ShadowOpsCore.Node`; this module only
  joins runtime evidence with the bounded local project catalog for the web layer.
  """

  alias ShadowOpsCore.{Audit, Node, RuntimeSources}
  alias ShadowOpsWeb.ProjectCatalog

  @chatgpt_source_type "chatgpt_library_project"

  def snapshot do
    runtime = RuntimeSources.nodes()
    catalog = ProjectCatalog.snapshot()
    chatgpt = chatgpt_nodes(catalog)
    records = runtime.records ++ chatgpt

    runtime
    |> Map.put(:records, records)
    |> Map.put(:record_count, length(records))
    |> Map.put(:source, "#{runtime.source} / local federated project catalog")
    |> Map.put(:updated_at, newest_timestamp(runtime[:updated_at], catalog.generated_at))
    |> Map.put(
      :metadata,
      Map.merge(runtime[:metadata] || %{}, %{
        physical_nodes: length(runtime.records),
        chatgpt_nodes: length(chatgpt),
        chatgpt_catalog_status: catalog.status,
        chatgpt_nodes_logical: true
      })
    )
  end

  def get(id) when is_binary(id) do
    case Enum.find(snapshot().records, &(Node.id(&1) == id)) do
      nil -> {:error, :not_found}
      node -> {:ok, node}
    end
  end

  def action(id, action) when is_binary(id) do
    case get(id) do
      {:ok, node} -> route_action(node, id, action)
      {:error, :not_found} -> RuntimeSources.node_action(id, action)
    end
  end

  def execute_action(id, action, actor) do
    case action(id, action) do
      {:ok, result} ->
        Audit.record(:node_action, actor, id, :success, %{action: action})
        {:ok, result}

      {:error, reason} ->
        Audit.record(:node_action, actor, id, :blocked, %{
          action: action,
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  defp route_action(node, id, action) do
    cond do
      Node.logical?(node) and Node.action_allowed?(node, action) -> {:ok, node}
      Node.logical?(node) -> {:error, :action_not_allowed}
      true -> RuntimeSources.node_action(id, action)
    end
  end

  defp chatgpt_nodes(%{projects: projects, generated_at: generated_at}) when is_list(projects) do
    projects
    |> Enum.filter(&(&1.source_type == @chatgpt_source_type))
    |> Enum.map(&Node.logical_project(&1, generated_at, :chatgpt))
    |> Enum.sort_by(& &1.node_id)
  end

  defp newest_timestamp(nil, other), do: other
  defp newest_timestamp(value, nil), do: value
  defp newest_timestamp(left, right), do: max(left, right)
end
