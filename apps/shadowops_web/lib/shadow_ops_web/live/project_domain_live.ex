defmodule ShadowOpsWeb.ProjectDomainLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsWeb.ProjectDomains

  def mount(_params, _session, socket) do
    domain = ProjectDomains.snapshot(socket.assigns.live_action)
    {:ok, assign(socket, domain: domain, path: "/projects/#{domain.id}")}
  end

  def render(assigns) do
    ~H"""
    <.app_shell
      title={@domain.name}
      subtitle="Private local project-domain state"
      active={@path}
      availability={@domain.status}
      updated_at={@domain.updated_at}
    >
      <section class="mc-grid" aria-label="Domain status">
        <.metric_card label="Status" value={@domain.status} status={@domain.status} source={@domain.source_type} />
        <.metric_card label="Open items" value={@domain.open_items || "Not evidenced"} status={@domain.status} source="local manifest" />
        <.metric_card label="Next deadline" value={@domain.next_deadline || "Not evidenced"} status={@domain.status} source="local manifest" />
        <.metric_card label="Classification" value={@domain.classification} status={@domain.status} source="privacy boundary" />
      </section>

      <.panel title="Summary" description="Only normalized local summary fields are rendered. Raw project records are not exposed here.">
        <dl class="mc-dl">
          <dt>Summary</dt><dd>{@domain.summary}</dd>
          <dt>Source</dt><dd class="mc-mono">{@domain.source || "Not configured"}</dd>
          <dt>Real data</dt><dd>{@domain.real_data}</dd>
          <dt>Reachable</dt><dd>{@domain.reachable}</dd>
          <dt>Error code</dt><dd>{@domain.error_code || "None"}</dd>
          <dt>Error</dt><dd>{@domain.error_message || "None"}</dd>
        </dl>
      </.panel>

      <p><a class="mc-button" href="/projects">All project domains</a></p>
    </.app_shell>
    """
  end
end
