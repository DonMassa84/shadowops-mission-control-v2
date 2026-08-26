alias ShadowOpsCore.{JobQueue, Repo, WorkflowJobs}
alias ShadowOpsCore.Workers.WorkflowRunWorker

assert! = fn condition, message ->
  unless condition, do: raise(message)
end

assert!.((Application.get_env(:shadowops_core, :start_persistence, false) == true), "persistence is not enabled")
assert!.(WorkflowJobs.enabled?(), "WorkflowJobs persistence boundary is disabled")

%Postgrex.Result{rows: [["oban_jobs"]]} =
  Ecto.Adapters.SQL.query!(Repo, "SELECT to_regclass('public.oban_jobs')::text", [])

probe_id = System.unique_integer([:positive, :monotonic])
run_id = "run_persistence_probe_#{probe_id}"

args = %{
  "run_id" => run_id,
  "workflow_id" => "persistence_probe",
  "actor" => "ci",
  "input" => %{"evidence_ref" => "ci:postgres-oban-e2e"},
  "approval_id" => "approval_persistence_probe"
}

scheduled_at = DateTime.add(DateTime.utc_now(), 600, :second)

changeset =
  WorkflowRunWorker.new(args,
    queue: :workflows,
    scheduled_at: scheduled_at,
    tags: ["persistence-e2e"]
  )

{:ok, inserted} = Oban.insert(changeset)
persisted = Repo.get!(Oban.Job, inserted.id)

assert!.(persisted.worker == inspect(WorkflowRunWorker), "unexpected persisted worker")
assert!.(to_string(persisted.queue) == "workflows", "unexpected persisted queue")
assert!.(persisted.args["run_id"] == run_id, "persisted job args do not match probe")
assert!.(to_string(persisted.state) == "scheduled", "probe job executed unexpectedly")

snapshot = JobQueue.snapshot()
projected = Enum.find(snapshot.records, &(&1.id == inserted.id))

assert!.(snapshot.status == "READY", "job projection is not READY")
assert!.(snapshot.real_data == true, "job projection is not marked as real data")
assert!.(snapshot.reachable == true, "job projection is not reachable")
assert!.(is_map(projected), "inserted job is missing from JobQueue projection")
assert!.(not Map.has_key?(projected, :args), "JobQueue projection exposed Oban args")
assert!.(not Map.has_key?(projected, "args"), "JobQueue projection exposed Oban args")

assert!.(WorkflowJobs.persistable?(%{"evidence_ref" => "safe"}), "safe metadata was rejected")
assert!.(not WorkflowJobs.persistable?(%{"token" => "must-not-persist"}), "token payload was accepted")
assert!.(not WorkflowJobs.persistable?(%{"nested" => %{"password" => "must-not-persist"}}), "nested password payload was accepted")

IO.puts("POSTGRES=PASS")
IO.puts("MIGRATION=PASS")
IO.puts("PERSISTENCE_ENABLED=PASS")
IO.puts("OBAN_INSERT=PASS")
IO.puts("OBAN_READ=PASS")
IO.puts("OBAN_SCHEDULED_NO_EXECUTION=PASS")
IO.puts("JOB_PROJECTION_PRIVACY=PASS")
IO.puts("SENSITIVE_PAYLOAD_GATE=PASS")
IO.puts("FINAL_STATUS=OBAN_PERSISTENCE_E2E_PASS")
