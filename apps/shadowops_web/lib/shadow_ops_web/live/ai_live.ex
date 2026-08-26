defmodule ShadowOpsWeb.AILive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(_params, _session, socket), do: {:ok, assign(socket, data: ShadowOpsApi.ai())}

  def render(assigns) do
    ~H"""
    <.app_shell
      title="AI Runtime"
      subtitle="Remote-only model execution · local inference disabled by policy"
      active="/ai"
      availability="AVAILABLE"
      updated_at={@data[:updated_at]}
    >
      <.source_meta
        source="remote-only AI policy + runtime discovery"
        updated_at={@data[:updated_at]}
        availability="AVAILABLE"
      />

      <.panel
        title="AI execution policy"
        description="ShadowOps coding and model execution requires an explicitly selected remote provider/model. No local-model fallback is permitted."
      >
        <div class="mc-detail-grid">
          <dl class="mc-dl">
            <dt>Execution policy</dt><dd><.status_badge status="AVAILABLE" label="REMOTE_ONLY" /></dd>
            <dt>Model authority</dt><dd class="mc-mono">explicit provider/model</dd>
            <dt>Local inference</dt><dd><.status_badge status="NOT_CONFIGURED" label="DISABLED" /></dd>
          </dl>
          <div class="mc-callout">
            Runtime discovery may report locally installed model services, but discovery does not authorize inference. Local runtimes are never an execution fallback.
          </div>
        </div>
      </.panel>

      <.panel
        title="Detected local runtimes"
        description="Inventory only. Any records below are informational and are not approved execution targets."
      >
        <div :if={@data.models != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Model</th><th>Node</th><th>Details</th><th>Execution</th></tr></thead>
            <tbody>
              <tr :for={model <- @data.models}>
                <td class="mc-mono">{model.name}</td>
                <td>{model.node}</td>
                <td>{model.details}</td>
                <td><.status_badge status="NOT_CONFIGURED" label="POLICY_DISABLED" /></td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@data.models == []} class="mc-empty">
          No local model runtime inventory was reported. Remote model availability is established by the configured remote provider/model at execution time.
        </p>
      </.panel>
    </.app_shell>
    """
  end
end
