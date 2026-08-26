defmodule ShadowOpsWeb.IntegrationsLive do
  use Phoenix.LiveView

  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsCore.{RuntimeSources, ServiceClassificationProjection}
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
        <.metric_card label="Required core" value={"#{@catalog.required_core_ready_count}/#{@catalog.required_core_count}"} status={@catalog.status} source={@catalog.source} note="Required control-plane sources determine overall integration health" />
        <.metric_card label="Optional ready" value={"#{@catalog.optional_ready_count}/#{@catalog.optional_count}"} status={optional_status(@catalog)} note="Optional connectors, imports and local discovery cannot mark required core healthy" />
        <.metric_card label="Connectors" value={@catalog.external_count} status={scope_status(@external)} note="External source adapters" />
        <.metric_card label="Imports" value={@catalog.import_count} status={scope_status(@imports)} note="Bounded local import sources; truth fields fail closed" />
        <.metric_card label="Local functions" value={@catalog.local_discovered_count} status={@catalog.local_discovery.status} note={"#{@catalog.local_auto_discovered_count} auto-discovered beyond the fixed inventory"} />
        <.metric_card label="Knowledge docs" value={@catalog.knowledge_document_count} status={knowledge_status(@catalog)} note={"#{@catalog.knowledge_available_source_count}/#{@catalog.knowledge_source_count} measured local sources available; RAG readiness remains separate"} />
      </div>

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

      <.panel title="Local function inventory" description="Bounded folder scan of known local automation entrypoints. Runtime classification uses the same canonical ServiceRuntimeCorrelation as /api/services.">
        <p class="mc-callout">
          {@catalog.local_discovery.counts.known_discovered}/{@catalog.local_discovery.counts.known_total} fixed candidates discovered ·
          {@catalog.local_discovery.counts.auto_discovered} additional entrypoints auto-discovered ·
          {@catalog.local_discovery.counts.discovered} total discovered
        </p>
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Name</th><th>Kind</th><th>Domain</th><th>Stage</th><th>Runtime</th><th>Live</th><th>Connected</th><th>Data</th><th>Governance</th></tr></thead>
            <tbody>
              <tr :for={record <- @catalog.local_discovery.records}>
                <td><strong>{record.name}</strong><br /><span class="mc-mono mc-muted">{record.id}</span></td>
                <td class="mc-mono">{record.kind}</td>
                <td>{record.domain}</td>
                <td><.classification_badge stage={record[:classification_stage] || record.status} /></td>
                <td class="mc-mono">{record[:runtime_identity] || "—"}</td>
                <td>{yes_no(record[:live])}</td>
                <td>{yes_no(record[:connected])}</td>
                <td>{yes_no(record[:real_data])}</td>
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
    runtime_snapshot = RuntimeSources.services().services

    classified_local =
      Enum.map(catalog.local_discovery.records, fn record ->
        ServiceClassificationProjection.classify_service(record, runtime_snapshot)
      end)

    local_discovery = %{catalog.local_discovery | records: classified_local}

    assign(socket,
      catalog: %{catalog | local_discovery: local_discovery},
      external: Enum.filter(catalog.records, &(&1.scope == "external")),
      imports: Enum.filter(catalog.records, &(&1.scope == "import")),
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
  end

  defp classification_badge(%{stage: "READY"} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--green">READY</span>
    """
  end

  defp classification_badge(%{stage: "RUNTIME_VERIFIED"} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--blue">RUNTIME_VERIFIED</span>
    """
  end

  defp classification_badge(%{stage: "LIVE"} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--yellow">LIVE</span>
    """
  end

  defp classification_badge(%{stage: "CONNECTED"} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--yellow">CONNECTED</span>
    """
  end

  defp classification_badge(%{stage: "REAL_DATA"} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--yellow">REAL_DATA</span>
    """
  end

  defp classification_badge(%{stage: "DISCOVERED"} = assigns) do
    ~H"""
    <span class="mc-badge mc-badge--gray">DISCOVERED</span>
    """
  end

  defp classification_badge(assigns) do
    ~H"""
    <span class="mc-badge mc-badge--gray">{@stage || "UNKNOWN"}</span>
    """
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
