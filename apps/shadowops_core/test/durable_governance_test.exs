defmodule ShadowOpsCore.DurableGovernanceTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.{ApprovalStore, Audit, ResultEvaluator, RunStore}

  setup do
    suffix = System.unique_integer([:positive])
    root = Path.join(System.tmp_dir!(), "shadowops-governance-#{suffix}")

    previous = %{
      approval: Application.get_env(:shadowops_core, :approval_path),
      run: Application.get_env(:shadowops_core, :run_path),
      audit: Application.get_env(:shadowops_core, :audit_path)
    }

    Application.put_env(:shadowops_core, :approval_path, Path.join(root, "approvals.jsonl"))
    Application.put_env(:shadowops_core, :run_path, Path.join(root, "runs.jsonl"))
    Application.put_env(:shadowops_core, :audit_path, Path.join(root, "audit.jsonl"))

    on_exit(fn ->
      restore(:approval_path, previous.approval)
      restore(:run_path, previous.run)
      restore(:audit_path, previous.audit)
      File.rm_rf(root)
    end)

    :ok
  end

  test "approval creation, decisions, expiry, persistence, audit linkage and legal transitions" do
    attrs = %{
      requested_by: "operator-a",
      action: "workflow.execute",
      resource: "repository_quality",
      reason: "verified deployment"
    }

    assert {:ok, pending} = ApprovalStore.create(attrs)
    assert pending.status == "PENDING"
    assert is_binary(pending.audit_ref)
    assert {:ok, persisted} = ApprovalStore.get(pending.id)
    assert persisted.id == pending.id

    assert {:ok, approved} = ApprovalStore.approve(pending.id, "reviewer-a")
    assert approved.status == "APPROVED"
    assert approved.decided_by == "reviewer-a"

    assert {:error, {:invalid_transition, "APPROVED"}} =
             ApprovalStore.reject(pending.id, "reviewer-b")

    assert {:ok, rejected_pending} =
             ApprovalStore.create(Map.put(attrs, :resource, "finance_quality_gate"))

    assert {:ok, rejected} = ApprovalStore.reject(rejected_pending.id, "reviewer-b")
    assert rejected.status == "REJECTED"

    assert {:ok, expired} =
             ApprovalStore.create(
               Map.put(attrs, :expires_at, DateTime.add(DateTime.utc_now(), -1, :second))
             )

    assert {:ok, %{status: "EXPIRED"}} = ApprovalStore.get(expired.id)

    assert {:error, {:invalid_transition, "EXPIRED"}} =
             ApprovalStore.approve(expired.id, "reviewer-a")

    assert match?({:ok, %{valid: true}}, Audit.verify())
  end

  test "run lifecycle validates workflow, persists every state and links audit" do
    assert {:error, :invalid_workflow_or_actor} = RunStore.queue("not-registered", "operator-a")

    assert {:ok, queued} = RunStore.queue("repository_quality", "operator-a")
    assert queued.status == "QUEUED" and is_binary(queued.audit_ref)
    assert queued.kind == "workflow"
    assert queued.resource_id == "repository_quality"
    assert {:ok, running} = RunStore.start(queued.id, "operator-a")
    assert running.status == "RUNNING"

    evaluation = ResultEvaluator.workflow("verified result", 0)

    assert {:ok, success} =
             RunStore.succeed(running.id, "operator-a", "verified result", 0, "evidence-a", %{
               evaluation: evaluation,
               score: evaluation.score
             })

    assert success.status == "SUCCESS" and success.evidence_ref == "evidence-a"
    assert success.score == 100

    assert {:error, {:invalid_transition, "SUCCESS", "RUNNING"}} =
             RunStore.start(success.id, "operator-a")

    assert {:ok, persisted} = RunStore.get(success.id)
    assert persisted.result == "verified result"

    assert {:ok, failure} = RunStore.queue("finance_quality_gate", "operator-b")
    assert {:ok, failure} = RunStore.start(failure.id, "operator-b")
    assert {:ok, failure} = RunStore.fail(failure.id, "operator-b", "non-zero exit", 2)
    assert failure.status == "FAILED"

    assert {:ok, blocked} = RunStore.queue("document_ai", "operator-c")
    assert {:ok, blocked} = RunStore.block(blocked.id, "operator-c", "approval required")
    assert blocked.status == "BLOCKED"
    assert match?({:ok, %{valid: true}}, Audit.verify())
  end

  test "service run persists before and after state with deterministic evaluation" do
    before_state = %{active_state: "inactive", pid: nil}
    after_state = %{active_state: "active", pid: 777}
    evaluation = ResultEvaluator.service("start", before_state, after_state, :ok)

    assert {:ok, queued} =
             RunStore.queue_service(
               "user:shadowops-phoenix.service",
               "start",
               "operator-service",
               %{
                 before_state: before_state,
                 trigger: "test"
               }
             )

    assert queued.kind == "service"
    assert queued.workflow_id == nil
    assert queued.resource_id == "user:shadowops-phoenix.service"
    assert queued.action == "start"

    assert {:ok, running} = RunStore.start(queued.id, "operator-service")

    assert {:ok, success} =
             RunStore.succeed(
               running.id,
               "operator-service",
               "service started",
               0,
               "service:test",
               %{
                 after_state: after_state,
                 evaluation: evaluation,
                 score: evaluation.score
               }
             )

    assert success.status == "SUCCESS"
    assert nested_value(success.before_state, :active_state) == "inactive"
    assert nested_value(success.after_state, :active_state) == "active"
    assert nested_value(success.after_state, :pid) == 777
    assert success.score == 100
    assert nested_value(success.evaluation, :verdict) == "EXCELLENT"
    assert is_integer(success.duration_ms)

    assert {:ok, persisted} = RunStore.get(success.id)
    assert persisted.kind == "service"
    assert persisted.resource_id == "user:shadowops-phoenix.service"
    assert nested_value(persisted.before_state, :active_state) == "inactive"
    assert nested_value(persisted.after_state, :active_state) == "active"
    assert nested_value(persisted.evaluation, :verdict) == "EXCELLENT"
    assert match?({:ok, %{valid: true}}, Audit.verify())
  end

  test "concurrent audit appends preserve a single valid hash chain" do
    1..20
    |> Task.async_stream(
      fn number ->
        Audit.record(:requested, "operator-#{number}", "concurrency-check", :success)
      end,
      max_concurrency: 8,
      ordered: false
    )
    |> Enum.each(fn {:ok, result} -> assert match?({:ok, _}, result) end)

    assert {:ok, %{valid: true, entries: 20}} = Audit.verify()
  end

  defp nested_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp restore(key, nil), do: Application.delete_env(:shadowops_core, key)
  defp restore(key, value), do: Application.put_env(:shadowops_core, key, value)
end
