defmodule ShadowOpsCore.GovernanceBaselineRecoveryTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.{
    Approval,
    CapabilityRegistry,
    GovernanceGate,
    LocalWorkflowEvidenceStore,
    RiskPolicy,
    WorkflowCuration
  }

  # ---------------------------------------------------------------------------
  # 2. PDF governance capability must be consistently known in both registries
  # ---------------------------------------------------------------------------

  test "PDF_GOVERNANCE_READ_CAPABILITY_KNOWN" do
    assert {:ok, spec} = CapabilityRegistry.lookup("pdf_governance.read")
    assert spec.id == "pdf_governance.read"
    # Runtime execution is not proven, so registration must not claim a live adapter.
    assert spec.executor == :not_connected
  end

  test "PDF_GOVERNANCE_READ_RISK_L0" do
    assert RiskPolicy.infer_risk("pdf_governance.read") == "L0"

    assert {:ok, policy} = RiskPolicy.get("L0")
    assert policy.effect_scope == :read_only
    refute policy.approval_required
    assert policy.automatic_execution
  end

  # ---------------------------------------------------------------------------
  # 3. Unknown local workflow must fail closed with a specific error
  # ---------------------------------------------------------------------------

  test "UNKNOWN_LOCAL_WORKFLOW_RETURNS_UNKNOWN_WORKFLOW_ID" do
    registry = evidence_registry()

    assert {:error, :unknown_workflow_id} =
             LocalWorkflowEvidenceStore.put(
               "localwf_missing",
               %{runtime_verified: true},
               registry
             )

    assert {:error, :unknown_workflow_id} =
             LocalWorkflowEvidenceStore.get("localwf_missing", registry)
  end

  # ---------------------------------------------------------------------------
  # 4 + 5. Effective risk is max(inferred, explicit); evidence cannot lower it
  # ---------------------------------------------------------------------------

  test "EXPLICIT_L0_CANNOT_LOWER_INFERRED_L3" do
    registry = evidence_registry()

    assert {:ok, _} =
             LocalWorkflowEvidenceStore.put(
               "localwf_deploy",
               %{runtime_verified: true, real_data: true, reachable: true, risk_level: "L0"},
               registry
             )

    row = curated(registry, "localwf_deploy")
    assert row.risk_level == "L3"
    assert row.approval_required
  end

  test "EXPLICIT_L1_CANNOT_LOWER_INFERRED_L2_OR_L3" do
    registry = evidence_registry()

    # inferred L2 (backup) must not be lowered to L1
    assert {:ok, _} =
             LocalWorkflowEvidenceStore.put(
               "localwf_backup",
               %{runtime_verified: true, real_data: true, reachable: true, risk_level: "L1"},
               registry
             )

    row_l2 = curated(registry, "localwf_backup")
    assert row_l2.risk_level == "L2"
    assert row_l2.approval_required

    # inferred L3 (deploy) must not be lowered to L1
    assert {:ok, _} =
             LocalWorkflowEvidenceStore.put(
               "localwf_deploy",
               %{runtime_verified: true, real_data: true, reachable: true, risk_level: "L1"},
               registry
             )

    row_l3 = curated(registry, "localwf_deploy")
    assert row_l3.risk_level == "L3"
    assert row_l3.approval_required
  end

  # ---------------------------------------------------------------------------
  # 5. Approval must follow the final effective risk
  # ---------------------------------------------------------------------------

  test "FINAL_L2_REQUIRES_APPROVAL" do
    registry = evidence_registry()

    assert {:ok, _} =
             LocalWorkflowEvidenceStore.put(
               "localwf_backup",
               %{runtime_verified: true, real_data: true, reachable: true, risk_level: "L0"},
               registry
             )

    row = curated(registry, "localwf_backup")
    assert row.risk_level == "L2"
    assert row.approval_required
  end

  test "FINAL_L3_REQUIRES_APPROVAL" do
    registry = evidence_registry()

    assert {:ok, _} =
             LocalWorkflowEvidenceStore.put(
               "localwf_deploy",
               %{runtime_verified: true, real_data: true, reachable: true, risk_level: "L0"},
               registry
             )

    row = curated(registry, "localwf_deploy")
    assert row.risk_level == "L3"
    assert row.approval_required
  end

  test "EVIDENCE_FALSE_APPROVAL_CANNOT_BYPASS_HIGH_RISK" do
    registry = evidence_registry()

    # Low evidence risk makes the store-derived approval_required false, but the
    # inferred high risk must still force approval in the governed record.
    assert {:ok, _} =
             LocalWorkflowEvidenceStore.put(
               "localwf_deploy",
               %{runtime_verified: true, real_data: true, reachable: true, risk_level: "L0"},
               registry
             )

    row = curated(registry, "localwf_deploy")
    assert row.risk_level == "L3"
    refute row.risk_level in ~w(L0 L1)
    assert row.approval_required
  end

  # ---------------------------------------------------------------------------
  # 6. High-risk executable requires real, single-use, matched approval evidence
  # ---------------------------------------------------------------------------

  test "HIGH_RISK_EXECUTABLE_REQUIRES_APPROVAL_EVIDENCE" do
    actor = "operator"
    resource = "localwf_x"
    action = "local_workflow.enable_execution"
    risk = "L2"

    # No approval supplied -> blocked (fail closed)
    assert {:error, :approval_required} =
             GovernanceGate.authorize(action, actor, resource, %{}, %{})

    {:ok, approval} =
      Approval.new(%{
        requested_by: actor,
        action: action,
        resource: resource,
        risk: risk,
        reason: "baseline recovery test"
      })

    {:ok, approved} = Approval.decide(approval, "APPROVED", actor)

    # Matching approval -> allowed
    assert :allowed = Approval.evaluate(approved, action, resource, risk)

    # Wrong resource rejected
    assert {:blocked, :wrong_resource} =
             Approval.evaluate(approved, action, "other_resource", risk)

    # Wrong workflow/action rejected
    assert {:blocked, :wrong_action} =
             Approval.evaluate(approved, "local_workflow.map_governance", resource, risk)

    # Mismatched risk rejected
    assert {:blocked, :wrong_risk} =
             Approval.evaluate(approved, action, resource, "L3")

    # Single-use: consuming blocks reuse
    {:ok, consumed} = Approval.consume(approved, actor)

    assert {:blocked, {:approval_status, "CONSUMED"}} =
             Approval.evaluate(consumed, action, resource, risk)
  end

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp curated(registry, id) do
    WorkflowCuration.snapshot(registry).records
    |> Enum.find(&(&1.id == id))
  end

  defp evidence_registry do
    %{
      records: [
        record("localwf_health", "i7 Health Status", "Projects", "ops/i7-health.sh"),
        record("localwf_deploy", "Deploy Production", "Projects", "ops/deploy-production.sh"),
        record("localwf_backup", "Backup Data", "Projects", "ops/backup-data.sh")
      ]
    }
  end

  defp record(id, name, source, source_ref) do
    %{
      id: id,
      name: name,
      source: source,
      source_ref: source_ref,
      kind: "SHELL_WORKFLOW",
      domain: "system",
      real_data: true,
      reachable: true,
      runtime_verified: false,
      governance_mapped: false,
      executable: false,
      integration_mode: "REFERENCE_ONLY"
    }
  end

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "shadowops-baseline-recovery-#{System.unique_integer([:positive])}.json"
      )

    previous = Application.get_env(:shadowops_core, :local_workflow_evidence_path)
    Application.put_env(:shadowops_core, :local_workflow_evidence_path, path)

    on_exit(fn ->
      File.rm(path)

      if previous do
        Application.put_env(:shadowops_core, :local_workflow_evidence_path, previous)
      else
        Application.delete_env(:shadowops_core, :local_workflow_evidence_path)
      end
    end)

    :ok
  end
end
