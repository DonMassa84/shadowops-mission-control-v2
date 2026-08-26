defmodule ShadowOpsCore.RuntimeSourcesEvidenceTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.RuntimeSources

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "shadowops-evidence-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)

    on_exit(fn ->
      File.rm_rf(root)
    end)

    %{root: root}
  end

  test "real local artifacts produce READY source truth without claiming verification",
       %{root: root} do
    File.write!(Path.join(root, "artifact.md"), "# evidence")

    snapshot = RuntimeSources.evidence_snapshot(root)

    assert snapshot.status == "READY"
    assert snapshot.health == "HEALTHY"
    assert snapshot.availability == "AVAILABLE"

    assert snapshot.real_data == true
    assert snapshot.synthetic == false
    assert snapshot.reachable == true

    assert snapshot.source_type == "LOCAL_FILESYSTEM"
    assert snapshot.record_count == 1

    assert [artifact] = snapshot.artifacts
    assert artifact.verification_status == "AVAILABLE"

    refute artifact.verification_status == "VERIFIED"
    assert snapshot.metadata.verified_claims_implied == false
  end

  test "empty but reachable evidence directory is DEGRADED", %{root: root} do
    snapshot = RuntimeSources.evidence_snapshot(root)

    assert snapshot.status == "DEGRADED"
    assert snapshot.health == "DEGRADED"
    assert snapshot.availability == "AVAILABLE"

    assert snapshot.real_data == false
    assert snapshot.synthetic == false
    assert snapshot.reachable == true
    assert snapshot.record_count == 0

    assert snapshot.error_code == "EVIDENCE_EMPTY"
  end

  test "missing evidence source remains fail-visible", %{root: root} do
    missing = Path.join(root, "does-not-exist")

    snapshot = RuntimeSources.evidence_snapshot(missing)

    assert snapshot.status == "UNAVAILABLE"
    assert snapshot.health == "UNAVAILABLE"
    assert snapshot.availability == "UNAVAILABLE"

    assert snapshot.real_data == false
    assert snapshot.synthetic == false
    assert snapshot.reachable == false

    assert snapshot.record_count == nil
    assert snapshot.artifacts == []
    assert snapshot.error_code == "SOURCE_MISSING"
  end
end
