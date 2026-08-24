defmodule ShadowOpsWeb.ModuleLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(_params, _session, socket) do
    {title, path, data} = module(socket.assigns.live_action)
    {:ok, assign(socket, title: title, path: path, data: data)}
  end

  def render(assigns) do
    ~H"""
    <.app_shell title={@title} subtitle="Evidence-backed module state" active={@path} availability={@data.status} updated_at={Map.get(@data, :last_sync_at) || Map.get(@data, :generated_at)}>
      <.source_meta source={@data.source || "No source"} updated_at={Map.get(@data, :last_sync_at) || Map.get(@data, :generated_at)} availability={@data.status} />
      <.panel title="Canonical connector state" description="Unknown and unavailable values are not inferred.">
        <dl class="mc-dl"><dt>Status</dt><dd><.status_badge status={@data.status} /></dd><dt>Health</dt><dd>{@data.health}</dd><dt>Source type</dt><dd>{@data.source_type}</dd><dt>Real data</dt><dd>{@data.real_data}</dd><dt>Synthetic</dt><dd>{@data.synthetic}</dd><dt>Reachable</dt><dd>{@data.reachable}</dd><dt>Record count</dt><dd>{@data.record_count || "Not evidenced"}</dd><dt>Last success</dt><dd>{@data.last_success_at || "Not evidenced"}</dd><dt>Error code</dt><dd>{@data.error_code || "None"}</dd><dt>Error</dt><dd>{@data.error_message || "None"}</dd></dl>
      </.panel>
      <.panel :if={Map.get(@data, :records)} title="Connected records"><div class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Name</th><th>Status</th><th>Health</th><th>Source type</th><th>Error</th></tr></thead><tbody><tr :for={row <- @data.records}><td>{row.name}</td><td><.status_badge status={row.status} /></td><td>{row.health}</td><td>{row.source_type}</td><td>{row.error_message || "None"}</td></tr></tbody></table></div></.panel>
    </.app_shell>
    """
  end

  defp module(:social), do: {"Social", "/social", ShadowOpsApi.social()}
  defp module(:career), do: {"Career", "/career", ShadowOpsApi.career()}
  defp module(:backups), do: {"Backups", "/backups", ShadowOpsApi.backups()}
  defp module(:reporting), do: {"Reporting", "/reporting", ShadowOpsApi.reporting()}
end
