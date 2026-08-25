defmodule ShadowOpsWeb.JobsLive do
  use Phoenix.LiveView

  import ShadowOpsWeb.MissionControlComponents

  alias ShadowOpsCore.JobQueue

  @impl true
  def mount(_params, _session, socket) do
    data = JobQueue.snapshot()

    {:ok,
     assign(socket,
       data: data,
       jobs: data.records,
       updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app_shell
      title="Persistent jobs"
      subtitle="Oban-backed workflow scheduling, retry and recovery"
      active="/jobs"
      availability={@data.status}
      updated_at={@updated_at}
    >
      <.source_meta source={@data.source} updated_at={@updated_at} availability={@data.status} />

      <div class="mc-grid">
        <.metric_card
          label="Persistence"
          value={@data.status}
          status={@data.status}
          note="Explicitly enabled with SHADOWOPS_START_PERSISTENCE"
        />
        <.metric_card
          label="Visible jobs"
          value={if(is_integer(@data.record_count), do: @data.record_count, else: "—")}
          status={@data.status}
          note="Arguments and private payloads are never rendered"
        />
      </div>

      <.panel
        title="Oban queue"
        description="Durable jobs. Run lifecycle remains visible under Runs; governance is revalidated when a job executes."
      >
        <div :if={@jobs != []} class="mc-table-wrap">
          <table class="mc-table">
            <thead><tr><th>Job</th><th>Queue</th><th>Worker</th><th>State</th><th>Attempt</th><th>Inserted</th><th>Completed</th></tr></thead>
            <tbody>
              <tr :for={job <- @jobs}>
                <td class="mc-mono">{job.id}</td>
                <td>{job.queue}</td>
                <td class="mc-mono">{job.worker}</td>
                <td><.status_badge status={String.upcase(job.state)} /></td>
                <td>{job.attempt}/{job.max_attempts}</td>
                <td>{time(job.inserted_at)}</td>
                <td>{time(job.completed_at)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <p :if={@jobs == []} class="mc-empty">
          {@data.error_message || "No persistent jobs have been queued."}
        </p>
      </.panel>
    </.app_shell>
    """
  end

  defp time(nil), do: "Not available"
  defp time(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp time(value), do: to_string(value)
end
