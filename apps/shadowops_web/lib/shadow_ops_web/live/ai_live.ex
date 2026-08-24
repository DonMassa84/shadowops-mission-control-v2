defmodule ShadowOpsWeb.AILive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(_params, _session, socket), do: {:ok, assign(socket, data: ShadowOpsApi.ai())}

  def render(assigns) do
    ~H"""
    <.app_shell title="AI Runtime" subtitle="Installed local Ollama models" active="/ai" availability={@data.status} updated_at={@data[:updated_at]}>
      <.source_meta source={@data.source} updated_at={@data[:updated_at]} availability={@data.status} />
      <.panel title="Installed models" description="Only models returned by the real Ollama CLI are listed.">
        <div :if={@data.models != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Model</th><th>Node</th><th>Details</th><th>Source</th></tr></thead><tbody><tr :for={model <- @data.models}><td class="mc-mono">{model.name}</td><td>{model.node}</td><td>{model.details}</td><td>{model.source}</td></tr></tbody></table></div><p :if={@data.models == []} class="mc-empty">No installed model records were reported by a reachable runtime.</p>
      </.panel>
    </.app_shell>
    """
  end
end
