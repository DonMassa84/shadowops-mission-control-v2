defmodule ShadowOpsWeb.DailyControlLive do
  @moduledoc """
  Read-only Daily Control LiveView.

  Reuses app_shell, status_badge, metric_card, and panel components. Both
  mount and the Tagescheck button use the same pure projection through
  ShadowOpsCore.DailyControl, so API and UI can never diverge.
  """
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsWeb.RuntimeOverview
  alias ShadowOpsWeb.ProjectDomains

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, snapshot: compute_snapshot())}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, snapshot: compute_snapshot())}
  end

  defp compute_snapshot do
    ShadowOpsCore.DailyControl.snapshot(
      overview: RuntimeOverview.snapshot(),
      ihk_domain: ProjectDomains.snapshot(:ihk)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app_shell title="Daily Control" subtitle="One-Click Tagescheck" active="/daily-control" availability={@snapshot.status} updated_at={@snapshot.generated_at}>
      <div class="mc-panel mc-panel--summary">
        <header class="mc-panel-head">
          <div>
            <h2>Gesamtstatus</h2>
            <p>{@snapshot.summary}</p>
          </div>
          <div class="mc-actions">
            <button class="mc-button" phx-click="refresh">Tagescheck</button>
          </div>
        </header>
        <div class="mc-status-row">
          <.status_badge status={@snapshot.status} label={@snapshot.status} />
          <.status_badge status={@snapshot.severity} label={"Severity: #{@snapshot.severity}"} />
        </div>
      </div>

      <div class="mc-checks-grid">
        <.panel :for={check <- @snapshot.checks} title={check.domain} description={check.summary}>
          <.status_badge status={check.status} />
          <.metric_card :if={check.severity != "INFO"} label="Schweregrad" value={check.severity} status={check.severity} />
        </.panel>
      </div>

      <.panel :if={@snapshot.attention_required} title="Aufmerksamkeit erforderlich" description="Bereiche, die nicht im grünen Bereich sind">
        <div class="mc-attention-list">
          <div :for={check <- Enum.reject(@snapshot.checks, &(&1.status == "GREEN"))} class="mc-attention-item">
            <.status_badge status={check.status} label={check.domain} />
            <span>{check.summary}</span>
          </div>
        </div>
      </.panel>

      <.panel :if={@snapshot.top_actions != []} title="Top 3 Next Actions" description="Deterministisch bewertete nächste Schritte">
        <div class="mc-actions-list">
          <div :for={action <- @snapshot.top_actions} class="mc-action-item">
            <span class="mc-action-rank">#{action.rank}</span>
            <.status_badge status={action.severity} label={action.severity} />
            <span class="mc-action-title">{action.title}</span>
            <small class="mc-action-score">Score: :erlang.float_to_binary(action.score, decimals: 2)</small>
          </div>
        </div>
      </.panel>
    </.app_shell>
    """
  end
end
