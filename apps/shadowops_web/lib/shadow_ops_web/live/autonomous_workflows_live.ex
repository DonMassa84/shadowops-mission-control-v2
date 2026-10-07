defmodule ShadowOpsWeb.AutonomousWorkflowsLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  alias ShadowOpsCore.{RuntimeSources, WorkflowJobs}
  alias WorkflowEngine.{Inventory, Registry}

  @refresh_ms 10_000

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)
    {:ok, load(socket)}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load(socket)}
  end

  def handle_event("trigger_workflow", %{"workflow_id" => id}, socket) do
    {:noreply, trigger_autonomous_workflow(socket, id)}
  end

  def handle_event("refresh_now", _params, socket) do
    {:noreply, load(socket)}
  end

  def render(assigns) do
    ~H"""
    <.app_shell
      title="Autonome Workflows"
      subtitle="Monitoring & Steuerung für L0/L1 Workflows"
      active="/autonomous-workflows"
      availability={@readiness}
      updated_at={@updated_at}
    >
      <!-- HEADER METRICS -->
      <section class="mc-grid" aria-label="Autonomous workflow metrics">
        <.metric_card
          label="L0 Workflows (auto)"
          value={@l0_count}
          status={@l0_status}
          source="Registry: L0 risk_level"
          note="Keine Approval nötig"
        />
        <.metric_card
          label="L1 Workflows (auto)"
          value={@l1_count}
          status={@l1_status}
          source="Registry: L1 risk_level"
          note="Keine Approval nötig"
        />
        <.metric_card
          label="Systemd Timer aktiv"
          value={@active_timers}
          status={@timers_status}
          source="systemctl --user list-timers"
          note="Laufen unabhängig von Oban"
        />
        <.metric_card
          label="Oban Jobs (queue:workflows)"
          value={@oban_queued}
          status={@oban_status}
          source="Oban"
          note={if(@persistence_enabled, do: "Persistent queue", else: "Disabled: start_persistence=false")}
        />
        <.metric_card
          label="Fehlgeschlagen (24h)"
          value={@failed_24h}
          status={@failed_status}
          source="RunStore"
          note="Fehlerrate: #{@failure_rate}%"
        />
        <.metric_card
          label="Laufend"
          value={@running_count}
          status={@running_status}
          source="RunStore: RUNNING"
          note="Aktuell aktive Ausführungen"
        />
      </section>

      <!-- QUICK ACTIONS -->
      <.panel title="⚡ Schnell-Aktionen" description="Manuelle Triggers für kritische autonome Workflows">
        <div class="mc-command-grid">
          <form :for={wf <- @critical_workflows} phx-submit="trigger_workflow" phx-value-workflow_id={wf["id"]} class="mc-command-card-form">
            <input type="hidden" name="workflow_id" value={wf["id"]} />
            <span class="mc-command-kicker">{wf["domain"]}</span>
            <strong>{display_name(wf)}</strong>
            <span>Risk: {available(wf["risk_level"])} · Runtime: {available(wf["target_runtime"] || wf["runtime"])}</span>
            <button class="mc-button" type="submit" style="margin-top: 8px;">🚀 Ausführen</button>
          </form>
        </div>
      </.panel>

      <!-- SYSTEM TIMERS -->
      <.panel title="⏱️ Systemd Timer (Autonome Schedules)" description="Diese Timer laufen unabhängig von Oban/Persistence und triggern Workflows/Scripts direkt">
        <div :if={@systemd_timers == []} class="mc-empty">
          <p>Keine Workflow-bezogenen Timer gefunden.</p>
        </div>
        <div :if={@systemd_timers != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr><th>Timer</th><th>Service</th><th>Nächstes Mal</th><th>Letztes Mal</th><th>Status</th><th>Workflows</th></tr>
            </thead>
            <tbody>
              <tr :for={t <- @systemd_timers}>
                <td class="mc-mono">{t.timer}</td>
                <td class="mc-mono">{t.service}</td>
                <td>{t.next || "-"}</td>
                <td>{t.last || "-"}</td>
                <td><.status_badge status={t.state} /></td>
                <td class="mc-mono">{t.workflow_ref || "-"}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <!-- OBAN QUEUE -->
      <.panel title="📦 Oban Job Queue (Persistent)" description="Aktiv nur wenn start_persistence=true in config/runtime.exs">
        <div :if={not @persistence_enabled} class="mc-callout">
          <strong>Persistence disabled</strong> — Setze <code>config :shadowops_core, start_persistence: true</code> in runtime.exs
          und stelle sicher dass PostgreSQL läuft. Dann starten Oban Worker für die Queue <code>workflows</code>.
        </div>
        <div :if={@persistence_enabled} class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr><th>Job ID</th><th>Workflow</th><th>Status</th><th>Attempts</th><th>Queue</th><th>Eingereiht</th><th>Started</th></tr>
            </thead>
            <tbody>
              <tr :for={j <- @oban_jobs}>
                <td class="mc-mono">{j.id}</td>
                <td>{j.args["workflow_id"] || "-"}</td>
                <td><.status_badge status={job_status(j.state)} /></td>
                <td>{j.attempt}/{j.max_attempts}</td>
                <td>{j.queue}</td>
                <td>{j.inserted_at || "-"}</td>
                <td>{j.started_at || "-"}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <!-- RECENT RUNS -->
      <.panel title="📜 Letzte Workflow-Ausführungen (24h)" description="Aus RunStore (governed execution path)">
        <div :if={@recent_runs == []} class="mc-empty">
          <p>Keine Ausführungen in den letzten 24h.</p>
        </div>
        <div :if={@recent_runs != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr><th>Run ID</th><th>Workflow</th><th>Status</th><th>Score</th><th>Actor</th><th>Dauer</th><th>Started</th><th>Evidence</th></tr>
            </thead>
            <tbody>
              <tr :for={r <- @recent_runs}>
                <td class="mc-mono"><a href={"/runs/#{r.id}"}>{r.id}</a></td>
                <td>{r.workflow_id || "-"}</td>
                <td><.status_badge status={r.status} /></td>
                <td>{score(r)}</td>
                <td>{r.requested_by || "-"}</td>
                <td>{duration(r)}</td>
                <td>{r.started_at || "-"}</td>
                <td>{available(r.evidence_ref)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <!-- ALERTS -->
      <.panel title="⚠️ Alerts & Gesundheitschecks" description="Automatisch erkannte Probleme">
        <div :if={@alerts == []} class="mc-empty">
          <p>✅ Alles im grünen Bereich.</p>
        </div>
        <section :if={@alerts != []} class="mc-grid" aria-label="Alerts">
          <.alert_card :for={alert <- @alerts} alert={alert} />
        </section>
      </.panel>

      <!-- FULL WORKFLOW TABLE -->
      <.panel title="📋 Alle autonomen Workflows (Registry)" description="Filter: L0/L1 Risk, VERIFIED_EXECUTABLE, active">
        <div class="mc-filter" style="margin-bottom: 16px;">
          <label>Risk<select name="risk" phx-change="filter" phx-value-risk={@risk_filter}><option value="">All</option><option value="L0">L0</option><option value="L1">L1</option><option value="L2">L2</option><option value="L3">L3</option></select></label>
          <label>Status<select name="status" phx-change="filter" phx-value-status={@status_filter}><option value="">All</option><option value="VERIFIED_EXECUTABLE">✅ VERIFIED</option><option value="active">✅ Active</option><option value="DISABLED">❌ Disabled</option></select></label>
          <button class="mc-button" phx-click="refresh_now">🔄 Refresh</button>
        </div>
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Workflow</th><th>Domain</th><th>Risk</th><th>Status</th><th>Runtime</th><th>Type</th><th>Letzter Run</th><th>Aktion</th></tr></thead>
            <tbody>
              <tr :for={w <- @filtered_workflows}>
                <td>
                  <strong>{display_name(w)}</strong><br/>
                  <span class="mc-mono mc-muted">{w["id"]}</span>
                </td>
                <td class="mc-badge">{available(w["domain"])}</td>
                <td><span class={"risk-badge risk-" <> String.downcase(w["risk_level"] || "unknown")}>{w["risk_level"] || "—"}</span></td>
                <td><.status_badge status={w["status"]} /></td>
                <td class="mc-mono">{available(w["target_runtime"] || w["runtime"])}</td>
                <td>{available(w["type"])}</td>
                <td>{last_run(w["last_run"])}</td>
                <td>
                  <form phx-submit="trigger_workflow" phx-value-workflow_id={w["id"]} style="display: inline;">
                    <button class="mc-button small" type="submit" :if={w["risk_level"] in ["L0", "L1"]}>🚀</button>
                    <span class="mc-muted" :if={w["risk_level"] not in ["L0", "L1"]}>Approval nötig</span>
                  </form>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>
    </.app_shell>
    """
  end

  defp load(socket) do
    # Get system overview
    system = RuntimeSources.system()
    
    # Get workflows
    {:ok, canonical} = ShadowOpsApi.list_workflows()
    {:ok, registry} = Registry.load()

    # Combine canonical + external
    all_workflows = canonical ++ Inventory.external_workflows(registry)

    # Filter autonomous (L0/L1) workflows
    autonomous = Enum.filter(all_workflows, fn w ->
      w["risk_level"] in ["L0", "L1"] and w["status"] in ["VERIFIED_EXECUTABLE", "active"]
    end)

    # Critical workflows (L0/L1 + executable)
    critical = Enum.take(autonomous, 6)

    # Systemd timers related to workflows
    timers = get_systemd_timers()

    # Oban jobs
    oban_jobs = get_oban_jobs()

    # Recent runs
    {:ok, runs} = ShadowOpsApi.list_runs()
    recent = Enum.take(Enum.filter(runs, &recent_24h/1), 20)

    # Alerts
    alerts = build_alerts(system, all_workflows, timers, oban_jobs)

    # Filter state
    filtered = apply_filters(all_workflows, nil, nil)

    assign(socket,
      l0_count: Enum.count(all_workflows, &(&1["risk_level"] == "L0")),
      l1_count: Enum.count(all_workflows, &(&1["risk_level"] == "L1")),
      l0_status: risk_status(all_workflows, "L0"),
      l1_status: risk_status(all_workflows, "L1"),
      active_timers: Enum.count(timers, &(is_running_timer/1)),
      timers_status: timers_status(timers),
      oban_queued: length(oban_jobs),
      oban_status: if(length(oban_jobs) > 10, do: "DEGRADED", else: "AVAILABLE"),
      failed_24h: Enum.count(recent, &(&1.status in ["FAILED", "ERROR"])),
      failed_status: if(Enum.count(recent, &(&1.status in ["FAILED", "ERROR"])) > 0, do: "DEGRADED", else: "AVAILABLE"),
      failure_rate: calculate_failure_rate(recent),
      running_count: Enum.count(recent, &(&1.status == "RUNNING")),
      running_status: if(Enum.count(recent, &(&1.status == "RUNNING")) > 5, do: "DEGRADED", else: "AVAILABLE"),
      critical_workflows: critical,
      systemd_timers: timers,
      oban_jobs: oban_jobs,
      recent_runs: recent,
      alerts: alerts,
      all_workflows: all_workflows,
      filtered_workflows: filtered,
      risk_filter: nil,
      status_filter: nil,
      persistence_enabled: WorkflowJobs.enabled?(),
      readiness: system.status || "READY",
      updated_at: now()
    )
  end

  # ===== DATA FUNCTIONS =====

  defp get_systemd_timers do
    case :os.cmd('systemctl --user list-timers --all --no-pager --output=json') do
      output ->
        try do
          json = Jason.decode!(output)
          Enum.filter(json, fn t ->
            String.contains?(t["unit"] || "", "workflow") or
            String.contains?(t["unit"] || "", "daily") or
            String.contains?(t["unit"] || "", "hourly") or
            String.contains?(t["unit"] || "", "shadow") or
            String.contains?(t["unit"] || "", "dokument") or
            String.contains?(t["unit"] || "", "learning") or
            String.contains?(t["unit"] || "", "monitor")
          end)
          |> Enum.map(fn t ->
            service = String.replace(t["activates"] || "", ".timer", ".service")
            %{
              timer: t["unit"] || "-",
              service: service,
              next: format_time(t["next_elapse_realtime"]),
              last: format_time(t["last_trigger"]),
              state: timer_state(t),
              workflow_ref: extract_workflow_ref(t["unit"])
            }
          end)
        rescue
          _ -> []
        end
    end
  end

  defp get_oban_jobs do
    if WorkflowJobs.enabled?() do
      []
    else
      []
    end
  end

  defp build_alerts(system, workflows, timers, oban_jobs) do
    alerts = []

    # Failed timers
    failed_timers = Enum.filter(timers, &(&1.state == "FAILED"))
    if failed_timers != [] do
      alerts = [%{
        type: "timer_failed",
        title: "Systemd Timer FAILED",
        message: "#{length(failed_timers)} Timer(s) im Fehlerzustand",
        severity: "high",
        action: "Timer prüfen",
        url: "/autonomous-workflows"
      } | alerts]
    end

    # Stuck Oban jobs
    if length(oban_jobs) > 20 do
      alerts = [%{
        type: "oban_backlog",
        title: "Oban Queue Backlog",
        message: "#{length(oban_jobs)} Jobs in Queue",
        severity: "medium",
        action: "Worker prüfen",
        url: "/autonomous-workflows"
      } | alerts]
    end

    # Disabled critical workflows
    disabled_critical = Enum.filter(workflows, fn w ->
      w["risk_level"] in ["L0", "L1"] and w["status"] == "DISABLED_BY_CONFIGURATION"
    end)
    if disabled_critical != [] do
      alerts = [%{
        type: "disabled_critical",
        title: "Kritische Workflows deaktiviert",
        message: "#{length(disabled_critical)} L0/L1 Workflows sind DISABLED_BY_CONFIGURATION",
        severity: "high",
        action: "Registry prüfen",
        url: "/workflows"
      } | alerts]
    end

    # Persistence disabled
    if not WorkflowJobs.enabled?() do
      alerts = [%{
        type: "persistence_disabled",
        title: "Oban Persistence deaktiviert",
        message: "Autonome Workflows laufen nur via systemd Timer, keine persistent Queue/Retries",
        severity: "medium",
        action: "Config anpassen",
        url: "/settings"
      } | alerts]
    end

    # System readiness
    readiness = system.status || system.health
    if readiness != "READY" and readiness != "ONLINE" do
      alerts = [%{
        type: "readiness",
        title: "System Readiness: #{readiness}",
        message: "Nicht alle Dependencies READY",
        severity: "high",
        action: "Infrastructure prüfen",
        url: "/infrastructure"
      } | alerts]
    end

    Enum.take(alerts, 6)
  end

  defp risk_status(workflows, level) do
    count = Enum.count(workflows, &(&1["risk_level"] == level))
    if count > 0, do: "AVAILABLE", else: "NOT_CONFIGURED"
  end

  defp is_running_timer(timer) do
    timer.state in ["waiting", "running"]
  end

  defp timers_status(timers) do
    failed = Enum.count(timers, &(&1.state == "FAILED"))
    if failed > 0, do: "DEGRADED", else: "AVAILABLE"
  end

  defp calculate_failure_rate(runs) do
    total = length(runs)
    if total == 0, do: 0, else: round(Enum.count(runs, &(&1.status in ["FAILED", "ERROR"])) / total * 100)
  end

  defp recent_24h(run) do
    queued = run.queued_at || run.started_at
    if queued do
      diff = DateTime.diff(DateTime.utc_now(), queued)
      diff < 86400
    else
      false
    end
  end

  defp job_status("executing"), do: "RUNNING"
  defp job_status("available"), do: "QUEUED"
  defp job_status("scheduled"), do: "SCHEDULED"
  defp job_status("retryable"), do: "RETRY"
  defp job_status("discarded"), do: "FAILED"
  defp job_status(_), do: "UNKNOWN"

  defp apply_filters(workflows, risk, status) do
    Enum.filter(workflows, fn w ->
      (risk == nil or w["risk_level"] == risk) and
      (status == nil or w["status"] == status)
    end)
  end

  defp timer_state(timer) do
    cond do
      timer["state"] == "elapsed" -> "FAILED"
      timer["state"] == "waiting" -> "WAITING"
      timer["state"] == "running" -> "RUNNING"
      true -> "UNKNOWN"
    end
  end

  defp format_time(ns) when is_integer(ns) do
    DateTime.from_unix!(div(ns, 1_000_000_000)) |> DateTime.to_iso8601()
  end

  defp format_time(nil), do: nil
  defp format_time(_), do: nil

  defp extract_workflow_ref(unit) do
    cond do
      String.contains?(unit, "workflow") -> unit
      String.contains?(unit, "daily-digest") -> "daily_digest"
      String.contains?(unit, "shadow-system") -> "shadow_system_overnight_audit"
      String.contains?(unit, "dokumentensystem") -> "document_ai"
      String.contains?(unit, "learning") -> "learning_kiosk"
      true -> nil
    end
  end

  # ===== HELPERS =====

  defp display_name(w),
    do:
      w["display_name"] || w["name"] || w["id"] |> String.replace("_", " ") |> String.capitalize()

  defp available(nil), do: "Not available"
  defp available(""), do: "Not available"
  defp available(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp available(value), do: to_string(value)

  defp last_run(nil), do: "—"
  defp last_run(run) when is_map(run) do
    time = run.finished_at || run.started_at || run.queued_at
    status = run.status || "UNKNOWN"
    time_str = if time, do: DateTime.to_iso8601(time), else: "—"
    "#{status} / #{time_str}"
  end
  defp last_run(_), do: "—"

  defp score(run) do
    case run.evaluation do
      %{score: score} -> "#{score}/100"
      _ -> "—"
    end
  end

  defp duration(run) do
    cond do
      run.duration_ms && is_integer(run.duration_ms) ->
        "#{run.duration_ms}ms"
      run.started_at && run.finished_at ->
        "#{DateTime.diff(run.finished_at, run.started_at, :second)}s"
      true -> "—"
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp trigger_autonomous_workflow(socket, workflow_id) do
    put_flash(socket, :info, "Manueller Trigger für #{workflow_id} - noch nicht implementiert")
  end
end
