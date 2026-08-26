defmodule ShadowOpsWeb.AgentsLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(_, _, socket), do: {:ok, assign(socket, data: ShadowOpsApi.agents())}

  def render(assigns) do
    ~H"""
    <.app_shell
      title="Agents"
      subtitle="Runtime-discovered automation agents · AI model execution remains remote-only"
      active="/agents"
      availability={@data.status}
      updated_at={@data.updated_at}
    >
      <.source_meta source={@data.source} updated_at={@data.updated_at} availability={@data.status} />

      <.panel
        title="Agent execution boundary"
        description="Agent process discovery does not authorize a local AI model. ShadowOps requires an explicit verified remote provider/model for AI-assisted coding."
      >
        <section class="mc-grid" aria-label="Agent governance summary">
          <.metric_card
            label="AI policy"
            value="REMOTE ONLY"
            status="PASS"
            source="docs/REMOTE_AI_POLICY.md"
            note="No local inference or automatic remote-to-local fallback."
          />
          <.metric_card
            label="Detected agents"
            value={length(@data.records)}
            status={@data.status}
            source={@data.source}
            note="Process discovery only; capabilities remain independently governed."
          />
        </section>
      </.panel>

      <.unavailable_state
        :if={@data.records == []}
        title="No agents detected"
        reason="No service matching the explicit agent runtime classifier was reported by a reachable service source."
        source="systemd service discovery"
      />

      <.panel
        :if={@data.records != []}
        title="Detected agents"
        description="Unknown model, task, and queue values are intentionally left empty. A discovered local model is never treated as an authorized execution target."
      >
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Agent</th><th>Status</th><th>Runtime</th><th>Model evidence</th><th>Node</th><th>Last activity</th><th>Error</th></tr></thead>
            <tbody>
              <tr :for={agent <- @data.records}>
                <td>{agent.name}</td>
                <td><.status_badge status={agent.status} /></td>
                <td>{agent.runtime}</td>
                <td>{agent.model || "Not evidenced / not authoritative"}</td>
                <td>{agent.node}</td>
                <td>{agent.last_activity || "Not evidenced"}</td>
                <td>{inspect(agent.error || agent.error_message)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>
    </.app_shell>
    """
  end
end
