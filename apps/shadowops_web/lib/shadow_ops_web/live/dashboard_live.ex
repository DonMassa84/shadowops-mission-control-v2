defmodule ShadowOpsWeb.DashboardLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents

  alias ShadowOpsApi
  alias ShadowOpsCore.{JobQueue, LearningFocus}
  alias ShadowOpsWeb.{IntegrationCatalog, MissionBrief, RuntimeOverview}
  alias WorkflowEngine.{Inventory, Registry}

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
      title="Mission Control"
      subtitle="Systemstatus · Workflows · Quellen · Fokus · Freigaben"
      active="/"
      availability={@overview.readiness.state}
      updated_at={@updated_at}
    >
      <section class="mc-grid" aria-label="Daily operations overview">
        <a class="mc-card-link" href="/infrastructure">
          <.metric_card label="System" value={@overview.readiness.state} status={@overview.readiness.state} source="runtime readiness" note="Required dependencies and audit readiness" />
        </a>
        <a class="mc-card-link" href="/workflows">
          <.metric_card label="Workflows" value={@workflow_inventory["canonical_count"]} status={workflow_inventory_status(@workflow_inventory)} source="canonical workflow registry" note="Executable governed automations" />
        </a>
        <a class="mc-card-link" href="/runs">
          <.metric_card label="Runs" value={length(@overview.runs.records)} status={@overview.runs.status} source={@overview.runs.source} note="Persisted workflow execution history" />
        </a>
        <a class="mc-card-link" href="/jobs">
          <.metric_card label="Job queue" value={job_summary(@jobs)} status={@jobs.status} source={@jobs.source} note={@jobs.error_message || "Persistent scheduled workload"} />
        </a>
        <a class="mc-card-link" href="/approvals">
          <.metric_card label="Pending approvals" value={pending(@overview.approvals.records)} status={approval_overall(@overview)} source={@overview.approvals.source} note="Actions waiting for operator decision" />
        </a>
        <a class="mc-card-link" href="/compute">
          <.metric_card label="Compute" value={node_summary(@overview)} status={node_status(@overview)} source={@overview.nodes.source} note="Physical compute and workload control" />
        </a>
        <a class="mc-card-link" href="/services">
          <.metric_card label="Services" value={service_summary(@overview)} status={service_status(@overview)} source={@overview.services.source} note="Runtime services discovered on the host" />
        </a>
        <a class="mc-card-link" href="/ai">
          <.metric_card label="AI policy" value={ai_policy(@overview)} status={ai_policy_status(@overview)} source={@overview.ai.source} note="No local Ollama LLM runtime" />
        </a>
        <a class="mc-card-link" href="/security">
          <.metric_card label="Security" value={@overview.security.overall} status={@overview.security.overall} source={@overview.security.source} note="Governance and write-boundary state" />
        </a>
      </section>

      <.panel title="Current mission" description="Configured mission source; never synthesized from an AI guess.">
        <div class="mc-command-grid">
          <article class="mc-command-card">
            <span class="mc-command-kicker">Mission</span>
            <strong>{@mission.mission.title}</strong>
            <span>{@mission.mission.current}</span>
          </article>
          <article class="mc-command-card">
            <span class="mc-command-kicker">Execute</span>
            <strong>{@mission.mission.detail}</strong>
            <span>Done when: {@mission.mission.done_when}</span>
          </article>
          <article class="mc-command-card">
            <span class="mc-command-kicker">Evidence</span>
            <strong>{@mission.mission.source}</strong>
            <span><.status_badge status={@mission.mission.status} /></span>
          </article>
        </div>
      </.panel>

      <.panel title="Top 3 next actions" description="Deterministic priority: governance and runtime blockers first, configured focus second. No invented tasks.">
        <div class="mc-command-grid" :if={@mission.actions != []}>
          <a
            :for={{action, index} <- Enum.with_index(@mission.actions, 1)}
            class="mc-command-card"
            href={action.href}
          >
            <span class="mc-command-kicker">#{index} · {action.status}</span>
            <strong>{action.title}</strong>
            <span>{action.detail}</span>
            <small>Source: {action.source}</small>
          </a>
        </div>
        <p :if={@mission.actions == []} class="mc-empty">No evidence-backed next action is currently available.</p>
      </.panel>

      <.panel title="Operational gates" description="Only evidence-backed gates are presented as healthy.">
        <div class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Gate</th><th>Status</th><th>Evidence</th><th>Open</th></tr></thead><tbody><tr :for={{gate, state, evidence, href} <- operational_gates(@overview)}><td><strong>{gate}</strong></td><td><.status_badge status={state} /></td><td class="mc-muted">{evidence}</td><td><a class="mc-button" href={href}>Open</a></td></tr></tbody></table></div>
      </.panel>

      <.panel title="Recent runs" description="Latest persisted workflow executions.">
        <div class="mc-table-wrap" :if={recent_runs(@overview) != []}><table class="mc-table"><thead><tr><th>Run</th><th>Status</th><th>Workflow</th><th>Updated</th></tr></thead><tbody><tr :for={run <- recent_runs(@overview)}><td class="mc-mono">{record_value(run, :id, "unknown")}</td><td><.status_badge status={record_value(run, :status, "UNKNOWN")} /></td><td>{record_value(run, :workflow_id, record_value(run, :workflow, "unknown"))}</td><td>{run_timestamp(run)}</td></tr></tbody></table></div>
        <p :if={recent_runs(@overview) == []} class="mc-empty">No persisted workflow runs yet.</p>
      </.panel>

      <.panel title="Available workflows" description="Canonical workflows only; external inventory-only records are hidden from the action list.">
        <div class="mc-table-wrap" :if={@canonical_workflows != []}><table class="mc-table"><thead><tr><th>Workflow</th><th>Status</th><th>Risk</th><th>Action</th></tr></thead><tbody><tr :for={workflow <- Enum.take(@canonical_workflows, 10)}><td><strong>{workflow_name(workflow)}</strong><br /><span class="mc-mono mc-muted">{workflow["id"]}</span></td><td><.status_badge status={workflow_status(workflow)} /></td><td>{workflow["risk_level"] || "Not specified"}</td><td><a class="mc-button" href={"/workflows/#{workflow["id"]}"}>Review / run</a></td></tr></tbody></table></div>
        <p :if={@canonical_workflows == []} class="mc-empty">No canonical executable workflow is currently available.</p>
      </.panel>
    </.app_shell>
    """
  end

  defp load(socket) do
    overview = RuntimeOverview.snapshot()
    jobs = JobQueue.snapshot()
    integrations = IntegrationCatalog.snapshot()

    focus =
      case LearningFocus.load() do
        {:ok, value} when is_map(value) -> value
        _ -> %{"availability" => "UNAVAILABLE"}
      end

    mission = MissionBrief.build(overview, jobs, integrations, focus)

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
      jobs: jobs,
      integrations: integrations,
      mission: mission,
      workflow_inventory: inventory,
      canonical_workflows: canonical_workflows,
      updated_at: now()
    )
  end

  defp empty_inventory,
    do: %{"total_count" => "UNAVAILABLE", "canonical_count" => 0, "external_count" => 0}

  defp executable_canonical?(workflow),
    do:
      workflow["source_kind"] != "external_runtime_set" and
        workflow_status(workflow) not in ["UNAVAILABLE", "DISABLED", "NOT_CONNECTED"]

  defp operational_gates(o),
    do: [
      {"Runtime readiness", o.readiness.state, "Required dependency checks", "/infrastructure"},
      {"Security", o.security.overall, o.security.source, "/security"},
      {"Audit chain", o.audit.state, o.audit.source, "/audit"},
      {"Backups", o.backups.status, o.backups.error_message || o.backups.source, "/backups"},
      {"Approvals", approval_overall(o), "#{pending(o.approvals.records)} pending", "/approvals"},
      {"AI execution", ai_policy_status(o), ai_policy(o), "/ai"}
    ]

  defp physical_nodes(o),
    do:
      o.nodes
      |> Map.get(:records, [])
      |> Enum.reject(&(get_in(&1, [:metadata, :logical]) == true))

  defp node_summary(o) do
    nodes = physical_nodes(o)
    ready = Enum.count(nodes, &(record_value(&1, :status, "") in ["READY", "ONLINE"]))
    "#{ready}/#{length(nodes)} ready"
  end

  defp node_status(o) do
    nodes = physical_nodes(o)
    ready = Enum.count(nodes, &(record_value(&1, :status, "") in ["READY", "ONLINE"]))

    cond do
      nodes == [] -> "UNAVAILABLE"
      ready == length(nodes) -> "READY"
      ready > 0 -> "DEGRADED"
      true -> "UNAVAILABLE"
    end
  end

  defp service_summary(o) do
    services = Map.get(o.services, :services, [])
    ready = Enum.count(services, &(record_value(&1, :status, "") == "READY"))
    "#{ready}/#{length(services)} ready"
  end

  defp service_status(o) do
    services = Map.get(o.services, :services, [])
    ready = Enum.count(services, &(record_value(&1, :status, "") == "READY"))

    cond do
      services == [] -> "UNAVAILABLE"
      ready == length(services) -> "READY"
      ready > 0 -> "DEGRADED"
      true -> "UNAVAILABLE"
    end
  end

  defp job_summary(%{record_count: count}) when is_integer(count), do: count
  defp job_summary(_), do: "Not configured"
  defp ai_policy(o), do: get_in(o, [:ai, :policy, :coding_execution]) || "UNAVAILABLE"
  defp ai_policy_status(o), do: if(ai_policy(o) == "REMOTE_ONLY", do: "READY", else: "DEGRADED")

  defp workflow_inventory_status(%{"canonical_count" => total})
       when is_integer(total) and total > 0, do: "READY"

  defp workflow_inventory_status(_), do: "UNAVAILABLE"

  defp approval_overall(o),
    do: if(pending(o.approvals.records) > 0, do: "DEGRADED", else: o.approvals.status)

  defp pending(records), do: Enum.count(records, &(record_value(&1, :status, "") == "PENDING"))
  defp recent_runs(o), do: o.runs.records |> Enum.take(5)

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
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
