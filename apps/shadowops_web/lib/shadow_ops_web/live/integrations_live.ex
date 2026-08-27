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
      subtitle="Real sources, curated workflow capabilities and governed connector readiness"
      active="/integrations"
      availability={@catalog.status}
      updated_at={@updated_at}
    >
      <div class="mc-grid">
        <.metric_card label="Required core" value={"#{@catalog.required_core_ready_count}/#{@catalog.required_core_count}"} status={@catalog.status} source={@catalog.source} note="Required control-plane sources determine overall integration health" />
        <.metric_card label="Connectors" value={@catalog.external_count} status={scope_status(@external)} note="External source adapters" />
        <.metric_card label="Workflow IDs" value={@catalog.local_workflow_registered_count} status={@catalog.local_workflow_registry.status} note={"Stable localwf_* IDs · #{@catalog.local_workflow_rejected_count} filtered/rejected"} />
        <.metric_card label="Unique workflows" value={@catalog.workflow_unique_count} status={curation_status(@catalog.workflow_unique_count)} note={"#{@catalog.workflow_potential_duplicate_count} potential duplicate records"} />
        <.metric_card label="Production ready" value={@catalog.workflow_production_ready_count} status={production_status(@catalog)} note={"#{@catalog.workflow_tested_count} tested · #{@catalog.workflow_connected_count} connected"} />
        <.metric_card label="Knowledge docs" value={@catalog.knowledge_document_count} status={knowledge_status(@catalog)} note={"#{@catalog.knowledge_available_source_count}/#{@catalog.knowledge_source_count} measured local sources; RAG readiness remains separate"} />
      </div>

      <p class="mc-callout">
        <strong>Capability library:</strong> discovery creates stable IDs and normalized metadata only. A workflow becomes production-ready only after real-source connectivity, execution testing and governance mapping are independently proven.
      </p>

      <section class="mc-curation-funnel" aria-label="Workflow production readiness funnel">
        <div class="mc-curation-stage">
          <span>01 · Found</span>
          <strong>{@catalog.workflow_found_count}</strong>
          <small>source-backed IDs</small>
        </div>
        <div class="mc-curation-stage">
          <span>02 · Unique</span>
          <strong>{@catalog.workflow_unique_count}</strong>
          <small>conservative dedupe</small>
        </div>
        <div class="mc-curation-stage">
          <span>03 · Normalized</span>
          <strong>{@catalog.workflow_normalized_count}</strong>
          <small>category + risk + systems</small>
        </div>
        <div class="mc-curation-stage">
          <span>04 · Connected</span>
          <strong>{@catalog.workflow_connected_count}</strong>
          <small>real runtime/source proof</small>
        </div>
        <div class="mc-curation-stage">
          <span>05 · Tested</span>
          <strong>{@catalog.workflow_tested_count}</strong>
          <small>execution evidence</small>
        </div>
        <div class="mc-curation-stage is-ready">
          <span>06 · Production ready</span>
          <strong>{@catalog.workflow_production_ready_count}</strong>
          <small>governed E2E proof</small>
        </div>
      </section>

      <.panel
        title="Curated workflow library"
        description="Normalized local workflow capabilities. Duplicate detection is conservative and never deletes or merges records automatically."
      >
        <div class="mc-statline">
          <.status_badge status="AVAILABLE" label={"#{@catalog.workflow_found_count} found"} />
          <.status_badge status="AVAILABLE" label={"#{@catalog.workflow_unique_count} unique"} />
          <.status_badge status={duplicate_status(@catalog)} label={"#{@catalog.workflow_duplicate_group_count} duplicate groups"} />
          <.status_badge status={production_status(@catalog)} label={"#{@catalog.workflow_production_ready_count} production ready"} />
        </div>

        <div class="mc-table-wrap mc-curation-table">
          <table class="mc-table">
            <thead>
              <tr>
                <th>Workflow / ID</th>
                <th>Category</th>
                <th>Risk</th>
                <th>Required systems</th>
                <th>Lifecycle</th>
                <th>Duplicate</th>
                <th>Source</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={record <- curated_rows(@catalog)}>
                <td>
                  <strong>{record.name}</strong><br />
                  <span class="mc-mono mc-muted">{record.id}</span>
                </td>
                <td><span class="mc-category-chip">{record.category}</span></td>
                <td><.status_badge status={risk_status(record.risk_level)} label={record.risk_level} /></td>
                <td>{systems(record.required_systems)}</td>
                <td><.status_badge status={record.lifecycle_status} /></td>
                <td>{if(record.duplicate_candidate, do: "Review group", else: "Unique key")}</td>
                <td>
                  {record.source}<br />
                  <span class="mc-mono mc-muted">{record.source_ref}</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@catalog.workflow_curation.records == []} class="mc-empty">
          No local workflow correlation evidence is available to curate.
        </p>
      </.panel>

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

  defp curated_rows(catalog), do: Enum.take(catalog.workflow_curation.records, 150)

  defp systems([]), do: "No external system inferred"
  defp systems(values), do: Enum.join(values, " · ")

  defp scope_status([]), do: "NOT_CONFIGURED"

  defp scope_status(records),
    do: if(Enum.any?(records, &IntegrationCatalog.positive?/1), do: "READY", else: "DEGRADED")

  defp curation_status(0), do: "NOT_CONFIGURED"
  defp curation_status(_), do: "AVAILABLE"

  defp production_status(%{workflow_production_ready_count: ready}) when ready > 0, do: "READY"
  defp production_status(%{workflow_tested_count: tested}) when tested > 0, do: "DEGRADED"
  defp production_status(_), do: "REVIEW"

  defp duplicate_status(%{workflow_potential_duplicate_count: 0}), do: "READY"
  defp duplicate_status(_), do: "REVIEW"

  defp risk_status("L0"), do: "READY"
  defp risk_status("L1"), do: "AVAILABLE"
  defp risk_status("L2"), do: "REVIEW"
  defp risk_status("L3"), do: "ERROR"
  defp risk_status(_), do: "REVIEW"

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
