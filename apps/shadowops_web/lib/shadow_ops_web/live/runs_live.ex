defmodule ShadowOpsWeb.RunsLive do
  use Phoenix.LiveView
  import ShadowOpsWeb.MissionControlComponents
  alias ShadowOpsApi
  alias ShadowOpsCore.ResultEvaluator

  def mount(params, _session, socket) do
    {:ok, runs} = ShadowOpsApi.list_runs()
    run = if id = params["id"], do: Enum.find(runs, &(&1.id == id))
    {:ok, assign(socket, runs: runs, run: run, updated_at: now())}
  end

  def render(%{run: nil} = assigns) do
    ~H"""
    <.app_shell title="Runs" subtitle="Workflow and service execution lifecycle" active="/runs" updated_at={@updated_at}>
      <.source_meta source="append-only run event store" updated_at={@updated_at} availability="READY" />
      <.panel title="Execution history" description="Only requests made through governed ShadowOps execution paths appear here.">
        <div :if={@runs != []} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Run</th><th>Kind</th><th>Resource</th><th>Action</th><th>Status</th><th>Score</th><th>Requested by</th><th>Duration</th><th>Evidence</th></tr></thead><tbody><tr :for={run <- @runs}><td><a href={"/runs/#{run.id}"} class="mc-mono">{run.id}</a></td><td>{run_kind(run)}</td><td>{resource_link(run)}</td><td>{run.action || "run"}</td><td><.status_badge status={run.status} /></td><td>{score(run)}</td><td>{run.requested_by}</td><td>{duration(run)}</td><td>{available(run.evidence_ref)}</td></tr></tbody></table></div>
        <p :if={@runs == []} class="mc-empty">No real execution has been requested.</p>
      </.panel>
    </.app_shell>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, :evaluation, evaluation(assigns.run))

    ~H"""
    <.app_shell title={@run.id} subtitle="Execution lifecycle and deterministic evaluation" active={"/runs/#{@run.id}"} availability={@run.status} updated_at={@updated_at}>
      <section class="mc-grid" aria-label="Execution evaluation metrics">
        <.metric_card label="Status" value={@run.status} status={@run.status} source="run store" />
        <.metric_card label="Score" value={if(@evaluation, do: "#{@evaluation.score}/100", else: "—")} status={if(@evaluation, do: @evaluation.verdict, else: "NOT_ASSESSED")} source="deterministic evaluator" />
        <.metric_card label="Duration" value={duration(@run)} status="AVAILABLE" source="run timestamps" />
        <.metric_card label="Kind" value={run_kind(@run)} status="AVAILABLE" source="execution record" />
      </section>

      <div class="mc-detail-grid">
        <.panel title="Execution"><dl class="mc-dl"><dt>Resource</dt><dd>{resource_link(@run)}</dd><dt>Action</dt><dd>{@run.action || "run"}</dd><dt>Actor</dt><dd>{@run.requested_by}</dd><dt>Status</dt><dd><.status_badge status={@run.status} /></dd><dt>Result</dt><dd>{available(@run.result)}</dd><dt>Exit code</dt><dd>{available(@run.exit_code)}</dd></dl></.panel>
        <.panel title="Governance & evidence"><dl class="mc-dl"><dt>Audit ref</dt><dd class="mc-mono">{available(@run.audit_ref)}</dd><dt>Correlation</dt><dd class="mc-mono">{available(@run.correlation_id)}</dd><dt>Evidence ref</dt><dd>{available(@run.evidence_ref)}</dd><dt>Logs</dt><dd>{log_refs(@run)}</dd></dl></.panel>
      </div>

      <.panel title="Deterministic result evaluation" description="AI may summarize these results later, but it cannot override technical checks.">
        <div :if={@evaluation} class="mc-table-wrap"><table class="mc-table"><thead><tr><th>Check</th><th>Status</th><th>Detail</th></tr></thead><tbody><tr :for={check <- @evaluation.checks}><td class="mc-mono">{check.id}</td><td><.status_badge status={check.status} /></td><td>{check.detail}</td></tr></tbody></table></div>
        <p :if={@evaluation} class="mc-callout"><strong>{@evaluation.verdict} · {@evaluation.score}/100</strong> — {@evaluation.summary}</p>
        <p :if={!@evaluation} class="mc-empty">This execution is not finished yet; evaluation will be available after completion.</p>
      </.panel>

      <div :if={run_kind(@run) == "service"} class="mc-detail-grid">
        <.panel title="Before state"><pre class="mc-mono">{pretty(@run.before_state)}</pre></.panel>
        <.panel title="After state"><pre class="mc-mono">{pretty(@run.after_state)}</pre></.panel>
      </div>

      <.panel title="Lifecycle timeline"><ol class="mc-timeline"><li><strong>QUEUED</strong><br/><span class="mc-muted">{time(@run.queued_at)}</span></li><li :if={@run.started_at}><strong>RUNNING</strong><br/><span class="mc-muted">{time(@run.started_at)}</span></li><li :if={@run.finished_at}><strong>{@run.status}</strong><br/><span class="mc-muted">{time(@run.finished_at)}</span></li></ol></.panel>
    </.app_shell>
    """
  end

  defp evaluation(%{evaluation: evaluation}) when is_map(evaluation) do
    %{
      kind: value(evaluation, :kind),
      verdict: value(evaluation, :verdict),
      score: value(evaluation, :score),
      checks:
        Enum.map(value(evaluation, :checks) || [], fn check ->
          %{id: value(check, :id), status: value(check, :status), detail: value(check, :detail)}
        end),
      summary: value(evaluation, :summary)
    }
  end

  defp evaluation(%{status: status}) when status in ["SUCCESS", "FAILED"] do
    # Backward-compatible assessment for historical workflow runs that predate stored evaluation.
    ResultEvaluator.workflow(status, if(status == "SUCCESS", do: 0, else: 1))
  end

  defp evaluation(_), do: nil

  defp run_kind(run), do: run.kind || if(run.workflow_id, do: "workflow", else: "execution")

  defp resource_link(run) do
    cond do
      run_kind(run) == "workflow" and run.workflow_id -> run.workflow_id
      run.resource_id -> run.resource_id
      true -> "Not available"
    end
  end

  defp score(run) do
    case evaluation(run) do
      %{score: score} -> "#{score}/100"
      _ -> "—"
    end
  end

  defp duration(%{duration_ms: ms}) when is_integer(ms), do: "#{ms}ms"

  defp duration(%{started_at: %DateTime{} = start, finished_at: %DateTime{} = finish}),
    do: "#{DateTime.diff(finish, start, :second)}s"

  defp duration(_), do: "Not available"
  defp time(nil), do: "Not available"
  defp time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp available(nil), do: "Not available from current source"
  defp available(value) when is_map(value) or is_list(value), do: Jason.encode!(value)
  defp available(value), do: to_string(value)
  defp pretty(nil), do: "Not available from current source"
  defp pretty(value), do: Jason.encode!(value, pretty: true)

  defp log_refs(run) do
    [run.stdout_ref, run.stderr_ref]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "Not available from current source"
      refs -> Enum.join(refs, " · ")
    end
  end

  defp value(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
