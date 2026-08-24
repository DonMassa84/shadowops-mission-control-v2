defmodule ShadowOpsWeb.DashboardLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  alias ShadowOpsWeb.{ProjectDomains, RuntimeOverview, SourceRegistry}
  alias WorkflowEngine.{Inventory, Registry}

  @refresh_ms 15_000
  @career_terms ~w(career application applicant bewerb job recruiting cv cover_letter cover-letter)

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
      title="Mission Control"
      subtitle="Production operations · real sources · governed execution"
      active="/"
      availability={@overview.readiness.state}
      updated_at={@updated_at}
    >
      <section class="mc-grid" aria-label="Executive production status">
        <.metric_card label="System" value={@overview.readiness.state} status={@overview.readiness.state} source="runtime readiness" note="Required runtime dependencies" />
        <.metric_card label="Runtime" value={runtime_state(@overview)} status={runtime_state(@overview)} source="bounded runtime snapshot" note={"#{value_or_state(@overview.services, :services)} services"} />
        <.metric_card label="Connectors" value={connector_summary(@overview)} status={connector_status(@overview)} source="evidence-backed connector adapters" note="Optional missing sources remain explicit" />
        <.metric_card label="Security" value={@overview.security.overall} status={@overview.security.overall} source={@overview.security.source} note="Write API remains approval-gated" />
        <.metric_card label="Audit" value={@overview.audit.state} status={@overview.audit.state} source={@overview.audit.source} note="Local hash-chain verification" />
        <.metric_card label="Backup" value={@overview.backups.status} status={@overview.backups.status} source={@overview.backups.source} note={@overview.backups.error_message || "Evidence-backed backup state"} />
        <.metric_card label="Career" value={@overview.career.status} status={@overview.career.status} source={@overview.career.source} note={"#{length(@career_workflows)} executable workflow candidates"} />
        <.metric_card label="Evidence" value={@overview.evidence.availability} status={@overview.evidence.availability} source={@overview.evidence.source} note="Production acceptance evidence" />
      </section>

      <.panel title="Project overview" description="Normalized private-local project state. Raw records remain outside the repository and outside this overview.">
        <section class="mc-grid" aria-label="Project overview">
          <a :for={domain <- @project_domains} href={"/projects/#{domain.id}"} class="mc-card-link">
            <.metric_card label={domain.name} value={domain.status} status={domain.status} source={domain.source_type} note={domain.summary} />
          </a>
        </section>
        <p><a class="mc-button" href="/projects">All project domains</a></p>
      </.panel>

      <.panel title="Automatic imports" description="External applications appear automatically from bounded local import evidence. Secret values are never rendered or stored here.">
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Source</th><th>Status</th><th>Domains</th><th>Secrets</th><th>Records</th><th>Last sync</th></tr></thead>
            <tbody>
              <tr :for={source <- @import_sources}>
                <td><strong>{source.name}</strong><br /><span class="mc-mono mc-muted">{source.adapter || "adapter not evidenced"}</span></td>
                <td><.status_badge status={source.status} /></td>
                <td>{Enum.join(source.domains, ", ")}</td>
                <td><.status_badge status={secret_status(source)} /></td>
                <td>{source.record_count || "Not evidenced"}</td>
                <td>{source.last_sync || "Not evidenced"}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel title="Production readiness" description="Only runtime-backed gates are shown as PASS. Degraded and unavailable dependencies stay visible.">
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Gate</th><th>Status</th><th>Evidence</th><th>Action</th></tr></thead>
            <tbody>
              <tr :for={{gate, state, evidence, href} <- production_rows(@overview)}>
                <td><strong>{gate}</strong></td>
                <td><.status_badge status={state} /></td>
                <td class="mc-muted">{evidence}</td>
                <td><a class="mc-button" href={href}>Open</a></td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel title="Career & application operations" description="Canonical career/application workflows only. Execution remains controlled by the workflow detail and approval path.">
        <div class="mc-table-wrap" :if={@career_workflows != []}>
          <table class="mc-table">
            <thead><tr><th>Workflow</th><th>Status</th><th>Runtime</th><th>Risk</th><th>Last run</th><th>Action</th></tr></thead>
            <tbody>
              <tr :for={workflow <- @career_workflows}>
                <td><strong>{workflow_name(workflow)}</strong><br /><span class="mc-mono mc-muted">{workflow["id"]}</span></td>
                <td><.status_badge status={workflow_status(workflow)} /></td>
                <td class="mc-mono">{available(workflow["target_runtime"] || workflow["runtime"])}</td>
                <td>{available(workflow["risk_level"])}</td>
                <td>{last_run(workflow["last_run"])}</td>
                <td><a class="mc-button" href={"/workflows/#{workflow["id"]}"}>Review / run</a></td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@career_workflows == []} class="mc-empty">No canonical executable career workflow is currently present in the registry. Nothing is invented.</p>
        <p><a class="mc-button" href="/career">Career pipeline</a> <a class="mc-button" href="/workflows">All workflows</a> <a class="mc-button" href="/approvals">Approvals</a></p>
      </.panel>

      <.panel title="Governed workflow operations" description="The dashboard exposes only canonical workflow detail links. Registry-only external workflows cannot be executed from here.">
        <section class="mc-grid" aria-label="Workflow operations metrics">
          <.metric_card label="Workflow inventory" value={@workflow_inventory["total_count"]} status="AVAILABLE" source="registry v2 + external runtime sets" note={"#{@workflow_inventory["canonical_count"]} canonical / #{@workflow_inventory["external_count"]} external"} />
          <.metric_card label="Runs" value={length(@overview.runs.records)} status={@overview.runs.status} source={@overview.runs.source} note="Persisted lifecycle records" />
          <.metric_card label="Pending approvals" value={pending(@overview.approvals.records)} status={approval_overall(@overview)} source={@overview.approvals.source} note="No approval bypass from Mission Control" />
          <.metric_card label="Canonical executable" value={length(@canonical_workflows)} status={if(@canonical_workflows == [], do: "DEGRADED", else: "AVAILABLE")} source="canonical registry" note="External source-only rows excluded" />
        </section>

        <div class="mc-table-wrap" :if={recent_runs(@overview) != []}>
          <table class="mc-table">
            <thead><tr><th>Recent run</th><th>Status</th><th>Workflow</th><th>Updated</th></tr></thead>
            <tbody>
              <tr :for={run <- recent_runs(@overview)}>
                <td class="mc-mono">{record_value(run, :id, "unknown")}</td>
                <td><.status_badge status={record_value(run, :status, "UNKNOWN")} /></td>
                <td>{record_value(run, :workflow_id, record_value(run, :workflow, "unknown"))}</td>
                <td>{run_timestamp(run)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel title="Sources & integrations" description="Real source state is refreshed every 15 seconds. Optional integrations are never promoted to healthy without evidence.">
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Area</th><th>Availability</th><th>Source / reason</th></tr></thead>
            <tbody>
              <tr :for={{area, state, detail} <- source_rows(@overview)}>
                <td>{area}</td><td><.status_badge status={state} /></td><td class="mc-muted">{detail}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel title="Operations" description="Direct navigation to live control-plane functions.">
        <p>
          <a class="mc-button" href="/infrastructure">Infrastructure</a>
          <a class="mc-button" href="/services">Services</a>
          <a class="mc-button" href="/nodes">Nodes</a>
          <a class="mc-button" href="/agents">Agents</a>
          <a class="mc-button" href="/ai">AI</a>
          <a class="mc-button" href="/security">Security</a>
          <a class="mc-button" href="/audit">Audit</a>
          <a class="mc-button" href="/evidence">Evidence</a>
          <a class="mc-button" href="/backups">Backups</a>
          <a class="mc-button" href="/logs">Logs</a>
        </p>
      </.panel>
    </.app_shell>
    """
  end

  defp load(socket) do
    overview = RuntimeOverview.snapshot()

    {inventory, canonical_workflows} =
      case Registry.load() do
        {:ok, registry} ->
          canonical =
            case ShadowOpsApi.list_workflows() do
              {:ok, workflows} ->
                workflows |> Enum.filter(&executable_canonical?/1) |> Enum.sort_by(& &1["id"])

              {:error, _reason} ->
                []
            end

          {Inventory.summary(registry), canonical}

        {:error, _reason} ->
          {empty_inventory(), []}
      end

    assign(socket,
      overview: overview,
      workflow_inventory: inventory,
      canonical_workflows: canonical_workflows,
      career_workflows: Enum.filter(canonical_workflows, &career_workflow?/1),
      project_domains: ProjectDomains.all(),
      import_sources: SourceRegistry.all(),
      updated_at: now()
    )
  end

  defp empty_inventory,
    do: %{"total_count" => "UNAVAILABLE", "canonical_count" => 0, "external_count" => 0}

  defp executable_canonical?(workflow) do
    workflow["source_kind"] != "external_runtime_set" and
      workflow_status(workflow) not in ["UNAVAILABLE", "DISABLED", "NOT_CONNECTED"]
  end

  defp career_workflow?(workflow) do
    haystack =
      [
        workflow["id"],
        workflow["name"],
        workflow["display_name"],
        workflow["domain"],
        workflow["type"]
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join(" ", &to_string/1)
      |> String.downcase()

    Enum.any?(@career_terms, &String.contains?(haystack, &1))
  end

  defp production_rows(o),
    do: [
      {"Runtime readiness", o.readiness.state, "Required dependency checks", "/infrastructure"},
      {"Security", o.security.overall, o.security.source, "/security"},
      {"Audit chain", o.audit.state, o.audit.source, "/audit"},
      {"Connectors", connector_status(o), connector_summary(o), "/social"},
      {"Backups", o.backups.status, o.backups.error_message || o.backups.source, "/backups"},
      {"Approvals", approval_overall(o), "#{pending(o.approvals.records)} pending", "/approvals"},
      {"Evidence", o.evidence.availability, o.evidence.source, "/evidence"}
    ]

  defp runtime_state(o) do
    if o.readiness.state in ["READY", "PASS", "AVAILABLE"] and
         o.services.availability == "AVAILABLE",
       do: "READY",
       else: "DEGRADED"
  end

  defp connector_status(o) do
    records = o.connectors.records

    cond do
      records == [] -> "UNAVAILABLE"
      Enum.any?(records, &(Map.get(&1, :status) in ["FAILED", "ERROR"])) -> "DEGRADED"
      Enum.any?(records, &(Map.get(&1, :health) == "DEGRADED")) -> "DEGRADED"
      true -> "READY"
    end
  end

  defp connector_summary(o) do
    records = o.connectors.records
    positive = Enum.count(records, &(Map.get(&1, :status) in ["READY", "ONLINE", "CONNECTED"]))
    "#{positive}/#{length(records)} ready"
  end

  defp secret_status(%{secret_binding: %{state: state}}), do: state
  defp secret_status(_), do: "UNKNOWN"

  defp approval_overall(o),
    do: if(pending(o.approvals.records) > 0, do: "DEGRADED", else: o.approvals.status)

  defp pending(records), do: Enum.count(records, &(record_value(&1, :status, "") == "PENDING"))
  defp value_or_state(%{availability: "AVAILABLE"} = data, key), do: length(Map.fetch!(data, key))
  defp value_or_state(data, _key), do: data.availability
  defp recent_runs(o), do: Enum.take(o.runs.records, 5)

  defp record_value(record, key, default) when is_map(record),
    do: Map.get(record, key, Map.get(record, to_string(key), default))

  defp record_value(_record, _key, default), do: default

  defp run_timestamp(run),
    do:
      record_value(run, :finished_at, nil) || record_value(run, :started_at, nil) ||
        record_value(run, :queued_at, "Not available")

  defp workflow_status(workflow),
    do: workflow["execution_status"] || workflow["status"] || "AVAILABLE"

  defp workflow_name(workflow), do: workflow["display_name"] || workflow["name"] || workflow["id"]
  defp available(nil), do: "Not available"
  defp available(""), do: "Not available"
  defp available(value), do: to_string(value)
  defp last_run(nil), do: "Not available"

  defp last_run(run) when is_map(run),
    do: "#{record_value(run, :status, "UNKNOWN")} / #{run_timestamp(run)}"

  defp last_run(_), do: "Not available"

  defp source_rows(o),
    do: [
      {"Knowledge", o.knowledge.availability, o.knowledge.source},
      {"Evidence", o.evidence.availability, o.evidence.source},
      {"Nodes", o.nodes.status, o.nodes.source},
      {"Agents", o.agents.status, o.agents.source},
      {"AI / Models", o.ai.availability, o.ai.source},
      {"Career", o.career.status, o.career.error_message || o.career.source},
      {"Backups", o.backups.status, o.backups.error_message || o.backups.source}
      | Enum.map(o.connectors.records, fn connector ->
          {connector.name, connector.status,
           connector.error_message || connector.source || "No source"}
        end)
    ]

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
