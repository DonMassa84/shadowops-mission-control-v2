defmodule ShadowOpsWeb.AILive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsWeb.AIStatus

  def mount(_params, _session, socket), do: {:ok, assign(socket, data: AIStatus.snapshot())}

  def render(assigns) do
    ~H"""
    <.app_shell
      title="AI Governance"
      subtitle="Remote-only coding · no local LLM runtime"
      active="/ai"
      availability={@data.status}
      updated_at={@data.updated_at}
    >
      <.source_meta
        source={@data.source}
        updated_at={@data.updated_at}
        availability={@data.status}
      />

      <.panel
        title="Coding execution policy"
        description="ShadowOps coding uses explicit remote OpenCode providers. Local LLM execution is disabled and is never used as a fallback."
      >
        <div class="mc-policy-grid">
          <div class="mc-policy-cell">
            <small>Execution</small>
            <strong>REMOTE_ONLY</strong>
            <span>Only an explicitly selected remote provider/model may execute coding work.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Model authority</small>
            <strong>CLI --model</strong>
            <span>The exact OpenCode model identifier is authoritative.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Local LLM runtime</small>
            <strong>DISABLED</strong>
            <span>No local Ollama model inventory is exposed by Mission Control.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Fallback</small>
            <strong>NONE</strong>
            <span>Invalid or unavailable remote selection fails closed.</span>
          </div>
        </div>
      </.panel>
    </.app_shell>
    """
  end
end
