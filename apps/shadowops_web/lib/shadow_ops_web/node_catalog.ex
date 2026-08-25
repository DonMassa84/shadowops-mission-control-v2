defmodule ShadowOpsWeb.NodeCatalog do
  @moduledoc """
  Read-only node projection combining physical runtime nodes with logical ChatGPT project nodes.

  ChatGPT nodes are derived exclusively from the local federated project catalog. They never imply
  a remote ChatGPT runtime connection and never expose local export paths or raw project content.
  """

  alias ShadowOpsCore.{Audit, RuntimeSources}
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
    case Enum.find(snapshot().records, &node_id?(&1, id)) do
      nil -> {:error, :not_found}
      node -> {:ok, node}
    end
  end

  def action(id, "status") when is_binary(id) do
    if String.starts_with?(id, "chatgpt:"),
      do: get(id),
      else: RuntimeSources.node_action(id, "status")
  end

  def action("chatgpt:" <> _rest, _action), do: {:error, :action_not_allowed}
  def action(id, action), do: RuntimeSources.node_action(id, action)

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

  defp chatgpt_nodes(%{projects: projects, generated_at: generated_at}) when is_list(projects) do
    projects
    |> Enum.filter(&(&1.source_type == @chatgpt_source_type))
    |> Enum.map(&chatgpt_node(&1, generated_at))
    |> Enum.sort_by(& &1.node_id)
  end

  defp chatgpt_nodes(_), do: []

  defp chatgpt_node(project, generated_at) do
    ready =
      project.status == "READY" and project.real_data == true and project.synthetic == false and
        project.reachable == true

    status = if(ready, do: "READY", else: "NOT_CONFIGURED")

    %{
      id: project.id,
      node_id: project.id,
      name: project.name,
      kind: "logical_project_node",
      status: status,
      health: if(ready, do: "HEALTHY", else: "UNAVAILABLE"),
      availability: if(ready, do: "AVAILABLE", else: "UNAVAILABLE"),
      source: "federated ChatGPT project catalog",
      source_type: "CHATGPT_LIBRARY_PROJECT",
      real_data: ready,
      synthetic: false,
      enabled: true,
      reachable: ready,
      optional: true,
      load: nil,
      ram: nil,
      uptime_seconds: nil,
      last_sync_at: generated_at,
      last_success_at: if(ready, do: generated_at),
      latency_ms: nil,
      record_count: nil,
      updated_at: generated_at,
      error_code: if(ready, do: nil, else: "CHATGPT_PROJECT_NOT_CONFIGURED"),
      error_message:
        if(ready,
          do: nil,
          else: "No evidenced local ChatGPT project export is available for this node"
        ),
      metadata: %{
        logical: true,
        provider: "chatgpt",
        control_actions: ["status"],
        integration_mode: project.integration_mode,
        content_ingested: project.content_ingested
      }
    }
  end

  defp node_id?(node, id), do: Map.get(node, :node_id) == id or Map.get(node, :id) == id

  defp newest_timestamp(nil, other), do: other
  defp newest_timestamp(value, nil), do: value
  defp newest_timestamp(left, right), do: max(left, right)
end
