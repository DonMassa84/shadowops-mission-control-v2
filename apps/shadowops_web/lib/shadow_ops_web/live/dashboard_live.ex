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
      subtitle="Production operations · physical compute · remote-only AI · governed actions · project federation"
      active="/"
      availability={@overview.readiness.state}
      updated_at={@updated_at}
    >
      <section class="mc-grid" aria-label="Primary command deck">
        <a class="mc-card-link" href="/nodes">
          <.metric_card
            label="Ryzen"
            value={node_status(@overview, "local-ryzen")}
            status={node_status(@overview, "local-ryzen")}
            source="runtime node evidence"
            note="Primary ShadowOps compute host"
          />
        </a>
        <a class="mc-card-link" href="/nodes">
          <.metric_card
            label="i7"
            value={node_status(@overview, "i7")}
            status={node_status(@overview, "i7")}
            source="bounded i7 probe"
            note="Optional secondary compute node"
          />
        </a>
        <a class="mc-card-link" href="/nodes">
          <.metric_card
            label="ChatGPT nodes"
            value={chatgpt_summary(@overview)}
            status={chatgpt_status(@overview)}
            source="local federated project catalog"
            note="Logical project nodes · status-only controls"
          />
        </a>
        <a class="mc-card-link" href="/workflows">
          <.metric_card
            label="Workflows"
            value={@workflow_inventory["total_count"]}
            status={workflow_inventory_status(@workflow_inventory)}
            source="workflow registry v2"
            note={"#{@workflow_inventory["canonical_count"]} canonical / #{@workflow_inventory["external_count"]} external"}
          />
        </a>
        <a class="mc-card-link" href="/agents">
          <.metric_card
            label="Agents"
            value={agent_summary(@overview)}
            status={agent_status(@overview)}
            source={@overview.agents.source}
            note="Automation agents only when evidenced · AI execution remains remote-only"
          />
        </a>
        <a class="mc-card-link" href="/ai">
          <.metric_card
            label="AI policy"
            value="REMOTE ONLY"
            status="PASS"
            source="docs/REMOTE_AI_POLICY.md"
            note="Explicit remote provider/model required · no local inference or fallback"
          />
        </a>
        <a class="mc-card-link" href="/security">
          <.metric_card
            label="Security"
            value={@overview.security.overall}
            status={@overview.security.overall}
            source={@overview.security.source}
            note="Write API remains governance-gated"
          />
        </a>
        <a class="mc-card-link" href="/audit">
          <.metric_card
            label="Audit"
            value={@overview.audit.state}
            status={@overview.audit.state}
            source={@overview.audit.source}
            note="Local hash-chain verification"
          />
        </a>
      </section>

      <.panel
        title="Command center"
        description="Highest-value operational surfaces. Read-only inspection is separated from governed write actions."
      >
        <div class="mc-command-grid">
          <a class="mc-command-card" href="/nodes">
            <span class="mc-command-kicker">Compute</span>
            <strong>Nodes</strong>
            <span>{physical_node_count(@overview)} physical · {length(chatgpt_nodes(@overview))} ChatGPT logical</span>
          </a>
          <a class="mc-command-card" href="/workflows">
            <span class="mc-command-kicker">Automation</span>
            <strong>Workflows</strong>
            <span>{@workflow_inventory["canonical_count"]} canonical workflows</span>
          </a>
          <a class="mc-command-card" href="/approvals">
            <span class="mc-command-kicker">Governance</span>
            <strong>Approvals</strong>
            <span>{pending(@overview.approvals.records)} pending decisions</span>
          </a>
          <a class="mc-command-card" href="/layers">
            <span class="mc-command-kicker">Architecture</span>
            <strong>Layer Health</strong>
            <span>Truthful assessed / not-assessed state</span>
          </a>
          <a class="mc-command-card" href="/projects/federated">
            <span class="mc-command-kicker">Federation</span>
            <strong>Projects</strong>
            <span>GitHub + local ChatGPT project catalog</span>
          </a>
          <a class="mc-command-card" href="/logs">
            <span class="mc-command-kicker">Diagnostics</span>
            <strong>Logs</strong>
            <span>Runtime and audit-backed diagnostics</span>
          </a>
        </div>
      </.panel>

      <section class="mc-grid" aria-label="Executive production status">
        <.metric_card
          label="System"
          value={@overview.readiness.state}
          status={@overview.readiness.state}
          source="runtime readiness"
          note="Required runtime dependencies"
        />
        <.metric_card
          label="Runtime"
          value={runtime_state(@overview)}
          status={runtime_state(@overview)}
          source="bounded runtime snapshot"
          note={"#{value_or_state(@overview.services, :services)} services"}
        />
        <.metric_card
          label="Connectors"
          value={connector_summary(@overview)}
          status={connector_status(@overview)}
          source="evidence-backed connector adapters"
          note="Optional missing sources remain explicit"
        />
        <.metric_card
          label="Pending approvals"
          value={pending(@overview.approvals.records)}
          status={approval_overall(@overview)}
          source={@overview.approvals.source}
          note="No approval bypass from Mission Control"
        />
        <.metric_card
          label="Backup"
          value={@overview.backups.status}
          status={@overview.backups.status}
          source={@overview.backups.source}
          note={@overview.backups.error_message || "Evidence-backed backup state"}
        />
        <.metric_card
          label="Career"
          value={@overview.career.status}
          status={@overview.career.status}
          source={@overview.career.source}
          note={"#{length(@career_workflows)} executable workflow candidates"}
        />
        <.metric_card
          label="Evidence"
          value={@overview.evidence.availability}
          status={@overview.evidence.availability}
          source={@overview.evidence.source}
          note="Production acceptance evidence"
        />
        <.metric_card
          label="Knowledge"
          value={@overview.knowledge.availability}
          status={@overview.knowledge.availability}
          source={@overview.knowledge.source}
          note="Local knowledge and retrieval evidence"
        />
      </section>

      <.panel
        title="Production readiness"
        description="Only runtime-backed gates are shown as PASS. Degraded and unavailable dependencies stay visible."
      >
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr><th>Gate</th><th>Status</th><th>Evidence</th><th>Action</th></tr>
            </thead>
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

      <.panel
        title="Project overview"
        description="Normalized private-local project state. Raw records remain outside the repository and outside this overview."
      >
        <section class="mc-grid" aria-label="Project overview">
          <a :for={domain <- @project_domains} href={"/projects/#{domain.id}"} class="mc-card-link">
            <.metric_card
              label={domain.name}
              value={domain.status}
              status={domain.status}
              source={domain.source_type}
              note={domain.summary}
            />
          </a>
        </section>
        <p>
          <a class="mc-button" href="/projects">Project domains</a>
          <a class="mc-button" href="/projects/federated">Federated projects</a>
          <a class="mc-button" href="/projects/chatgpt">ChatGPT project</a>
        </p>
      </.panel>

      <.panel
        title="Governed workflow operations"
        description="Canonical workflow detail links only. Registry-only external workflows cannot be executed from here."
      >
        <section class="mc-grid" aria-label="Workflow operations metrics">
          <.metric_card
            label="Workflow inventory"
            value={@workflow_inventory["total_count"]}
            status={workflow_inventory_status(@workflow_inventory)}
            source="registry v2 + external runtime sets"
            note={"#{@workflow_inventory["canonical_count"]} canonical / #{@workflow_inventory["external_count"]} external"}
          />
          <.metric_card
            label="Runs"
            value={length(@overview.runs.records)}
            status={@overview.runs.status}
            source={@overview.runs.source}
            note="Persisted lifecycle records"
          />
          <.metric_card
            label="Pending approvals"
            value={pending(@overview.approvals.records)}
            status={approval_overall(@overview)}
            source={@overview.approvals.source}
            note="No approval bypass from Mission Control"
          />
          <.metric_card
            label="Canonical executable"
            value={length(@canonical_workflows)}
            status={if(@canonical_workflows == [], do: "DEGRADED", else: "AVAILABLE")}
            source="canonical registry"
            note="External source-only rows excluded"
          />
        </section>

        <div class="mc-table-wrap" :if={recent_runs(@overview) != []}>
          <table class="mc-table">
            <thead>
              <tr><th>Recent run</th><th>Status</th><th>Workflow</th><th>Updated</th></tr>
            </thead>
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

      <.panel
        title="Career & application operations"
        description="Canonical career/application workflows only. Execution remains controlled by workflow detail and approval gates."
      >
        <div class="mc-table-wrap" :if={@career_workflows != []}>
          <table class="mc-table">
            <thead>
              <tr><th>Workflow</th><th>Status</th><th>Runtime</th><th>Risk</th><th>Last run</th><th>Action</th></tr>
            </thead>
            <tbody>
              <tr :for={workflow <- @career_workflows}>
                <td>
                  <strong>{workflow_name(workflow)}</strong><br />
                  <span class="mc-mono mc-muted">{workflow["id"]}</span>
                </td>
                <td><.status_badge status={workflow_status(workflow)} /></td>
                <td class="mc-mono">{available(workflow["target_runtime"] || workflow["runtime"])}</td>
                <td>{available(workflow["risk_level"])}</td>
                <td>{last_run(workflow["last_run"])}</td>
                <td><a class="mc-button" href={"/workflows/#{workflow["id"]}"}>Review / run</a></td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@career_workflows == []} class="mc-empty">
          No canonical executable career workflow is currently present in the registry. Nothing is invented.
        </p>
        <p>
          <a class="mc-button" href="/career">Career pipeline</a>
          <a class="mc-button" href="/workflows">All workflows</a>
          <a class="mc-button" href="/approvals">Approvals</a>
        </p>
      </.panel>

      <.panel
        title="Automatic imports"
        description="External applications appear automatically from bounded local import evidence. Secret values are never rendered or stored here."
      >
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr><th>Source</th><th>Status</th><th>Domains</th><th>Secrets</th><th>Records</th><th>Last sync</th></tr>
            </thead>
            <tbody>
              <tr :for={source <- @import_sources}>
                <td>
                  <strong>{source.name}</strong><br />
                  <span class="mc-mono mc-muted">{source.adapter || "adapter not evidenced"}</span>
                </td>
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

      <.panel
        title="Sources & integrations"
        description="Real source state is refreshed every 15 seconds. Optional integrations are never promoted to healthy without evidence."
      >
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Area</th><th>Availability</th><th>Source / reason</th></tr></thead>
            <tbody>
              <tr :for={{area, state, detail} <- source_rows(@overview)}>
                <td>{area}</td>
                <td><.status_badge status={state} /></td>
                <td class="mc-muted">{detail}</td>
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
          <a class="mc-button" href="/ai">AI policy</a>
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

  defp node_status(o, id) do
    case Enum.find(node_records(o), &(record_value(&1, :node_id, nil) == id)) do
      nil -> "UNAVAILABLE"
      node -> record_value(node, :status, "UNKNOWN")
    end
  end

  defp node_records(o), do: Map.get(o.nodes, :records, [])

  defp chatgpt_nodes(o) do
    Enum.filter(node_records(o), &(get_in(&1, [:metadata, :logical]) == true))
  end

  defp physical_node_count(o),
    do: Enum.count(node_records(o), &(get_in(&1, [:metadata, :logical]) != true))

  defp chatgpt_summary(o) do
    nodes = chatgpt_nodes(o)
    ready = Enum.count(nodes, &(record_value(&1, :status, "") == "READY"))
    "#{ready}/#{length(nodes)} ready"
  end

  defp chatgpt_status(o) do
    nodes = chatgpt_nodes(o)
    ready = Enum.count(nodes, &(record_value(&1, :status, "") == "READY"))

    cond do
      nodes == [] -> "NOT_CONFIGURED"
      ready == length(nodes) -> "READY"
      ready > 0 -> "DEGRADED"
      true -> "NOT_CONFIGURED"
    end
  end

  defp agent_records(o), do: Map.get(o.agents, :records, [])

  defp agent_summary(o) do
    records = agent_records(o)
    ready = Enum.count(records, &(record_value(&1, :status, "") == "READY"))
    "#{ready}/#{length(records)} ready"
  end

  defp agent_status(o) do
    records = agent_records(o)

    cond do
      records == [] -> "UNAVAILABLE"
      Enum.all?(records, &(record_value(&1, :status, "") == "READY")) -> "READY"
      Enum.any?(records, &(record_value(&1, :status, "") == "READY")) -> "DEGRADED"
      true -> Map.get(o.agents, :status, "UNAVAILABLE")
    end
  end

  defp workflow_inventory_status(%{"total_count" => total}) when is_integer(total) and total > 0,
    do: "READY"

  defp workflow_inventory_status(_), do: "UNAVAILABLE"

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
      {"AI execution policy", "PASS", "REMOTE_ONLY · docs/REMOTE_AI_POLICY.md"},
      {"Local AI inventory", o.ai.availability,
       "#{length(Map.get(o.ai, :models, []))} discovered model records · execution blocked"},
      {"Career", o.career.status, o.career.error_message || o.career.source},
      {"Backups", o.backups.status, o.backups.error_message || o.backups.source}
      | Enum.map(o.connectors.records, fn connector ->
          {connector.name, connector.status,
           connector.error_message || connector.source || "No source"}
        end)
    ]

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
