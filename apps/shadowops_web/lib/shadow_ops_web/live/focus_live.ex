defmodule ShadowOpsWeb.FocusLive do
  use Phoenix.LiveView

  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsCore.LearningFocus

  def mount(_params, _session, socket) do
    {:ok, plan} = LearningFocus.load()

    {:ok,
     assign(socket,
       plan: plan,
       updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
     )}
  end

  def render(assigns) do
    ~H"""
    <.app_shell
      title="Focus"
      subtitle="Current objective, next actions and execution rules"
      active="/focus"
      availability={@plan["availability"]}
      updated_at={@updated_at}
    >
      <.source_meta source={@plan["source"] || "learning_focus"} updated_at={@updated_at} availability={@plan["availability"]} />

      <%= if @plan["availability"] == "AVAILABLE" do %>
        <div class="mc-grid">
          <.metric_card label="Context" value={@plan["active_context"]} status="AVAILABLE" note="Current allowlisted focus context" />
          <.metric_card label="Focus block" value={"#{@plan["execution"]["focus_minutes"]} min"} status="READY" note={"Break #{@plan["execution"]["break_minutes"]} min"} />
          <.metric_card label="Next actions" value={length(@plan["next"])} status="AVAILABLE" note="Bounded configured priorities" />
          <.metric_card label="KPIs" value={length(@plan["kpis"])} status="AVAILABLE" note="Explicit outcome checks" />
        </div>

        <.panel title={@plan["goal"]["title"]} description={@plan["goal"]["smart"]}>
          <div class="mc-detail-grid">
            <div class="mc-callout"><strong>Current</strong><br />{@plan["current"]["title"]}<br /><span class="mc-muted">{@plan["current"]["instruction"]}</span></div>
            <div class="mc-callout"><strong>Done when</strong><br />{@plan["current"]["done_when"]}</div>
          </div>
        </.panel>

        <.panel title="Next" description="Configured next actions only; nothing is inferred from private data here.">
          <ol>
            <li :for={item <- @plan["next"]}>{item}</li>
          </ol>
        </.panel>

        <.panel title="Execution rules">
          <dl class="mc-dl">
            <dt>Rule</dt><dd>{@plan["execution"]["rule"]}</dd>
            <dt>Error rule</dt><dd>{@plan["execution"]["error_rule"]}</dd>
            <dt>Output rule</dt><dd>{@plan["execution"]["output_rule"]}</dd>
          </dl>
        </.panel>

        <.panel title="KPIs">
          <div class="mc-table-wrap"><table class="mc-table"><thead><tr><th>KPI</th><th>Target</th></tr></thead><tbody><tr :for={kpi <- @plan["kpis"]}><td><strong>{kpi["name"]}</strong></td><td>{kpi["target"]}</td></tr></tbody></table></div>
        </.panel>
      <% else %>
        <.unavailable_state title="Focus plan unavailable" state="UNAVAILABLE" reason={@plan["detail"] || "Learning focus source is unavailable"} source="config/learning_focus.yaml" />
      <% end %>
    </.app_shell>
    """
  end
end
