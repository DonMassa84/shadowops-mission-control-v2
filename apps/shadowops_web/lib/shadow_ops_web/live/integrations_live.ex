defmodule ShadowOpsWeb.IntegrationsLive do
  use Phoenix.LiveView

  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsWeb.IntegrationCatalog

  @refresh_ms 15_000

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)
    {:ok, load(socket)}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load(socket)}
  end

  def render(assigns) do
    ~H"""
    <.app_shell
      title="Integrations"
      subtitle="Real sources, connectors and import evidence"
      active="/integrations"
      availability={@catalog.status}
      updated_at={@updated_at}
    >
      <div class="mc-grid">
        <.metric_card label="Ready" value={@catalog.positive_count} status={@catalog.status} source={@catalog.source} note="Evidence-backed positive integrations" />
        <.metric_card label="Core" value={@catalog.core_count} status="AVAILABLE" note="ShadowOps control-plane modules" />
        <.metric_card label="Connectors" value={@catalog.external_count} status={scope_status(@external)} note="External source adapters" />
        <.metric_card label="Imports" value={@catalog.import_count} status={scope_status(@imports)} note="Bounded local import sources" />
      </div>

      <.panel title="Source catalog" description="A source is not promoted to healthy unless runtime evidence says it is real and reachable.">
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Source</th><th>Scope</th><th>Status</th><th>Real</th><th>Reachable</th><th>Records</th><th>Source type</th><th>Evidence / error</th></tr></thead>
            <tbody>
              <tr :for={record <- @catalog.records}>
                <td><strong>{record.name}</strong><br /><span class="mc-mono mc-muted">{record.id}</span></td>
                <td>{record.scope}</td>
                <td><.status_badge status={record.status} /></td>
                <td>{yes_no(record.real_data)}</td>
                <td>{yes_no(record.reachable)}</td>
                <td>{record.record_count || "—"}</td>
                <td class="mc-mono">{record.source_type}</td>
                <td>{record.error_message || record.source}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>
    </.app_shell>
    """
  end

  defp load(socket) do
    catalog = IntegrationCatalog.snapshot()

    assign(socket,
      catalog: catalog,
      external: Enum.filter(catalog.records, &(&1.scope == "external")),
      imports: Enum.filter(catalog.records, &(&1.scope == "import")),
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
  end

  defp scope_status([]), do: "NOT_CONFIGURED"
  defp scope_status(records), do: if(Enum.any?(records, &IntegrationCatalog.positive?/1), do: "READY", else: "DEGRADED")
  defp yes_no(true), do: "Yes"
  defp yes_no(_), do: "No"
end
