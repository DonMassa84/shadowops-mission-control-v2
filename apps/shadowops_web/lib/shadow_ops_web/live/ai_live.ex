defmodule ShadowOpsWeb.AILive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(_params, _session, socket), do: {:ok, assign(socket, data: ShadowOpsApi.ai())}

  def render(assigns) do
    ~H"""
    <.app_shell
      title="AI Governance"
      subtitle="Remote-only coding agent · governed local product runtime"
      active="/ai"
      availability={@data[:availability] || "UNKNOWN"}
      updated_at={@data[:updated_at]}
    >
      <.source_meta
        source="docs/REMOTE_AI_POLICY.md + CapabilityRegistry + runtime inventory"
        updated_at={@data[:updated_at]}
        availability={@data[:availability] || "UNKNOWN"}
      />

      <.panel
        title="Coding agent"
        description="The development-plane AI contract remains remote-only and fail-closed. Local Ollama is never a coding-agent fallback."
      >
        <div class="mc-policy-grid">
          <div class="mc-policy-cell">
            <small>Policy</small>
            <strong>REMOTE_ONLY</strong>
            <span>ShadowOps coding uses an explicit remote provider/model.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Model authority</small>
            <strong>CLI --model</strong>
            <span>The exact OpenCode provider/model identifier is authoritative.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Local coding fallback</small>
            <strong>FORBIDDEN</strong>
            <span>Ollama, LM Studio and llama.cpp are not coding-agent providers.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Fallback</small>
            <strong>NONE</strong>
            <span>Missing or invalid remote model selection fails closed.</span>
          </div>
        </div>
      </.panel>

      <.panel
        title="Product AI runtime"
        description="Local Ollama is a separate product-runtime executor. Requests still pass through ShadowOps governance before adapter execution."
      >
        <div class="mc-policy-grid">
          <div class="mc-policy-cell">
            <small>Provider</small>
            <strong>OLLAMA LOCAL</strong>
            <span>Runtime inventory is read from the local Ollama source.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Execution</small>
            <strong>GOVERNED</strong>
            <span>Capability: ollama.generate · executor: ollama_runtime.</span>
          </div>
          <div class="mc-policy-cell">
            <small>Runtime availability</small>
            <strong>{@data[:availability] || "UNKNOWN"}</strong>
            <span>{length(@data.models)} discovered model record(s).</span>
          </div>
          <div class="mc-policy-cell">
            <small>Control path</small>
            <strong>POLICY + AUDIT</strong>
            <span>Policy decision is required by the adapter; governed execution remains auditable.</span>
          </div>
        </div>

        <p class="mc-policy-warning">
          <strong>Inventory is not certification.</strong>
          A discovered local model is an available runtime resource, not proof that the model passed ShadowOps production-quality gates.
        </p>
      </.panel>

      <.panel
        title="Local runtime inventory"
        description="Evidence-backed discovery for product AI runtimes. These records do not authorize coding-agent use."
      >
        <div :if={@data.models != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr><th>Model</th><th>Node</th><th>Details</th><th>Source</th><th>Product runtime</th></tr>
            </thead>
            <tbody>
              <tr :for={model <- @data.models}>
                <td class="mc-mono">{model.name}</td>
                <td>{model.node}</td>
                <td>{model.details}</td>
                <td>{model.source}</td>
                <td><span class="mc-inventory-forbidden">GOVERNED</span></td>
              </tr>
            </tbody>
          </table>
        </div>

        <p :if={@data.models == []} class="mc-empty">
          No local model inventory was reported. Product AI runtime is unavailable until a governed Ollama resource is discoverable; coding remains remote-only regardless.
        </p>
      </.panel>
    </.app_shell>
    """
  end
end
