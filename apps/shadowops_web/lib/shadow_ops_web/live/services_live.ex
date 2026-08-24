defmodule ShadowOpsWeb.ServicesLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(_params, _session, socket) do
    data = ShadowOpsApi.services()
    filters = %{"scope" => "", "state" => "", "source" => ""}
    {:ok, assign(socket, data: data, services: data.services, filters: filters)}
  end

  def handle_event("filter", params, socket) do
    filters =
      Map.merge(socket.assigns.filters, Map.take(params, Map.keys(socket.assigns.filters)))

    rows =
      Enum.filter(socket.assigns.data.services, fn row ->
        matches_filter?(row.scope, filters["scope"]) and
          matches_filter?(row.active_state, filters["state"]) and
          matches_filter?(row.source, filters["source"])
      end)

    {:noreply, assign(socket, filters: filters, services: rows)}
  end

  def render(assigns) do
    ~H"""
    <.app_shell title="Services" subtitle="Local runtime inventory" active="/services" availability={@data.availability} updated_at={@data.updated_at}>
      <.source_meta source={@data.source} updated_at={@data.updated_at} availability={@data.availability} />
      <.panel title="Service records" description="Read-only runtime state. No direct shell controls are exposed.">
        <form id="service-filters" class="mc-filter" phx-change="filter"><label>Scope<select name="scope"><option value="">All</option><option :for={v <- values(@data.services, :scope)} value={v}>{v}</option></select></label><label>State<select name="state"><option value="">All</option><option :for={v <- values(@data.services, :active_state)} value={v}>{v}</option></select></label><label>Source<select name="source"><option value="">All</option><option :for={v <- values(@data.services, :source)} value={v}>{v}</option></select></label></form>
        <div :if={@services != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Name</th><th>Scope</th><th>Active</th><th>Sub-state</th><th>Enabled</th><th>PID</th><th>Uptime</th><th>Restarts</th><th>Last error</th><th>Source</th></tr></thead><tbody><tr :for={row <- @services}><td class="mc-mono">{row.name}</td><td>{row.scope}</td><td><.status_badge status={row.active_state} /></td><td>{row.sub_state}</td><td>{row.enabled || "Not measured"}</td><td>{row.pid || "—"}</td><td>{row.uptime_seconds || "—"}</td><td>{row.restart_count || "Not measured"}</td><td>{inspect(row.last_error)}</td><td>{row.source}</td></tr></tbody></table></div><p :if={@services == []} class="mc-empty">No service records match the current filters.</p>
      </.panel>
    </.app_shell>
    """
  end

  defp matches_filter?(_value, ""), do: true
  defp matches_filter?(value, filter), do: value == filter
  defp values(rows, key), do: rows |> Enum.map(&Map.fetch!(&1, key)) |> Enum.uniq() |> Enum.sort()
end
