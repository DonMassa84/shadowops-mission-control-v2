defmodule ShadowOpsWeb.ProjectCatalogLive do
  use Phoenix.LiveView

  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsWeb.ProjectCatalog

  def mount(_params, _session, socket) do
    catalog = ProjectCatalog.snapshot()
    {:ok, assign(socket, catalog: catalog)}
  end

  def render(assigns) do
    ~H"""
    <.app_shell
      title="Federated projects"
      subtitle="GitHub and ChatGPT project metadata from the private local ShadowOps catalog"
      active="/projects/federated"
      availability={@catalog.status}
      updated_at={@catalog.generated_at}
    >
      <.unavailable_state
        :if={@catalog.status != "READY"}
        title="Project federation not configured"
        state={@catalog.status}
        reason={@catalog.error_message || "Generate the local project catalog first"}
        source="SHADOWOPS_PROJECT_CATALOG"
      />

      <section :if={@catalog.status == "READY"} class="mc-grid" aria-label="Federated project counts">
        <.metric_card label="Projects" value={display_count(@catalog.counts.total)} status="READY" source="federated catalog" />
        <.metric_card label="GitHub" value={display_count(@catalog.counts.github)} status="READY" source={@catalog.github_discovery_mode} />
        <.metric_card label="ChatGPT" value={display_count(@catalog.counts.chatgpt)} status="READY" source="local library exports" />
        <.metric_card label="Ready" value={display_count(@catalog.counts.ready)} status="READY" source="truthfulness gate" />
      </section>

      <.panel
        :if={@catalog.status == "READY"}
        title="Project catalog"
        description="Metadata only. Raw project files, ChatGPT contents, credentials, and local export paths are not rendered."
      >
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr>
                <th>Project</th>
                <th>Source</th>
                <th>Status</th>
                <th>Visibility</th>
                <th>Mode</th>
                <th>Content ingested</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={project <- @catalog.projects}>
                <td>
                  <a :if={project.url} href={project.url} rel="noreferrer" target="_blank"><strong>{project.name}</strong></a>
                  <strong :if={!project.url}>{project.name}</strong>
                </td>
                <td>{source_label(project.source_type)}</td>
                <td><.status_badge status={project.status} /></td>
                <td>{project.visibility || "Local/private"}</td>
                <td>{project.integration_mode}</td>
                <td>{if project.content_ingested, do: "Yes", else: "No"}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>
    </.app_shell>
    """
  end

  defp display_count(nil), do: "N/A"
  defp display_count(value), do: value

  defp source_label("github_repository"), do: "GitHub"
  defp source_label("chatgpt_library_project"), do: "ChatGPT"
  defp source_label(value), do: value
end
