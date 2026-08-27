defmodule ShadowOpsCore.WorkflowCurationTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.WorkflowCuration

  test "curation classifies records and groups conservative duplicate candidates" do
    registry = %{
      records: [
        record("localwf_a", "Career Sync", "auto_bewerbungen", "scripts/career_sync.py"),
        record("localwf_b", "Career Sync Copy", "Projects", "tools/career_sync_copy.py"),
        record("localwf_c", "Security Audit", "DokumentenSystem", "07_AUTOMATION/security-audit.sh")
      ]
    }

    snapshot = WorkflowCuration.snapshot(registry)

    assert snapshot.status == "AVAILABLE"
    assert snapshot.counts.found == 3
    assert snapshot.counts.unique == 2
    assert snapshot.counts.potential_duplicates == 1
    assert snapshot.counts.duplicate_groups == 1
    assert snapshot.counts.normalized == 3
    assert snapshot.counts.connected == 0
    assert snapshot.counts.tested == 0
    assert snapshot.counts.production_ready == 0

    career = Enum.find(snapshot.records, &(&1.id == "localwf_a"))
    security = Enum.find(snapshot.records, &(&1.id == "localwf_c"))

    assert career.category == "CAREER"
    assert career.lifecycle_status == "NORMALIZED"
    assert career.duplicate_candidate == true
    assert career.real_source_state == "DISCOVERED_REAL_ARTIFACT"

    assert security.category == "SECURITY"
    assert security.risk_level == "L0"
    assert security.duplicate_candidate == false
  end

  test "production readiness fails closed until runtime, test and governance evidence all exist" do
    base =
      record("localwf_runtime", "GitHub Sync", "actions-runner-host", ".github/workflows/sync.yml")

    normalized = WorkflowCuration.snapshot(%{records: [base]}).records |> hd()
    assert normalized.lifecycle_status == "NORMALIZED"
    refute normalized.production_ready

    connected =
      base
      |> Map.put(:runtime_verified, true)
      |> then(&WorkflowCuration.snapshot(%{records: [&1]}))
      |> Map.fetch!(:records)
      |> hd()

    assert connected.lifecycle_status == "CONNECTED"
    refute connected.production_ready

    tested =
      base
      |> Map.merge(%{runtime_verified: true, execution_tested: true})
      |> then(&WorkflowCuration.snapshot(%{records: [&1]}))
      |> Map.fetch!(:records)
      |> hd()

    assert tested.lifecycle_status == "TESTED"
    refute tested.production_ready

    ready =
      base
      |> Map.merge(%{
        runtime_verified: true,
        execution_tested: true,
        governance_mapped: true,
        executable: true
      })
      |> then(&WorkflowCuration.snapshot(%{records: [&1]}))
      |> Map.fetch!(:records)
      |> hd()

    assert ready.lifecycle_status == "PRODUCTION_READY"
    assert ready.production_ready
  end

  test "required systems are inferred without claiming connection" do
    github =
      record(
        "localwf_github",
        "GitHub Security Audit",
        "actions-runner-host",
        ".github/workflows/security-audit.yml",
        "GITHUB_ACTION"
      )

    row = WorkflowCuration.snapshot(%{records: [github]}).records |> hd()

    assert row.category == "SECURITY"
    assert "GitHub" in row.required_systems
    assert "GitHub Actions" in row.required_systems
    assert row.real_source_state == "DISCOVERED_REAL_ARTIFACT"
    assert row.lifecycle_status == "NORMALIZED"
  end

  defp record(id, name, source, source_ref, kind \\ "PYTHON_WORKFLOW") do
    %{
      id: id,
      name: name,
      source: source,
      source_ref: source_ref,
      kind: kind,
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
