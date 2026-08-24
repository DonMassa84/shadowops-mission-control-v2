defmodule ShadowOpsWeb.WorkflowDetailLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(%{"id" => id}, _session, socket) do
    case ShadowOpsApi.get_workflow(id) do
      {:ok, workflow} ->
        {:ok, runs} = ShadowOpsApi.list_runs()
        {:ok, audit} = ShadowOpsApi.list_audit_events()

        {:ok,
         assign(socket,
           workflow: workflow,
           runs: Enum.filter(runs, &(&1.workflow_id == id)),
           audit: Enum.filter(audit, &(&1["resource"] == id)),
           updated_at: now()
         )}

      {:error, :not_found} ->
        {:ok, socket |> put_flash(:error, "Workflow not found") |> redirect(to: "/workflows")}
    end
  end

  def render(assigns) do
    ~H"""
    <.app_shell title={@workflow["id"]} subtitle="Workflow detail" active={"/workflows/#{@workflow["id"]}"} updated_at={@updated_at}>
      <div class="mc-statline"><.status_badge status={@workflow["status"]} /><.status_badge status="REVIEW" label="L2 approval required" /><span class="mc-muted">Source: workflow registry v2</span></div>
      <div class="mc-detail-grid">
        <.panel title="Overview"><dl class="mc-dl"><dt>Display name</dt><dd>{display_name(@workflow)}</dd><dt>Type</dt><dd>{available(@workflow["type"])}</dd><dt>Domain</dt><dd>{available(@workflow["domain"])}</dd><dt>Status</dt><dd>{available(@workflow["status"])}</dd><dt>Runtime</dt><dd class="mc-mono">{available(@workflow["target_runtime"] || @workflow["runtime"])}</dd><dt>Trigger</dt><dd>{available(@workflow["trigger"])}</dd></dl></.panel>
        <.panel title="Execution policy" description="Backend authorization remains authoritative."><p class="mc-callout">Execution requires bearer write authorization, an authenticated actor and an APPROVED durable approval for action <span class="mc-mono">workflow.execute</span>.</p><a class="mc-button" href={"/approvals?resource=#{@workflow["id"]}"}>Review approvals</a></.panel>
      </div>
      <.panel title="Configuration and dependencies"><div class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Registry field</th><th>Value</th></tr></thead><tbody><tr :for={{key, value} <- configuration(@workflow)}><td>{key}</td><td class="mc-mono">{format_value(value)}</td></tr></tbody></table></div></.panel>
      <.panel title="Recent real runs"><div :if={@runs != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Run</th><th>Status</th><th>Actor</th><th>Queued</th><th>Evidence</th></tr></thead><tbody><tr :for={run <- @runs}><td><a href={"/runs/#{run.id}"}>{run.id}</a></td><td><.status_badge status={run.status} /></td><td>{run.requested_by}</td><td>{time(run.queued_at)}</td><td>{available(run.evidence_ref)}</td></tr></tbody></table></div><p :if={@runs == []} class="mc-empty">No persisted execution exists for this workflow.</p></.panel>
      <.panel title="Audit events"><div :if={@audit != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Time</th><th>Actor</th><th>Action</th><th>Result</th><th>Evidence</th></tr></thead><tbody><tr :for={event <- @audit}><td>{event["timestamp"]}</td><td>{event["actor"]}</td><td>{event["action"]}</td><td><.status_badge status={event["result"]} /></td><td>{available(event["evidence_ref"])}</td></tr></tbody></table></div><p :if={@audit == []} class="mc-empty">No audit event currently references this workflow.</p></.panel>
    </.app_shell>
    """
  end

  defp configuration(workflow), do: workflow |> Map.drop(["id"]) |> Enum.sort_by(&elem(&1, 0))

  defp display_name(w),
    do:
      w["display_name"] || w["name"] || w["id"] |> String.replace("_", " ") |> String.capitalize()

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: Jason.encode!(value)
  defp available(nil), do: "Not available from current source"
  defp available(""), do: "Not available from current source"
  defp available(value), do: to_string(value)
  defp time(nil), do: "Not available from current source"
  defp time(%DateTime{} = time), do: DateTime.to_iso8601(time)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
