defmodule ShadowOpsWeb.ApprovalDetailLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  alias ShadowOpsWeb.OneClick

  def mount(%{"id" => id}, _session, socket) do
    case ShadowOpsApi.get_approval(id) do
      {:ok, approval} ->
        {:ok,
         assign(socket,
           approval: approval,
           one_click_ready: OneClick.available?()
         )}

      _ ->
        {:ok, socket |> put_flash(:error, "Approval not found") |> redirect(to: "/approvals")}
    end
  end

  def handle_event("decide", %{"action" => action}, socket) do
    case OneClick.decide_approval(socket.assigns.approval.id, action) do
      {:ok, approval} ->
        {:noreply,
         socket
         |> assign(approval: approval, one_click_ready: OneClick.available?())
         |> put_flash(:info, "Approval #{approval.status}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Approval decision failed: #{safe_reason(reason)}")}
    end
  end

  def render(assigns) do
    ~H"""
    <.app_shell title={@approval.id} subtitle="Approval decision record" active={"/approvals/#{@approval.id}"} availability={@approval.status}>
      <div class="mc-detail-grid"><.panel title="Request"><dl class="mc-dl"><dt>Requested at</dt><dd>{time(@approval.requested_at)}</dd><dt>Requested by</dt><dd>{@approval.requested_by}</dd><dt>Action</dt><dd>{@approval.action}</dd><dt>Resource</dt><dd>{@approval.resource}</dd><dt>Reason</dt><dd>{@approval.reason}</dd><dt>Expires</dt><dd>{time(@approval.expires_at)}</dd></dl></.panel><.panel title="Decision"><dl class="mc-dl"><dt>Status</dt><dd><.status_badge status={@approval.status} /></dd><dt>Decision at</dt><dd>{time(@approval.decision_at)}</dd><dt>Decided by</dt><dd>{available(@approval.decided_by)}</dd><dt>Audit ref</dt><dd class="mc-mono">{available(@approval.audit_ref)}</dd></dl><div :if={@approval.status == "PENDING"} class="mc-actions"><button class="mc-button" type="button" phx-click="decide" phx-value-action="approve" disabled={!@one_click_ready}>✓ Approve</button><button class="mc-button" type="button" phx-click="decide" phx-value-action="reject" disabled={!@one_click_ready}>× Reject</button></div><p :if={@approval.status != "PENDING"} class="mc-callout">Decision is final and cannot be rewritten.</p><p :if={!@one_click_ready and @approval.status == "PENDING"} class="mc-callout">Configure SHADOWOPS_WRITE_TOKEN to enable one-click decisions.</p></.panel></div>
    </.app_shell>
    """
  end

  defp time(nil), do: "Not available"
  defp time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp available(nil), do: "Not available"
  defp available(value), do: to_string(value)
  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({tag, _}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_reason(_), do: "approval_failed"
end
