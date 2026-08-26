defmodule ShadowOpsCore.WorkflowJobsTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.{JobQueue, WorkflowJobs}

  setup do
    previous = Application.get_env(:shadowops_core, :start_persistence, false)
    Application.put_env(:shadowops_core, :start_persistence, false)
    on_exit(fn -> Application.put_env(:shadowops_core, :start_persistence, previous) end)
    :ok
  end

  test "persistent payload contract rejects private execution content" do
    assert WorkflowJobs.persistable?(%{"action" => "restart", "args" => ["safe"]})
    refute WorkflowJobs.persistable?(%{"prompt" => "private prompt"})
    refute WorkflowJobs.persistable?(%{"nested" => %{"token" => "secret"}})
    refute WorkflowJobs.persistable?(%{"message" => "private body"})
  end

  test "job projection is fail-visible when persistence is disabled" do
    snapshot = JobQueue.snapshot()

    assert snapshot.status == "NOT_CONFIGURED"
    assert snapshot.real_data == false
    assert snapshot.synthetic == false
    assert snapshot.reachable == false
    assert snapshot.records == []
    assert snapshot.record_count == nil
    assert snapshot.error_code == "PERSISTENCE_DISABLED"
  end
end
