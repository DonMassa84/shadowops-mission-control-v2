defmodule ShadowOpsCore.ApprovalSingleUseTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.{ApprovalStore, Audit, EventBus, GovernanceGate}

  setup do
    suffix = System.unique_integer([:positive])
    root = Path.join(System.tmp_dir!(), "shadowops-approval-single-use-#{suffix}")

    previous = %{
      approval: Application.get_env(:shadowops_core, :approval_path),
      audit: Application.get_env(:shadowops_core, :audit_path)
    }

    Application.put_env(:shadowops_core, :approval_path, Path.join(root, "approvals.jsonl"))
    Application.put_env(:shadowops_core, :audit_path, Path.join(root, "audit.jsonl"))
    :ok = EventBus.reset()

    on_exit(fn ->
      restore(:approval_path, previous.approval)
      restore(:audit_path, previous.audit)
      File.rm_rf(root)
    end)

    :ok
  end

  test "first consume persists terminal CONSUMED state and second consume is blocked" do
    approval = approved_approval()

    assert {:ok, consumed} =
             ApprovalStore.consume(
               approval.id,
               "workflow.execute",
               "repository_quality",
               "L2",
               "operator-a"
             )

    assert consumed.status == "CONSUMED"
    assert %DateTime{} = consumed.consumed_at
    assert consumed.consumed_by == "operator-a"

    assert {:ok, persisted} = ApprovalStore.get(approval.id)
    assert persisted.status == "CONSUMED"
    assert persisted.consumed_at == consumed.consumed_at
    assert persisted.consumed_by == "operator-a"

    assert {:blocked, {:approval_status, "CONSUMED"}} =
             ApprovalStore.consume(
               approval.id,
               "workflow.execute",
               "repository_quality",
               "L2",
               "operator-a"
             )
  end

  test "wrong action resource and risk never consume an approved record" do
    approval = approved_approval()

    assert {:blocked, :wrong_action} =
             ApprovalStore.consume(
               approval.id,
               "workflow.run",
               "repository_quality",
               "L2",
               "operator-a"
             )

    assert_approved(approval.id)

    assert {:blocked, :wrong_resource} =
             ApprovalStore.consume(
               approval.id,
               "workflow.execute",
               "different-resource",
               "L2",
               "operator-a"
             )

    assert_approved(approval.id)

    assert {:blocked, :wrong_risk} =
             ApprovalStore.consume(
               approval.id,
               "workflow.execute",
               "repository_quality",
               "L3",
               "operator-a"
             )

    assert_approved(approval.id)
  end

  test "expired and rejected approvals cannot be consumed" do
    assert {:ok, expired} =
             ApprovalStore.create(%{
               requested_by: "operator-a",
               action: "workflow.execute",
               resource: "repository_quality",
               reason: "expiry negative test",
               expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
             })

    assert {:blocked, :expired} =
             ApprovalStore.consume(
               expired.id,
               "workflow.execute",
               "repository_quality",
               "L2",
               "operator-a"
             )

    assert {:ok, %{status: "EXPIRED"}} = ApprovalStore.get(expired.id)

    assert {:ok, pending} =
             ApprovalStore.create(%{
               requested_by: "operator-a",
               action: "workflow.execute",
               resource: "rejected-resource",
               reason: "rejection negative test"
             })

    assert {:ok, rejected} = ApprovalStore.reject(pending.id, "reviewer-a")
    assert rejected.status == "REJECTED"

    assert {:blocked, {:approval_status, "REJECTED"}} =
             ApprovalStore.consume(
               rejected.id,
               "workflow.execute",
               "rejected-resource",
               "L2",
               "operator-a"
             )

    assert {:ok, %{status: "REJECTED", consumed_at: nil, consumed_by: nil}} =
             ApprovalStore.get(rejected.id)
  end

  test "PrivacyGate failure happens before consumption and a later safe request may consume" do
    approval = approved_approval()

    assert {:error, {:privacy_gate_blocked, _reason}} =
             GovernanceGate.authorize(
               "workflow.execute",
               "operator-a",
               "repository_quality",
               %{password: "synthetic-secret"},
               %{approval_id: approval.id}
             )

    assert_approved(approval.id)

    assert {:ok, authorization} =
             GovernanceGate.authorize(
               "workflow.execute",
               "operator-a",
               "repository_quality",
               %{payload: "safe metadata"},
               %{approval_id: approval.id}
             )

    assert authorization.approval_required
    assert authorization.risk_level == "L2"

    assert {:ok, %{status: "CONSUMED", consumed_by: "operator-a"}} =
             ApprovalStore.get(approval.id)

    assert {:error, {:approval_blocked, {:approval_status, "CONSUMED"}}} =
             GovernanceGate.authorize(
               "workflow.execute",
               "operator-a",
               "repository_quality",
               %{payload: "safe metadata"},
               %{approval_id: approval.id}
             )
  end

  test "two concurrent consumes produce exactly one winner" do
    approval = approved_approval()

    results =
      1..2
      |> Enum.map(fn number ->
        Task.async(fn ->
          ApprovalStore.consume(
            approval.id,
            "workflow.execute",
            "repository_quality",
            "L2",
            "operator-#{number}"
          )
        end)
      end)
      |> Enum.map(&Task.await(&1, 5_000))

    successes = Enum.count(results, &match?({:ok, %{status: "CONSUMED"}}, &1))

    blocked =
      Enum.count(
        results,
        &match?({:blocked, {:approval_status, "CONSUMED"}}, &1)
      )

    assert successes == 1
    assert blocked == 1
    assert {:ok, %{status: "CONSUMED"}} = ApprovalStore.get(approval.id)
  end

  test "consumption is represented in the audit chain and event bus" do
    approval = approved_approval()

    assert {:ok, consumed} =
             ApprovalStore.consume(
               approval.id,
               "workflow.execute",
               "repository_quality",
               "L2",
               "operator-a"
             )

    assert Enum.any?(Audit.list(100), fn row ->
             row["action"] == "approval_consumed" and
               get_in(row, ["metadata", "approval_id"]) == approval.id
           end)

    assert Enum.any?(EventBus.list(%{type: "approval.consumed"}), fn event ->
             event.resource_id == "approval:" <> approval.id and
               event.correlation_id == consumed.correlation_id
           end)

    assert {:ok, %{valid: true}} = Audit.verify()
  end

  defp approved_approval do
    assert {:ok, pending} =
             ApprovalStore.create(%{
               requested_by: "operator-a",
               action: "workflow.execute",
               resource: "repository_quality",
               reason: "single-use authorization test"
             })

    assert pending.risk == "L2"
    assert {:ok, approved} = ApprovalStore.approve(pending.id, "reviewer-a")
    assert approved.status == "APPROVED"
    approved
  end

  defp assert_approved(id) do
    assert {:ok, approval} = ApprovalStore.get(id)
    assert approval.status == "APPROVED"
    assert approval.consumed_at == nil
    assert approval.consumed_by == nil
  end

  defp restore(key, nil), do: Application.delete_env(:shadowops_core, key)
  defp restore(key, value), do: Application.put_env(:shadowops_core, key, value)
end
