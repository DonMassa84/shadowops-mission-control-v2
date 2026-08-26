defmodule ShadowOpsWeb.AILive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(_params, _session, socket), do: {:ok, assign(socket, data: ShadowOpsApi.ai())}

  def render(assigns) do
    ~H"""
    <.app_shell
      title="AI Governance"
      subtitle="Remote-only model execution · local inference is forbidden for ShadowOps coding and automation"
      active="/ai"
      availability="AVAILABLE"
      updated_at={@data[:updated_at]}
    >
      <.source_meta
        source="docs/REMOTE_AI_POLICY.md + runtime inventory"
        updated_at={@data[:updated_at]}
        availability="AVAILABLE"
      />

      <.panel
        title="Execution policy"
        description="The UI reports the binding execution contract separately from any locally installed model inventory."
      >
        <div class="mc-policy-grid">
          <div class="mc-policy-cell">
            <small>AI execution</small>
            <strong>REMOTE_ONLY</strong>
            <span>No local inference fallback.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Model authority</small>
            <strong>CLI --model</strong>
            <span>The explicit provider/model identifier is authoritative.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Local models</small>
            <strong>FORBIDDEN</strong>
            <span>Ollama, LM Studio and llama.cpp are not valid ShadowOps execution providers.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Fallback</small>
            <strong>NONE</strong>
            <span>Missing or invalid remote model selection must fail closed.</span>
          </div>
        </div>
      </.panel>

      <.panel
        title="Local runtime inventory"
        description="Discovery only. A locally installed model is not an authorized ShadowOps execution target."
      >
        <p class="mc-policy-warning">
          <strong>Inventory is not authorization.</strong>
          Local model records may still exist on the host, but ShadowOps must not select or execute them under the REMOTE_ONLY policy.
        </p>

        <div :if={@data.models != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr><th>Model</th><th>Node</th><th>Details</th><th>Source</th><th>ShadowOps execution</th></tr>
            </thead>
            <tbody>
              <tr :for={model <- @data.models}>
                <td class="mc-mono">{model.name}</td>
                <td>{model.node}</td>
                <td>{model.details}</td>
                <td>{model.source}</td>
                <td><span class="mc-inventory-forbidden">FORBIDDEN</span></td>
              </tr>
            </tbody>
          </table>
        </div>

        <p :if={@data.models == []} class="mc-empty">
          No local model inventory was reported. Remote execution still requires an explicit provider/model identifier verified by OpenCode.
        </p>
      </.panel>
    </.app_shell>
    """
  end
end
