defmodule ShadowOpsWeb.KnowledgeLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(_, _, socket), do: {:ok, assign(socket, data: ShadowOpsApi.knowledge())}

  def render(assigns) do
    ~H"""
    <.app_shell
      title="Knowledge"
      subtitle="Private source metadata only"
      active="/knowledge"
      availability={@data.status}
      updated_at={@data.updated_at}
    >
      <.source_meta
        source={@data.source}
        updated_at={@data.updated_at}
        availability={@data.status}
      />

      <.panel
        title="Configured stores"
        description="Mission Control does not expose note content or absolute paths."
      >
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr>
                <th>Source</th>
                <th>Availability</th>
                <th>Measured documents</th>
                <th>Last update</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={source <- @data.sources}>
                <td>{source.source}</td>
                <td><.status_badge status={source.availability} /></td>
                <td>{source[:document_count] || "Not measurable"}</td>
                <td>{source[:last_update] || "Not available"}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>

      <.panel
        title="Slides"
        description="Curated ShadowOps presentation artifacts available from the local control plane."
      >
        <div class="mc-table-wrap">
          <table class="mc-table">
            <thead>
              <tr>
                <th>Deck</th>
                <th>Slides</th>
                <th>Status</th>
                <th>Open</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Kontrollierte Präsenz</td>
                <td>9</td>
                <td><.status_badge status="AVAILABLE" /></td>
                <td><a href="/slides/controlled-presence.html">Open deck</a></td>
              </tr>
            </tbody>
          </table>
        </div>
      </.panel>
    </.app_shell>
    """
  end
end
