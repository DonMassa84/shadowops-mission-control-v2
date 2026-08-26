defmodule ShadowOpsWeb.AILive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(_params, _session, socket), do: {:ok, assign(socket, data: ShadowOpsApi.ai())}

  def render(assigns) do
    ~H"""
    <.app_shell
      title="AI Governance"
      subtitle="Remote-only AI execution · no local Ollama LLM runtime"
      active="/ai"
      availability="AVAILABLE"
      updated_at={@data[:updated_at]}
    >
      <.source_meta
        source="docs/REMOTE_AI_POLICY.md"
        updated_at={@data[:updated_at]}
        availability="AVAILABLE"
      />

      <.panel
        title="Execution policy"
        description="ShadowOps coding and AI-assisted execution use explicitly selected remote models only. Local Ollama LLM execution is disabled."
      >
        <div class="mc-policy-grid">
          <div class="mc-policy-cell">
            <small>AI execution</small>
            <strong>REMOTE_ONLY</strong>
            <span>No local LLM inference fallback.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Model authority</small>
            <strong>CLI --model</strong>
            <span>The explicit OpenCode provider/model identifier is authoritative.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Local LLM runtime</small>
            <strong>DISABLED</strong>
            <span>Ollama-hosted LLMs are not part of the ShadowOps dashboard or execution path.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Fallback</small>
            <strong>NONE</strong>
            <span>Missing or invalid remote model selection fails closed.</span>
          </div>
        </div>
      </.panel>

      <.panel
        title="Runtime contract"
        description="The dashboard reports policy and remote execution authority only; local LLM inventory is intentionally not surfaced."
      >
        <p class="mc-policy-warning">
          <strong>Local LLM inventory disabled.</strong>
          ShadowOps does not list, select, benchmark, or execute Ollama-hosted LLMs from this control surface.
        </p>
      </.panel>
    </.app_shell>
    """
  end
end
