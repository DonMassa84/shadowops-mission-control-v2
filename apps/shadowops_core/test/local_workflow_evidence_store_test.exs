defmodule ShadowOpsCore.LocalWorkflowEvidenceStoreTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.{LocalWorkflowEvidenceStore, WorkflowCuration}

  setup do
    path = Path.join(System.tmp_dir!(), "shadowops-workflow-evidence-#{System.unique_integer([:positive])}.json")
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

    %{path: path, registry: registry()}
  end

  test "unknown workflow IDs and mismatched source refs are rejected", %{registry: registry} do
    assert {:error, :error} =
             LocalWorkflowEvidenceStore.put("localwf_missing", %{runtime_verified: true}, registry)

    assert {:error, :source_ref_mismatch} =
             LocalWorkflowEvidenceStore.put(
               "localwf_health",
               %{source_ref: "wrong/path.sh", runtime_verified: true},
               registry
             )
  end

  test "evidence defaults fail closed and unknown fields are rejected", %{registry: registry} do
    assert {:ok, evidence} = LocalWorkflowEvidenceStore.put("localwf_health", %{}, registry)

    refute evidence.runtime_verified
    refute evidence.real_data
    refute evidence.reachable
    refute evidence.execution_tested
    refute evidence.governance_mapped
    refute evidence.executable
    assert evidence.risk_level == "L3"
    assert evidence.approval_required

    assert {:error, :unknown_evidence_field} =
             LocalWorkflowEvidenceStore.put(
               "localwf_health",
               %{secret_token: "must-not-be-stored"},
               registry
             )
  end

  test "corrupt evidence storage fails closed", %{path: path, registry: registry} do
    File.write!(path, "not-json")
    assert LocalWorkflowEvidenceStore.snapshot(registry) == %{}
  end

  test "curation advances only when every lifecycle evidence gate is explicit", %{registry: registry} do
    assert lifecycle(registry, "localwf_health") == "NORMALIZED"

    assert {:ok, _} =
             LocalWorkflowEvidenceStore.put(
               "localwf_health",
               %{runtime_verified: true, real_data: true, reachable: true, risk_level: "L0"},
               registry
             )

    assert lifecycle(registry, "localwf_health") == "CONNECTED"

    assert {:ok, _} =
             LocalWorkflowEvidenceStore.put(
               "localwf_health",
               %{
                 runtime_verified: true,
                 real_data: true,
                 reachable: true,
                 execution_tested: true,
                 risk_level: "L0"
               },
               registry
             )

    assert lifecycle(registry, "localwf_health") == "TESTED"

    assert {:ok, _} =
             LocalWorkflowEvidenceStore.put(
               "localwf_health",
               %{
                 runtime_verified: true,
                 real_data: true,
                 reachable: true,
                 execution_tested: true,
                 governance_mapped: true,
                 executable: true,
                 adapter: "read_only_health",
                 capability: "node.status",
                 risk_level: "L0",
                 evidence_refs: ["runtime:4015/api/nodes"]
               },
               registry
             )

    row = WorkflowCuration.snapshot(registry).records |> Enum.find(&(&1.id == "localwf_health"))
    assert row.lifecycle_status == "PRODUCTION_READY"
    assert row.production_ready
    assert row.capability == "node.status"
    assert row.evidence_refs == ["runtime:4015/api/nodes"]
  end

  test "explicit evidence cannot lower an inferred high-risk workflow", %{registry: registry} do
    assert {:ok, _} =
             LocalWorkflowEvidenceStore.put(
               "localwf_deploy",
               %{
                 runtime_verified: true,
                 real_data: true,
                 reachable: true,
                 risk_level: "L0"
               },
               registry
             )

    row = WorkflowCuration.snapshot(registry).records |> Enum.find(&(&1.id == "localwf_deploy"))
    assert row.risk_level == "L3"
    assert row.approval_required
  end

  defp lifecycle(registry, id) do
    WorkflowCuration.snapshot(registry).records
    |> Enum.find(&(&1.id == id))
    |> Map.fetch!(:lifecycle_status)
  end

  defp registry do
    %{
      records: [
        record("localwf_health", "i7 Health Status", "Projects", "ops/i7-health.sh"),
        record("localwf_deploy", "Deploy Production", "Projects", "ops/deploy-production.sh")
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
end
