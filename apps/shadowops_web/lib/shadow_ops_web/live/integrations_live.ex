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
      subtitle="Real sources, workflow evidence and governed connector readiness"
      active="/integrations"
      availability={@catalog.status}
      updated_at={@updated_at}
    >
      <div class="mc-grid">
        <.metric_card label="Required core" value={"#{@catalog.required_core_ready_count}/#{@catalog.required_core_count}"} status={@catalog.status} source={@catalog.source} note="Required control-plane sources determine overall integration health" />
        <.metric_card label="Optional ready" value={"#{@catalog.optional_ready_count}/#{@catalog.optional_count}"} status={optional_status(@catalog)} note="Optional connectors and discoveries cannot mark required core healthy" />
        <.metric_card label="Connectors" value={@catalog.external_count} status={scope_status(@external)} note="External source adapters" />
        <.metric_card label="Imports" value={@catalog.import_count} status={scope_status(@imports)} note="Bounded local import sources; truth fields fail closed" />
        <.metric_card label="Local functions" value={@catalog.local_discovered_count} status={@catalog.local_discovery.status} note={"#{@catalog.local_auto_discovered_count} auto-discovered beyond the fixed inventory"} />
        <.metric_card label="Workflow IDs" value={@catalog.local_workflow_registered_count} status={@catalog.local_workflow_registry.status} note={"Stable localwf_* IDs · #{@catalog.local_workflow_rejected_count} filtered/rejected · reference only"} />
        <.metric_card label="Knowledge docs" value={@catalog.knowledge_document_count} status={knowledge_status(@catalog)} note={"#{@catalog.knowledge_available_source_count}/#{@catalog.knowledge_source_count} measured local sources available; RAG readiness remains separate"} />
      </div>

      <p class="mc-callout">
        <strong>Evidence-first integration:</strong> discovered local workflows receive stable IDs and become visible immediately, but no discovery result gains execution rights until runtime and governance mapping are independently proven.
      </p>

      <.panel title="Source catalog" description="A source is not promoted to healthy unless runtime evidence explicitly says it is real and reachable.">
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

      <.panel title="Registered local workflow IDs" description="Stable IDs from the latest local workflow correlation evidence. These rows are inventory records, not executable workflow grants.">
        <p class="mc-callout">
          {@catalog.local_workflow_registered_count} registered ·
          {@catalog.local_workflow_rejected_count} filtered/rejected ·
          maximum {@catalog.local_workflow_registry.counts.max_records} records ·
          mode <strong>REFERENCE_ONLY</strong>
        </p>
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Workflow / ID</th><th>Source</th><th>Kind</th><th>Domain</th><th>Status</th><th>Source ref</th><th>Governance</th></tr></thead>
            <tbody>
              <tr :for={record <- @catalog.local_workflow_registry.records}>
                <td><strong>{record.name}</strong><br /><span class="mc-mono mc-muted">{record.id}</span></td>
                <td>{record.source}</td>
                <td class="mc-mono">{record.kind}</td>
                <td>{record.domain}</td>
                <td><.status_badge status={record.status} /></td>
                <td class="mc-mono">{record.source_ref}</td>
                <td>{if(record.governance_mapped, do: "Mapped", else: "Reference only")}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@catalog.local_workflow_registry.records == []} class="mc-empty">
          No local workflow correlation report is currently available to this runtime.
        </p>
      </.panel>

      <.panel title="Knowledge sources" description="Measured local knowledge paths. AVAILABLE means the local source exists and its files were counted; indexed/RAG readiness is reported separately by the Knowledge module.">
        <p class="mc-callout">
          {@catalog.knowledge_available_source_count}/{@catalog.knowledge_source_count} sources available ·
          {@catalog.knowledge_document_count} measured documents ·
          indexed documents: {@catalog.knowledge_indexed_document_count || "not ready"}
        </p>
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Source</th><th>Availability</th><th>Measured documents</th><th>Last update</th><th>Source type</th></tr></thead>
            <tbody>
              <tr :for={record <- @catalog.knowledge_sources}>
                <td><strong>{record.name}</strong><br /><span class="mc-mono mc-muted">{record.id}</span></td>
                <td><.status_badge status={record.availability} /></td>
                <td>{record.document_count}</td>
                <td class="mc-mono">{record.last_update || "—"}</td>
                <td class="mc-mono">{record.source_type}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel title="Local function inventory" description="Bounded folder scan of known local automation entrypoints. DISCOVERED proves a real local file exists; execution remains disabled until runtime and governance mapping are proven.">
        <p class="mc-callout">
          {@catalog.local_discovery.counts.known_discovered}/{@catalog.local_discovery.counts.known_total} fixed candidates discovered ·
          {@catalog.local_discovery.counts.auto_discovered} additional entrypoints auto-discovered ·
          {@catalog.local_discovery.counts.discovered} total discovered
        </p>
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Name</th><th>Kind</th><th>Domain</th><th>Status</th><th>Discovery</th><th>Source ref</th><th>Governance</th></tr></thead>
            <tbody>
              <tr :for={record <- @catalog.local_discovery.records}>
                <td><strong>{record.name}</strong><br /><span class="mc-mono mc-muted">{record.id}</span></td>
                <td class="mc-mono">{record.kind}</td>
                <td>{record.domain}</td>
                <td><.status_badge status={record.status} /></td>
                <td>{record.discovery_mode}</td>
                <td class="mc-mono">{record.source_ref}</td>
                <td>{if(record.governance_mapped, do: "Mapped", else: "Reference only")}</td>
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

  defp scope_status(records),
    do: if(Enum.any?(records, &IntegrationCatalog.positive?/1), do: "READY", else: "DEGRADED")

  defp optional_status(%{optional_count: 0}), do: "NOT_CONFIGURED"

  defp optional_status(%{optional_ready_count: ready, optional_count: total}) when ready == total,
    do: "READY"

  defp optional_status(_), do: "DEGRADED"

  defp knowledge_status(%{knowledge_source_count: 0}), do: "NOT_CONFIGURED"

  defp knowledge_status(%{
         knowledge_available_source_count: ready,
         knowledge_source_count: total
       })
       when ready == total,
       do: "AVAILABLE"

  defp knowledge_status(%{knowledge_available_source_count: ready}) when ready > 0, do: "DEGRADED"
  defp knowledge_status(_), do: "UNAVAILABLE"

  defp yes_no(true), do: "Yes"
  defp yes_no(_), do: "No"
end
