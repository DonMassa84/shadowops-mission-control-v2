defmodule ShadowOpsWeb.NodesLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsWeb.NodeCatalog

  def mount(_, _, socket), do: {:ok, assign(socket, data: NodeCatalog.snapshot())}

  def render(assigns) do
    ~H"""
    <.app_shell title="Nodes" subtitle="Measured infrastructure health" active="/nodes" availability={@data.status} updated_at={@data.updated_at}>
      <.source_meta source={@data.source} updated_at={@data.updated_at} availability={@data.status} />
      <.panel title="Real nodes" description="Unavailable nodes remain visible; actions are not invoked by this view.">
        <div class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Node</th><th>Status</th><th>Health</th><th>Source</th><th>Reachable</th><th>Load</th><th>RAM</th><th>Uptime</th><th>Error</th></tr></thead><tbody>
          <tr :for={node <- @data.records}><td>{node.name}</td><td><.status_badge status={node.status} /></td><td>{node.health}</td><td class="mc-mono">{node.source}</td><td>{node.reachable}</td><td>{inspect(node[:load])}</td><td>{inspect(node[:ram])}</td><td>{node[:uptime_seconds] || "Not measured"}</td><td>{node.error_message || "None"}</td></tr>
        </tbody></table></div>
      </.panel>
    </.app_shell>
    """
  end
end
