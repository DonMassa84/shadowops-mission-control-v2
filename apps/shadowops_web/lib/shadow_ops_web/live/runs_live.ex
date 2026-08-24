defmodule ShadowOpsWeb.RunsLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi

  def mount(params, _session, socket) do
    {:ok, runs} = ShadowOpsApi.list_runs()
    run = if id = params["id"], do: Enum.find(runs, &(&1.id == id))
    {:ok, assign(socket, runs: runs, run: run, updated_at: now())}
  end

  def render(%{run: nil} = assigns) do
    ~H"""
    <.app_shell title="Runs" subtitle="Persisted workflow execution lifecycle" active="/runs" updated_at={@updated_at}>
      <.source_meta source="append-only run event store" updated_at={@updated_at} availability="READY" />
      <.panel title="Execution history" description="Only requests made through the real execution API appear here.">
        <div :if={@runs != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Run</th><th>Workflow</th><th>Status</th><th>Requested by</th><th>Queued</th><th>Started</th><th>Finished</th><th>Duration</th><th>Audit</th><th>Evidence</th></tr></thead><tbody><tr :for={run <- @runs}><td><a href={"/runs/#{run.id}"} class="mc-mono">{run.id}</a></td><td><a href={"/workflows/#{run.workflow_id}"}>{run.workflow_id}</a></td><td><.status_badge status={run.status} /></td><td>{run.requested_by}</td><td>{time(run.queued_at)}</td><td>{time(run.started_at)}</td><td>{time(run.finished_at)}</td><td>{duration(run)}</td><td class="mc-mono">{available(run.audit_ref)}</td><td>{available(run.evidence_ref)}</td></tr></tbody></table></div>
        <p :if={@runs == []} class="mc-empty">No real workflow execution has been requested.</p>
      </.panel>
    </.app_shell>
    """
  end

  def render(assigns) do
    ~H"""
    <.app_shell title={@run.id} subtitle="Run lifecycle detail" active={"/runs/#{@run.id}"} availability={@run.status} updated_at={@updated_at}>
      <div class="mc-detail-grid"><.panel title="Execution"><dl class="mc-dl"><dt>Workflow</dt><dd><a href={"/workflows/#{@run.workflow_id}"}>{@run.workflow_id}</a></dd><dt>Actor</dt><dd>{@run.requested_by}</dd><dt>Status</dt><dd><.status_badge status={@run.status} /></dd><dt>Result</dt><dd>{available(@run.result)}</dd><dt>Exit code</dt><dd>{available(@run.exit_code)}</dd></dl></.panel><.panel title="Governance"><dl class="mc-dl"><dt>Audit ref</dt><dd class="mc-mono">{available(@run.audit_ref)}</dd><dt>Evidence ref</dt><dd>{available(@run.evidence_ref)}</dd><dt>Logs</dt><dd>Not available from current source</dd></dl></.panel></div>
      <.panel title="Lifecycle timeline"><ol class="mc-timeline"><li><strong>QUEUED</strong><br/><span class="mc-muted">{time(@run.queued_at)}</span></li><li :if={@run.started_at}><strong>RUNNING</strong><br/><span class="mc-muted">{time(@run.started_at)}</span></li><li :if={@run.finished_at}><strong>{@run.status}</strong><br/><span class="mc-muted">{time(@run.finished_at)}</span></li></ol></.panel>
    </.app_shell>
    """
  end

  defp duration(%{started_at: %DateTime{} = start, finished_at: %DateTime{} = finish}),
    do: "#{DateTime.diff(finish, start, :second)}s"

  defp duration(_), do: "Not available"
  defp time(nil), do: "Not available"
  defp time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp available(nil), do: "Not available from current source"
  defp available(value), do: to_string(value)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
