defmodule ShadowOpsWeb.EvidenceLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  def mount(_, _, socket), do: {:ok, assign(socket, data: ShadowOpsApi.evidence())}

  def render(assigns) do
    ~H"""
    <.app_shell title="Evidence" subtitle="Privacy-safe project artifacts" active="/evidence" availability={@data.availability} updated_at={@data.updated_at}>
      <.source_meta source={@data.source} updated_at={@data.updated_at} availability={@data.availability} />
      <.panel title="Evidence artifacts" description="Names and file metadata only; absolute filesystem paths are withheld."><div :if={@data.artifacts != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Artifact</th><th>Type</th><th>Modified</th><th>Source category</th><th>Verification</th><th>Linked workflow/run</th></tr></thead><tbody><tr :for={artifact <- @data.artifacts}><td>{artifact.artifact}</td><td>{artifact.type}</td><td>{artifact.modified}</td><td>{artifact.source_category}</td><td><.status_badge status={artifact.verification_status} /></td><td>Not available from current source</td></tr></tbody></table></div><p :if={@data.artifacts == []} class="mc-empty">No evidence artifact metadata is available.</p></.panel>
    </.app_shell>
    """
  end
end
