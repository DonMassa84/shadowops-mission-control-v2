defmodule ShadowOpsWeb.AILive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(_params, _session, socket), do: {:ok, assign(socket, data: ShadowOpsApi.ai())}

  def render(assigns) do
    ~H"""
    <.app_shell
      title="AI Policy"
      subtitle="Remote-only model execution · local runtimes are inventory-only and never an execution fallback"
      active="/ai"
      availability="AVAILABLE"
      updated_at={@data[:updated_at]}
    >
      <section class="mc-grid" aria-label="AI execution policy">
        <.metric_card
          label="Execution policy"
          value="REMOTE ONLY"
          status="PASS"
          source="docs/REMOTE_AI_POLICY.md"
          note="Every coding run must select an explicit remote provider/model identifier."
        />
        <.metric_card
          label="Remote provider"
          value="PER RUN"
          status="NOT_ASSESSED"
          source="OpenCode model contract"
          note="The exact provider/model must be verified by opencode models before execution."
        />
        <.metric_card
          label="Local inference"
          value="BLOCKED"
          status="BLOCKED"
          source="AI_EXECUTION_POLICY=REMOTE_ONLY"
          note="Ollama, LM Studio and llama.cpp are not authorized ShadowOps execution paths."
        />
      </section>

      <.panel
        title="Execution contract"
        description="This UI reports policy separately from runtime discovery so an installed local model can never be mistaken for an authorized execution target."
      >
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr><th>Control</th><th>Required state</th><th>Authority</th></tr>
            </thead>
            <tbody>
              <tr><td>Model selection</td><td><.status_badge status="PASS" label="Explicit remote provider/model" /></td><td class="mc-mono">SHADOWOPS_CODER_MODEL</td></tr>
              <tr><td>Model verification</td><td><.status_badge status="PASS" label="Must exist" /></td><td class="mc-mono">opencode models</td></tr>
              <tr><td>Execution authority</td><td><.status_badge status="PASS" label="CLI authoritative" /></td><td class="mc-mono">--model</td></tr>
              <tr><td>Local fallback</td><td><.status_badge status="BLOCKED" label="Forbidden" /></td><td>Remote-only policy</td></tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel
        title="Local runtime inventory"
        description="Discovery only. These records remain useful for diagnostics, but they are not eligible ShadowOps AI execution targets."
      >
        <div :if={@data.models != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Model</th><th>Node</th><th>Execution</th><th>Details</th><th>Discovery source</th></tr></thead>
            <tbody>
              <tr :for={model <- @data.models}>
                <td class="mc-mono">{model.name}</td>
                <td>{model.node}</td>
                <td><.status_badge status="BLOCKED" label="Inventory only" /></td>
                <td>{model.details}</td>
                <td>{model.source}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@data.models == []} class="mc-empty">
          No local model records were discovered. Remote-only policy remains authoritative regardless of inventory state.
        </p>
      </.panel>
    </.app_shell>
    """
  end
end
