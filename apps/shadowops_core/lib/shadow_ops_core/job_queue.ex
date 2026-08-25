defmodule ShadowOpsCore.JobQueue do
  @moduledoc "Read-only projection of Oban persistence for Mission Control."

  import Ecto.Query

  alias ShadowOpsCore.Repo

  @limit 100

  def snapshot do
    if Application.get_env(:shadowops_core, :start_persistence, false) do
      load_jobs()
    else
      %{
        id: "jobs",
        name: "Persistent jobs",
        kind: "oban_queue",
        status: "NOT_CONFIGURED",
        health: "UNAVAILABLE",
        availability: "UNAVAILABLE",
        source: "oban",
        source_type: "POSTGRES_OBAN",
        real_data: false,
        synthetic: false,
        enabled: false,
        reachable: false,
        records: [],
        record_count: nil,
        error_code: "PERSISTENCE_DISABLED",
        error_message: "Set SHADOWOPS_START_PERSISTENCE=true and migrate the database to enable Oban.",
        metadata: %{queues: ["default", "workflows", "agents"]}
      }
    end
  end

  defp load_jobs do
    jobs =
      Oban.Job
      |> order_by([j], desc: j.inserted_at)
      |> limit(@limit)
      |> Repo.all()
      |> Enum.map(&project/1)

    %{
      id: "jobs",
      name: "Persistent jobs",
      kind: "oban_queue",
      status: "READY",
      health: "HEALTHY",
      availability: "AVAILABLE",
      source: "oban",
      source_type: "POSTGRES_OBAN",
      real_data: true,
      synthetic: false,
      enabled: true,
      reachable: true,
      records: jobs,
      record_count: length(jobs),
      error_code: nil,
      error_message: nil,
      metadata: %{limit: @limit}
    }
  rescue
    error ->
      %{
        id: "jobs",
        name: "Persistent jobs",
        kind: "oban_queue",
        status: "ERROR",
        health: "ERROR",
        availability: "UNAVAILABLE",
        source: "oban",
        source_type: "POSTGRES_OBAN",
        real_data: false,
        synthetic: false,
        enabled: true,
        reachable: false,
        records: [],
        record_count: nil,
        error_code: "OBAN_READ_FAILED",
        error_message: Exception.message(error),
        metadata: %{}
      }
  end

  defp project(job) do
    %{
      id: job.id,
      queue: to_string(job.queue),
      worker: job.worker,
      state: to_string(job.state),
      attempt: job.attempt,
      max_attempts: job.max_attempts,
      inserted_at: job.inserted_at,
      scheduled_at: job.scheduled_at,
      attempted_at: job.attempted_at,
      completed_at: job.completed_at,
      discarded_at: job.discarded_at,
      tags: job.tags
    }
  end
end
