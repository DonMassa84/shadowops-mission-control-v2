defmodule ShadowOpsWeb.LogsLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  def mount(_, _, socket), do: {:ok, assign(socket, data: ShadowOpsApi.logs())}

  def render(assigns) do
    ~H"""
    <.app_shell title="Logs" subtitle="Bounded and redacted operational events" active="/logs" availability={@data.status} updated_at={@data.updated_at}>
      <.source_meta source={@data.source} updated_at={@data.updated_at} availability={@data.status} />
      <.panel title="Recent entries" description="At most 200 records from the audit chain and workflow run store; sensitive patterns are redacted.">
        <div :if={@data.records != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Time</th><th>Module</th><th>Severity</th><th>Workflow</th><th>Message</th><th>Source</th></tr></thead><tbody>
          <tr :for={row <- @data.records}><td>{row.time}</td><td>{row.module}</td><td><.status_badge status={row.severity} /></td><td>{row.workflow || "—"}</td><td>{row.message}</td><td>{row.source}</td></tr>
        </tbody></table></div><p :if={@data.records == []} class="mc-empty">The connected stores contain no records.</p>
      </.panel>
    </.app_shell>
    """
  end
end
