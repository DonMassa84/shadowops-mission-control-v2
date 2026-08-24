defmodule ShadowOpsWeb.ApprovalDetailLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(%{"id" => id}, _session, socket) do
    case ShadowOpsApi.get_approval(id) do
      {:ok, approval} -> {:ok, assign(socket, approval: approval)}
      _ -> {:ok, socket |> put_flash(:error, "Approval not found") |> redirect(to: "/approvals")}
    end
  end

  def render(assigns) do
    ~H"""
    <.app_shell title={@approval.id} subtitle="Approval decision record" active={"/approvals/#{@approval.id}"} availability={@approval.status}>
      <div class="mc-detail-grid"><.panel title="Request"><dl class="mc-dl"><dt>Requested at</dt><dd>{time(@approval.requested_at)}</dd><dt>Requested by</dt><dd>{@approval.requested_by}</dd><dt>Action</dt><dd>{@approval.action}</dd><dt>Resource</dt><dd>{@approval.resource}</dd><dt>Reason</dt><dd>{@approval.reason}</dd><dt>Expires</dt><dd>{time(@approval.expires_at)}</dd></dl></.panel><.panel title="Decision"><dl class="mc-dl"><dt>Status</dt><dd><.status_badge status={@approval.status} /></dd><dt>Decision at</dt><dd>{time(@approval.decision_at)}</dd><dt>Decided by</dt><dd>{available(@approval.decided_by)}</dd><dt>Audit ref</dt><dd class="mc-mono">{available(@approval.audit_ref)}</dd></dl><p class="mc-callout">Approve/reject is available only through authenticated API routes; terminal decisions cannot be rewritten.</p></.panel></div>
    </.app_shell>
    """
  end

  defp time(nil), do: "Not available"
  defp time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp available(nil), do: "Not available"
  defp available(value), do: to_string(value)
end
