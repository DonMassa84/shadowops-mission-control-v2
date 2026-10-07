defmodule ShadowOpsWeb.PersonalLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsWeb.{RuntimeOverview, SourceRegistry}
  alias WorkflowEngine.{Inventory, Registry}

  @refresh_ms 30_000
  @tasks_file "/home/shadowmaker/dashboard/tasks.json"

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)
    {:ok, load(socket)}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, load(socket)}
  end

  def handle_event("toggle_task", %{"task_id" => task_id}, socket) do
    {:noreply, update_task_status(socket, task_id)}
  end

  def handle_event("add_quick_task", %{"title" => title, "project" => project}, socket) do
    {:noreply, add_quick_task(socket, title, project)}
  end

  def handle_event("log_focus", %{"duration" => duration, "type" => type}, socket) do
    {:noreply, log_focus_session(socket, duration, type)}
  end

  def handle_event("update_energy", %{"level" => level}, socket) do
    {:noreply, assign(socket, energy_level: level)}
  end

  def handle_event("update_review", %{"field" => field, "value" => value}, socket) do
    {:noreply, assign(socket, review_data: Map.put(socket.assigns.review_data, field, value))}
  end

  def handle_event("sync_taskwarrior", _params, socket) do
    {:noreply, sync_taskwarrior(socket)}
  end

  def render(assigns) do
    ~H"""
    <.app_shell
      title="Personal Command Center"
      subtitle="Dein Fokus · Deine Energie · Deine Prioritäten"
      active="/personal"
      availability={@readiness}
      updated_at={@updated_at}
    >
      <!-- ENERGY & FOCUS BAR -->
      <.panel title="Status" description="Echtzeit-Check-in">
        <div class="mc-grid" style="grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));">
          <div class="mc-card">
            <div class="mc-label">Energie</div>
            <div class="mc-energy-bar">
              <input type="range" min="1" max="10" value={@energy_level} phx-change="update_energy" class="energy-slider" />
              <span class="energy-value"><%= @energy_level %>/10</span>
            </div>
            <div class="mc-mono mc-muted"><%= energy_label(@energy_level) %></div>
          </div>
          <div class="mc-card">
            <div class="mc-label">Fokus heute</div>
            <div class="mc-value"><%= format_minutes(@focus_today) %></div>
            <div class="mc-mono mc-muted">Ziel: 240min / <%= round(@focus_today / 240 * 100) %>%</div>
            <progress value={min(@focus_today, 240)} max="240" class="progress-bar"></progress>
          </div>
          <div class="mc-card">
            <div class="mc-label">Pomodoro-Zähler</div>
            <div class="mc-value"><%= @pomodoro_count %></div>
            <div class="mc-mono mc-muted">Session: <%= @current_session_type %></div>
            <button class="mc-button" phx-click="log_focus" phx-value-duration="25" phx-value-type="pomodoro">🍅 Start</button>
            <button class="mc-button" phx-click="log_focus" phx-value-duration="50" phx-value-type="deep_work">🔬 Deep Work</button>
            <button class="mc-button" phx-click="log_focus" phx-value-duration="15" phx-value-type="break">☕ Pause</button>
          </div>
          <div class="mc-card">
            <div class="mc-label">Letzte Pause</div>
            <div class="mc-value"><%= @last_break || "nie" %></div>
            <div class="mc-mono mc-muted"><%= break_status(@last_break) %></div>
          </div>
        </div>
      </.panel>

      <!-- TOP 3 PRIORITIES -->
      <.panel title="🎯 Top 3 Heute" description="Deine wichtigsten Aufgaben - drag to reorder">
        <div class="mc-grid" style="grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));">
          <article :for={{task, idx} <- Enum.with_index(@top_tasks)} class="priority-card" data-task-id={task.id}>
            <span class="priority-index"><%= idx + 1 %></span>
            <div class="priority-title">
              <input type="checkbox" checked={task.done} phx-click="toggle_task" phx-value-task_id={task.id} />
              <span class={if task.done, do: "line-through", else: ""}><%= task.title %></span>
            </div>
            <div class="priority-meta">
              <span class="mc-badge"><%= task.project %></span>
              <span class={"urgency-" <> task.urgency}>◆ <%= task.urgency %></span>
            </div>
          </article>
        </div>
        <form phx-submit="add_quick_task" class="quick-add-form">
          <input type="text" name="title" placeholder="Neue Aufgabe..." required />
          <select name="project">
            <option value="IHK">IHK Projekt</option>
            <option value="FINANCE">Finanzen</option>
            <option value="LEARNING">Learning</option>
            <option value="ADMIN">Admin</option>
            <option value="HEALTH">Gesundheit</option>
            <option value="OTHER">Sonstiges</option>
          </select>
          <button type="submit" class="mc-button">+ Hinzufügen</button>
        </form>
      </.panel>

      <!-- TASKWARRIOR SYNC -->
      <.panel title="⚔️ Taskwarrior (IHK Projekt)" description={"Sync mit sync-dashboard.sh · " <> (@tw_last_sync || "nie")}>
        <div class="mc-grid" style="grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 12px;">
          <div class="mc-card">
            <div class="mc-label">Taskwarrior Tasks</div>
            <div class="mc-value"><%= length(@tw_tasks) %></div>
            <button class="mc-button small" phx-click="sync_taskwarrior" style="margin-top: 8px;">🔄 Sync jetzt</button>
            <div class="mc-mono mc-muted" style="margin-top: 8px;">
              <%= if @tw_sync_status == "syncing", do: "⏳ Synchronisiere...", else: @tw_sync_status || "Bereit" %>
            </div>
          </div>
          <div class="mc-card">
            <div class="mc-label">Export Status</div>
            <div class="mc-value"><%= @tw_export_ok && "✅ OK" || "❌ Fehler" %></div>
            <div class="mc-mono mc-muted">Datei: <%= @tasks_file %></div>
          </div>
        </div>
        
        <div :if={@tw_tasks != []} class="mc-table-wrap" style="margin-top: 12px;">
          <table class="mc-table">
            <thead><tr><th>ID</th><th>Beschreibung</th><th>Projekt</th><th>Tags</th><th>Priorität</th><th>Status</th><th>Fällig</th></tr></thead>
            <tbody>
              <tr :for={task <- @tw_tasks}>
                <td class="mc-mono"><%= task.id || task.uuid || "-" %></td>
                <td><%= task.description %></td>
                <td class="mc-badge"><%= task.project || "-" %></td>
                <td><%= task.tags && Enum.join(task.tags, ", ") || "-" %></td>
                <td><span class={"urgency-" <> (task.priority || "low")}>◆ <%= task.priority || "low" %></span></td>
                <td><.status_badge status={task_status(task)} /></td>
                <td class="mc-mono"><%= task.due || task.due_date || "-" %></td>
              </tr>
            </tbody>
          </table>
        </div>
        
        <div :if={@tw_tasks == []} class="mc-empty" style="margin-top: 12px;">
          <p>Keine Taskwarrior Tasks gefunden. <button class="mc-button small" phx-click="sync_taskwarrior">🔄 Erst syncen</button></p>
        </div>
      </.panel>

      <!-- TIME-BLOCKING / SCHEDULE -->
      <.panel title="📅 Heute" description="Zeitblöcke & Termine">
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Zeit</th><th>Block</th><th>Projekt</th><th>Status</th><th>Aktion</th></tr></thead>
            <tbody>
              <tr :for={block <- @time_blocks}>
                <td class="mc-mono"><%= block.time %></td>
                <td><strong><%= block.title %></strong></td>
                <td class="mc-badge"><%= block.project %></td>
                <td><.status_badge status={block.status} /></td>
                <td>
                  <button class="mc-button small" phx-click="complete_block" phx-value-id={block.id}>✓</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <!-- PROJECT HEALTH -->
      <.panel title="📊 Projekt-Gesundheit" description="Fortschritt deiner aktiven Projekte">
        <div class="mc-grid" style="grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));">
          <.project_health_card
            :for={project <- @projects}
            project={project}
          />
        </div>
      </.panel>

      <!-- ALERTS & REMINDERS -->
      <.panel title="⚠️ Alarme & Erinnerungen" description="Dinge die JETZT Aufmerksamkeit brauchen">
        <div :if={@alerts == []} class="mc-empty">
          <p>✅ Alles ruhig. Keine dringenden Alarme.</p>
        </div>
        <section :if={@alerts != []} class="mc-grid" aria-label="Alerts">
          <.alert_card :for={alert <- @alerts} alert={alert} />
        </section>
      </.panel>

      <!-- QUICK LINKS -->
      <.panel title="⚡ Schnellzugriff" description="Wichtigste Links für deinen Workflow">
        <div class="mc-command-grid">
          <a class="mc-command-card" href="/workflows" target="_blank">
            <span class="mc-command-kicker">ShadowOps</span>
            <strong>Workflows</strong>
            <span>Automation ausführen</span>
          </a>
          <a class="mc-command-card" href="http://localhost:8765" target="_blank">
            <span class="mc-command-kicker">Learning</span>
            <strong>Learning Kiosk</strong>
            <span>Bital Interview Training</span>
          </a>
          <a class="mc-command-card" href="/finance" target="_blank">
            <span class="mc-command-kicker">Finanzen</span>
            <strong>Finanz-Dashboard</strong>
            <span>Forderungen & Fristen</span>
          </a>
          <a class="mc-command-card" href="/documents" target="_blank">
            <span class="mc-command-kicker">Dokumente</span>
            <strong>Document System</strong>
            <span>2.550 Docs durchsuchen</span>
          </a>
          <a class="mc-command-card" href="/rag" target="_blank">
            <span class="mc-command-kicker">Wissen</span>
            <strong>RAG Query</strong>
            <span>6.087 Chunks searchen</span>
          </a>
          <a class="mc-command-card" href="/career" target="_blank">
            <span class="mc-command-kicker">Karriere</span>
            <strong>Bewerbungen</strong>
            <span>Pipeline & Deadlines</span>
          </a>
          <a class="mc-command-card" href="/calendar" target="_blank">
            <span class="mc-command-kicker">Planung</span>
            <strong>Kalender</strong>
            <span>Termine & Zeitblöcke</span>
          </a>
          <a class="mc-command-card" href="http://localhost:11434" target="_blank">
            <span class="mc-command-kicker">KI</span>
            <strong>Ollama (GPU)</strong>
            <span>24 Modelle lokal</span>
          </a>
        </div>
      </.panel>

      <!-- DAILY REVIEW -->
      <.panel title="📝 Tages-Review" description="Am Ende des Tages ausfüllen">
        <div class="mc-grid" style="grid-template-columns: 1fr 1fr;">
          <div>
            <strong>Was lief gut?</strong>
            <textarea rows="3" placeholder="Erfolge notieren..." phx-change="update_review" phx-value-field="went_well" phx-value-value={@review_data.went_well}></textarea>
          </div>
          <div>
            <strong>Was war schwierig?</strong>
            <textarea rows="3" placeholder="Blocker, Energie-Tiefs..." phx-change="update_review" phx-value-field="was_hard" phx-value-value={@review_data.was_hard}></textarea>
          </div>
          <div>
            <strong>Morgen wichtig:</strong>
            <textarea rows="3" placeholder="Top 3 für morgen..." phx-change="update_review" phx-value-field="tomorrow_top3" phx-value-value={@review_data.tomorrow_top3}></textarea>
          </div>
          <div>
            <strong>Energie-Trend:</strong>
            <select phx-change="update_review" phx-value-field="energy_trend" phx-value-value={@review_data.energy_trend}>
              <option value="up">📈 Steigend</option>
              <option value="stable">➡️ Stabil</option>
              <option value="down">📉 Fallend</option>
            </select>
          </div>
        </div>
      </.panel>
    </.app_shell>
    """
  end

  defp load(socket) do
    overview = RuntimeOverview.snapshot()
    sources = SourceRegistry.all()

    assign(socket,
      energy_level: get_energy_level(),
      focus_today: get_focus_today(),
      pomodoro_count: get_pomodoro_count(),
      current_session_type: "ready",
      last_break: get_last_break(),
      top_tasks: get_top_tasks(),
      time_blocks: get_time_blocks(),
      projects: get_project_health(overview, sources),
      alerts: get_alerts(overview, sources),
      review_data: get_daily_review(),
      readiness: "READY",
      updated_at: now(),
      tw_tasks: load_tw_tasks(),
      tw_last_sync: get_tw_last_sync(),
      tw_sync_status: "Bereit",
      tw_export_ok: File.exists?(@tasks_file),
      tasks_file: @tasks_file
    )
  end

  # ===== TASKWARRIOR INTEGRATION =====

  defp sync_taskwarrior(socket) do
    socket
    |> assign(tw_sync_status: "syncing")
    |> assign(tw_tasks: [])
    |> then(fn socket ->
      # Run sync script in background
      case System.cmd("/home/shadowmaker/bin/sync-dashboard.sh", [], timeout: 30_000) do
        {output, 0} ->
          socket
          |> assign(tw_tasks: load_tw_tasks())
          |> assign(tw_last_sync: now())
          |> assign(tw_sync_status: "✅ Synced #{now()}")
          |> assign(tw_export_ok: true)
        {output, code} ->
          socket
          |> assign(tw_sync_status: "❌ Fehler (Exit: #{code})")
          |> assign(tw_export_ok: false)
      end
    end)
  end

  defp load_tw_tasks do
    if File.exists?(@tasks_file) do
      case File.read(@tasks_file) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, tasks} when is_list(tasks) -> tasks
            _ -> []
          end
        _ -> []
      end
    else
      []
    end
  end

  defp get_tw_last_sync do
    if File.exists?("/home/shadowmaker/dashboard/update.log") do
      case File.read("/home/shadowmaker/dashboard/update.log") do
        {:ok, content} ->
          content
          |> String.split("\n")
          |> Enum.find(&String.contains?(&1, "=== DASHBOARD SYNC ==="))
          |> (fn
            nil -> nil
            line -> String.replace(line, "==== DASHBOARD SYNC ====", "") |> String.trim()
          end).()
        _ -> nil
      end
    else
      nil
    end
  end

  defp task_status(%{"status" => "pending"}), do: "ACTIVE"
  defp task_status(%{"status" => "completed"}), do: "DONE"
  defp task_status(%{"status" => "deleted"}), do: "DELETED"
  defp task_status(%{"status" => "waiting"}), do: "PENDING"
  defp task_status(_), do: "UNKNOWN"

  # ===== DATA FUNCTIONS =====

  defp get_energy_level, do: 7
  defp get_focus_today, do: 145
  defp get_pomodoro_count, do: 3
  defp get_last_break, do: ~T[14:30:00]
  defp get_daily_review, do: %{
    went_well: "",
    was_hard: "",
    tomorrow_top3: "",
    energy_trend: "stable"
  }

  defp get_top_tasks do
    [
      %{id: "1", title: "IHK AP01 Dokument sichern", project: "IHK", done: false, urgency: "high"},
      %{id: "2", title: "BA Inkasso Zahlung prüfen", project: "FINANCE", done: false, urgency: "high"},
      %{id: "3", title: "Learning Kiosk Bital Session", project: "LEARNING", done: false, urgency: "medium"}
    ]
  end

  defp get_time_blocks do
    [
      %{id: "1", time: "08:00-09:30", title: "Deep Work: IHK AP01", project: "IHK", status: "DONE"},
      %{id: "2", time: "09:30-09:45", title: "Pause ☕", project: "HEALTH", status: "DONE"},
      %{id: "3", time: "10:00-11:30", title: "Finanzen: BA Inkasso", project: "FINANCE", status: "ACTIVE"},
      %{id: "4", time: "11:30-12:00", title: "E-Mail / Admin", project: "ADMIN", status: "PENDING"},
      %{id: "5", time: "12:00-13:00", title: "Mittagspause 🍽️", project: "HEALTH", status: "PENDING"},
      %{id: "6", time: "13:00-14:30", title: "Learning: Bital Interview", project: "LEARNING", status: "PENDING"},
      %{id: "7", time: "14:30-14:45", title: "Pause ☕", project: "HEALTH", status: "PENDING"},
      %{id: "8", time: "15:00-16:30", title: "Deep Work: Career Pipeline", project: "CAREER", status: "PENDING"}
    ]
  end

  defp get_project_health(_overview, _sources) do
    [
      %{id: "ihk", name: "IHK Projektarbeit", progress: 65, status: "ON_TRACK", next_milestone: "AP01 bis AP04 finalisieren", deadline: "2026-10-15", color: "#4af"},
      %{id: "finance", name: "Finanzen", progress: 40, status: "NEEDS_ATTENTION", next_milestone: "BA Inkasso klären", deadline: "2026-10-10", color: "#fa4"},
      %{id: "learning", name: "Learning / Bital", progress: 30, status: "ON_TRACK", next_milestone: "Interview-Training Woche 2", deadline: "2026-10-20", color: "#4fa"},
      %{id: "career", name: "Karriere / Bewerbungen", progress: 20, status: "STALLED", next_milestone: "Anschreiben finalisieren", deadline: "2026-11-01", color: "#aa4"},
      %{id: "health", name: "Gesundheit / Routine", progress: 80, status: "ON_TRACK", next_milestone: "Morgen/Abend Routine stabil", deadline: "ongoing", color: "#4fa"},
      %{id: "infra", name: "Infrastruktur", progress: 90, status: "ON_TRACK", next_milestone: "Ollama Tunnel stabil", deadline: "done", color: "#4af"}
    ]
  end

  defp get_alerts(overview, _sources) do
    alerts = []

    alerts = alerts ++ finance_alerts()
    alerts = alerts ++ health_alerts()
    alerts = alerts ++ infra_alerts(overview)
    alerts = alerts ++ learning_alerts()

    Enum.take(alerts, 5)
  end

  defp finance_alerts do
    [
      %{type: "deadline", title: "BA Inkasso AZ 6201097747704", message: "Zahlung fällig - prüfen ob versendet", severity: "high", action: "Finanzen prüfen", url: "/finance"},
      %{type: "deadline", title: "Nebenkostenabrechnung", message: "Prüfen & Widerspruchsfrist notieren", severity: "medium", action: "Dokument öffnen", url: "/documents"}
    ]
  end

  defp health_alerts do
    [
      %{type: "break", title: "Pause überfällig", message: "Letzte Pause vor 90+ min", severity: "medium", action: "Jetzt 5min Pause", url: "#"},
      %{type: "hydration", title: "Wasser trinken", message: "Letztes Glas vor 2h", severity: "low", action: "Trinken", url: "#"}
    ]
  end

  defp infra_alerts(overview) do
    alerts = []
    if overview.readiness.state != "READY" do
      alerts = [%{type: "infra", title: "System nicht READY", message: overview.readiness.state, severity: "high", action: "Infrastructure prüfen", url: "/infrastructure"} | alerts]
    end
    alerts
  end

  defp learning_alerts do
    [
      %{type: "habit", title: "Bital Training", message: "Tägliche Session noch nicht gemacht", severity: "medium", action: "Kiosk öffnen", url: "http://localhost:8765"}
    ]
  end

  # ===== HELPERS =====

  defp energy_label(1), do: "🔴 Erschöpft"
  defp energy_label(2), do: "🔴 Sehr niedrig"
  defp energy_label(3), do: "🟠 Niedrig"
  defp energy_label(4), do: "🟠 Etwas niedrig"
  defp energy_label(5), do: "🟡 Mittel"
  defp energy_label(6), do: "🟡 Gut"
  defp energy_label(7), do: "🟢 Hoch"
  defp energy_label(8), do: "🟢 Sehr hoch"
  defp energy_label(9), do: "🟢 Peak"
  defp energy_label(10), do: "🟢 Flow"

  defp format_minutes(m), do: "#{div(m, 60)}h #{rem(m, 60)}min"

  defp break_status(nil), do: "⚠️ Keine Pause heute"
  defp break_status(time) do
    case DateTime.new(Date.utc_today(), time, "Etc/UTC") do
      {:ok, dt} ->
        diff = DateTime.diff(DateTime.utc_now(), dt)
        if diff > 5400, do: "⚠️ Überfällig (#{div(diff, 60)}min her)", else: "✅ Vor #{div(diff, 60)}min"
      :error ->
        "⚠️ Ungültige Zeit"
    end
  end

  defp update_task_status(socket, task_id) do
    tasks = Enum.map(socket.assigns.top_tasks, fn task ->
      if task.id == task_id, do: Map.put(task, :done, not task.done), else: task
    end)
    assign(socket, top_tasks: tasks)
  end

  defp add_quick_task(socket, title, project) do
    new_task = %{
      id: to_string(System.unique_integer()),
      title: title,
      project: project,
      done: false,
      urgency: "medium"
    }
    assign(socket, top_tasks: [new_task | socket.assigns.top_tasks])
  end

  defp log_focus_session(socket, duration, type) do
    new_focus = socket.assigns.focus_today + duration
    new_count = socket.assigns.pomodoro_count + (if type == "pomodoro", do: 1, else: 0)
    new_break = if type == "break", do: Time.utc_now() |> Time.truncate(:minute), else: socket.assigns.last_break
    assign(socket,
      focus_today: new_focus,
      pomodoro_count: new_count,
      last_break: new_break,
      current_session_type: type
    )
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
