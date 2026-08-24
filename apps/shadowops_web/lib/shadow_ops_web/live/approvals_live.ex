defmodule ShadowOpsWeb.ApprovalsLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(_params, _session, socket) do
    data = ShadowOpsApi.approvals()
    {:ok, assign(socket, data: data, approvals: data.records, updated_at: now())}
  end

  def render(assigns) do
    ~H"""
    <.app_shell title="Approvals" subtitle="Durable high-risk decision records" active="/approvals" availability={@data.status} updated_at={@updated_at}>
      <.source_meta source="append-only approval event store" updated_at={@updated_at} availability={@data.status} />
      <p class="mc-callout">Creation and decisions require authenticated write API calls. The browser view never embeds authorization tokens.</p>
      <.panel title="Approval records"><div :if={@approvals != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Requested</th><th>Requester</th><th>Action</th><th>Resource</th><th>Reason</th><th>Status</th><th>Decision</th><th>Actor</th><th>Audit</th></tr></thead><tbody><tr :for={a <- @approvals}><td>{time(a.requested_at)}</td><td>{a.requested_by}</td><td>{a.action}</td><td><a href={"/approvals/#{a.id}"}>{a.resource}</a></td><td>{a.reason}</td><td><.status_badge status={a.status} /></td><td>{time(a.decision_at)}</td><td>{available(a.decided_by)}</td><td class="mc-mono">{available(a.audit_ref)}</td></tr></tbody></table></div><p :if={@approvals == []} class="mc-empty">No approval has been requested.</p></.panel>
    </.app_shell>
    """
  end

  defp time(nil), do: "Not available"
  defp time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp available(nil), do: "Not available"
  defp available(value), do: to_string(value)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
