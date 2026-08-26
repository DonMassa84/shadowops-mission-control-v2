defmodule ShadowOpsWeb.ApprovalsLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  alias ShadowOpsWeb.OneClick

  def mount(_params, _session, socket) do
    data = ShadowOpsApi.approvals()

    {:ok,
     assign(socket,
       data: data,
       approvals: data.records,
       updated_at: now(),
       one_click_ready: OneClick.available?()
     )}
  end

  def handle_event("decide", %{"id" => id, "action" => action}, socket) do
    case OneClick.decide_approval(id, action) do
      {:ok, approval} ->
        data = ShadowOpsApi.approvals()

        {:noreply,
         socket
         |> assign(
           data: data,
           approvals: data.records,
           updated_at: now(),
           one_click_ready: OneClick.available?()
         )
         |> put_flash(:info, "#{approval.id}: #{approval.status}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Approval decision failed: #{safe_reason(reason)}")}
    end
  end

  def render(assigns) do
    ~H"""
    <.app_shell title="Approvals" subtitle="Durable high-risk decision records" active="/approvals" availability={@data.status} updated_at={@updated_at}>
      <.source_meta source="append-only approval event store" updated_at={@updated_at} availability={@data.status} />
      <p class="mc-callout">
        One-click mode: <strong>{if(@one_click_ready, do: "READY", else: "WRITE TOKEN REQUIRED")}</strong> · Approve/Reject buttons are explicit operator decisions and remain immutable audit events.
      </p>
      <.panel title="Approval records"><div :if={@approvals != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Requested</th><th>Requester</th><th>Action</th><th>Resource</th><th>Reason</th><th>Status</th><th>Decision</th><th>Actor</th><th>Audit</th><th>One click</th></tr></thead><tbody><tr :for={a <- @approvals}><td>{time(a.requested_at)}</td><td>{a.requested_by}</td><td>{a.action}</td><td><a href={"/approvals/#{a.id}"}>{a.resource}</a></td><td>{a.reason}</td><td><.status_badge status={a.status} /></td><td>{time(a.decision_at)}</td><td>{available(a.decided_by)}</td><td class="mc-mono">{available(a.audit_ref)}</td><td class="mc-actions"><button :if={a.status == "PENDING"} class="mc-button" type="button" phx-click="decide" phx-value-id={a.id} phx-value-action="approve" disabled={!@one_click_ready}>✓ Approve</button><button :if={a.status == "PENDING"} class="mc-button" type="button" phx-click="decide" phx-value-id={a.id} phx-value-action="reject" disabled={!@one_click_ready}>× Reject</button><span :if={a.status != "PENDING"} class="mc-muted">Final</span></td></tr></tbody></table></div><p :if={@approvals == []} class="mc-empty">No approval has been requested.</p></.panel>
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
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
