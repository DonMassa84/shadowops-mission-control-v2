defmodule ShadowOpsWeb.HighValueWorkflowsLive do
  use Phoenix.LiveView

  import ShadowOpsWeb.MissionControlComponents

  alias ShadowOpsCore.WorkflowJobs
  alias ShadowOpsWeb.{HighValueWorkflows, OneClick}

  @tabs [
    {"daily_control", "Tagescheck"},
    {"system_doctor", "System prüfen"},
    {"release_acceptance", "Release prüfen"},
    {"ihk_evidence_gate", "IHK-Nachweise prüfen"},
    {"career_control", "Karriere prüfen"}
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:tabs, @tabs)
     |> assign(:selected, "daily_control")
     |> refresh()}
  end

  def handle_event("select", %{"workflow" => workflow}, socket),
    do: {:noreply, assign(socket, :selected, workflow)}

  def handle_event("refresh", _params, socket), do: {:noreply, refresh(socket)}

  def handle_event("run-release", _params, socket) do
    result =
      cond do
        not WorkflowJobs.enabled?() -> {:error, :workflow_jobs_required}
        not OneClick.available?() -> {:error, :one_click_unavailable}
        true -> OneClick.execute_workflow("release_acceptance")
      end

    socket =
      case result do
        {:ok, _run} ->
          put_flash(
            socket,
            :info,
            "Release acceptance queued through the governed workflow path."
          )

        {:error, reason} ->
          put_flash(socket, :error, "Release acceptance blocked: #{inspect(reason)}")
      end

    {:noreply, refresh(socket)}
  end

  def render(assigns) do
    current = Map.fetch!(assigns.workflows, String.to_existing_atom(assigns.selected))
    assigns = assign(assigns, :current, current)

    ~H"""
    <.app_shell
      title="High-Value Control"
      subtitle="Five evidence-backed one-click workflows"
      active="/control"
      availability={if(@current.status == "GREEN", do: "AVAILABLE", else: @current.status)}
      updated_at={@current.generated_at}
    >
      <.panel title="One-click workflows" description="Read-only checks refresh evidence. Release execution stays governed.">
        <div class="mc-actions">
          <button
            :for={{key, label} <- @tabs}
            type="button"
            class="mc-button"
            phx-click="select"
            phx-value-workflow={key}
          >
            {label}
          </button>
          <button type="button" class="mc-button" phx-click="refresh">Aktualisieren</button>
          <button
            :if={@selected == "release_acceptance"}
            type="button"
            class="mc-button"
            phx-click="run-release"
            disabled={not OneClick.available?() or not WorkflowJobs.enabled?()}
          >
            Release Acceptance starten (governed / 4015)
          </button>
        </div>
      </.panel>

      <.panel title={@current.workflow_id} description={@current.summary}>
        <div class="mc-kpis">
          <div class="mc-kpi"><span>Status</span><.status_badge status={@current.status} /></div>
          <div class="mc-kpi"><span>Severity</span><strong>{@current.severity}</strong></div>
          <div class="mc-kpi"><span>Attention</span><strong>{if(@current.attention_required, do: "YES", else: "NO")}</strong></div>
        </div>
      </.panel>

      <.panel title="Checks" description="Missing evidence never becomes success.">
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Check</th><th>Status</th><th>Severity</th><th>Source</th></tr></thead>
            <tbody>
              <tr :for={check <- @current.checks}>
                <td>{check.title}</td>
                <td><.status_badge status={check.status} /></td>
                <td>{check.severity}</td>
                <td>{check.source}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel title="Top actions" description="Deterministic ranking, maximum three actions.">
        <p :if={@current.next_actions == []} class="mc-empty">No action is currently evidenced.</p>
        <div :if={@current.next_actions != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Rank</th><th>Action</th><th>Reason</th><th>Score</th></tr></thead>
            <tbody>
              <tr :for={action <- @current.next_actions}>
                <td>{action.rank}</td>
                <td><a href={action.href}>{action.title}</a></td>
                <td>{action.reason}</td>
                <td>{action.score}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel
        :if={@selected == "ihk_evidence_gate"}
        title="IHK Evidence Score"
        description="VERIFIED=1, WEAK=0.5, MISSING=0."
      >
        <strong>{@current.evidence_score}%</strong>
        <p>VERIFIED {@current.verified_count} · WEAK {@current.weak_count} · MISSING {@current.missing_count}</p>
      </.panel>

      <.panel
        :if={@selected == "release_acceptance"}
        title="Release certificate"
        description="READY only for a complete exact-HEAD certificate."
      >
        <p>Release ready: {if(@current.release_ready, do: "YES", else: "NO")}</p>
        <p>Branch: {@current.branch || "UNKNOWN"}</p>
        <p>HEAD: {@current.head || "UNKNOWN"}</p>
      </.panel>
    </.app_shell>
    """
  end

  defp refresh(socket), do: assign(socket, :workflows, HighValueWorkflows.all())
end
