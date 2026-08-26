defmodule ShadowOpsWeb.WorkflowDetailLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  alias ShadowOpsWeb.OneClick

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
           updated_at: now(),
           last_run: nil,
           one_click_ready: OneClick.available?()
         )}

      {:error, :not_found} ->
        {:ok, socket |> put_flash(:error, "Workflow not found") |> redirect(to: "/workflows")}
    end
  end

  def handle_event("one_click_run", _params, socket) do
    workflow_id = socket.assigns.workflow["id"]

    case OneClick.execute_workflow(workflow_id) do
      {:ok, run} ->
        refresh_after_run(socket, workflow_id, run, "Workflow one-click execution accepted")

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Workflow execution failed: #{safe_reason(reason)}")}
    end
  end

  def render(assigns) do
    ~H"""
    <.app_shell title={@workflow["id"]} subtitle="Workflow detail and governed execution" active={"/workflows/#{@workflow["id"]}"} updated_at={@updated_at}>
      <div class="mc-statline"><.status_badge status={@workflow["status"]} /><.status_badge status="REVIEW" label="L2 approval required" /><span class="mc-muted">Source: workflow registry v2</span></div>

      <.panel title="Run workflow" description="One click is the explicit local-operator decision. Required L2 approval is created, approved and audited before execution; no credential form is needed.">
        <button
          class="mc-button"
          type="button"
          phx-click="one_click_run"
          disabled={!@one_click_ready}
          title={if(@one_click_ready, do: "Approve if required and run now", else: "Configure SHADOWOPS_WRITE_TOKEN")}
        >
          ✓ Approve & run
        </button>
        <span class="mc-muted"> · One-click {if(@one_click_ready, do: "READY", else: "WRITE TOKEN REQUIRED")}</span>
        <p :if={@last_run} class="mc-callout">Run accepted: <a href={"/runs/#{@last_run.id}"} class="mc-mono">{@last_run.id}</a> · <strong>{@last_run.status}</strong></p>
      </.panel>

      <div class="mc-detail-grid">
        <.panel title="Overview"><dl class="mc-dl"><dt>Display name</dt><dd>{display_name(@workflow)}</dd><dt>Type</dt><dd>{available(@workflow["type"])}</dd><dt>Domain</dt><dd>{available(@workflow["domain"])}</dd><dt>Status</dt><dd>{available(@workflow["status"])}</dd><dt>Runtime</dt><dd class="mc-mono">{available(@workflow["target_runtime"] || @workflow["runtime"])}</dd><dt>Trigger</dt><dd>{available(@workflow["trigger"])}</dd></dl></.panel>
        <.panel title="Execution policy" description="Backend authorization remains authoritative."><p class="mc-callout">The click is recorded as the operator decision. Execution still passes action <span class="mc-mono">workflow.execute</span> through Policy, ApprovalStore, PrivacyGate, ExecutionService and Audit.</p><a class="mc-button" href={"/approvals?resource=#{@workflow["id"]}"}>Review approvals</a></.panel>
      </div>
      <.panel title="Configuration and dependencies"><div class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Registry field</th><th>Value</th></tr></thead><tbody><tr :for={{key, value} <- configuration(@workflow)}><td>{key}</td><td class="mc-mono">{format_value(value)}</td></tr></tbody></table></div></.panel>
      <.panel title="Recent real runs"><div :if={@runs != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Run</th><th>Status</th><th>Score</th><th>Actor</th><th>Queued</th><th>Evidence</th></tr></thead><tbody><tr :for={run <- @runs}><td><a href={"/runs/#{run.id}"}>{run.id}</a></td><td><.status_badge status={run.status} /></td><td>{available(run.score)}</td><td>{run.requested_by}</td><td>{time(run.queued_at)}</td><td>{available(run.evidence_ref)}</td></tr></tbody></table></div><p :if={@runs == []} class="mc-empty">No persisted execution exists for this workflow.</p></.panel>
      <.panel title="Audit events"><div :if={@audit != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Time</th><th>Actor</th><th>Action</th><th>Result</th><th>Evidence</th></tr></thead><tbody><tr :for={event <- @audit}><td>{event["timestamp"]}</td><td>{event["actor"]}</td><td>{event["action"]}</td><td><.status_badge status={event["result"]} /></td><td>{available(event["evidence_ref"])}</td></tr></tbody></table></div><p :if={@audit == []} class="mc-empty">No audit event currently references this workflow.</p></.panel>
    </.app_shell>
    """
  end

  defp refresh_after_run(socket, workflow_id, run, message) do
    {:ok, runs} = ShadowOpsApi.list_runs()
    {:ok, audit} = ShadowOpsApi.list_audit_events()

    socket =
      assign(socket,
        runs: Enum.filter(runs, &(&1.workflow_id == workflow_id)),
        audit: Enum.filter(audit, &(&1["resource"] == workflow_id)),
        last_run: run,
        one_click_ready: OneClick.available?(),
        updated_at: now()
      )

    {:noreply, put_flash(socket, :info, message)}
  end

  defp configuration(workflow), do: workflow |> Map.drop(["id"]) |> Enum.sort_by(&elem(&1, 0))

  defp display_name(w),
    do:
      w["display_name"] || w["name"] || w["id"] |> String.replace("_", " ") |> String.capitalize()

  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: Jason.encode!(value)
  defp available(nil), do: "Not available from current source"
  defp available(""), do: "Not available from current source"
  defp available(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp available(value), do: to_string(value)
  defp time(nil), do: "Not available from current source"
  defp time(%DateTime{} = time), do: DateTime.to_iso8601(time)
  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason({tag, _}) when is_atom(tag), do: Atom.to_string(tag)
  defp safe_reason(_), do: "execution_failed"
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
