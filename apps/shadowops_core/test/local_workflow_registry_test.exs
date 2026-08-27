defmodule ShadowOpsCore.LocalWorkflowRegistryTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.LocalWorkflowRegistry

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "shadowops_local_workflows_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "missing report remains not configured", %{root: root} do
    snapshot = LocalWorkflowRegistry.snapshot(root)

    assert snapshot.status == "NOT_CONFIGURED"
    assert snapshot.source_type == "LOCAL_WORKFLOW_CORRELATION"
    assert snapshot.counts.registered == 0
    assert snapshot.records == []
    assert snapshot.executable == false
  end

  test "correlation entrypoints are registered with stable IDs but never execution rights", %{
    root: root
  } do
    script = Path.join(root, "whatsapp-agent/run_sync.py")
    service = Path.join(root, "DokumentenSystem/07_AUTOMATION/demo/demo.service")
    test_file = Path.join(root, "Projects/example/test/demo_test.exs")

    for path <- [script, service, test_file] do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "fixture")
    end

    report = Path.join(root, "reports/shadowops/workflow_correlation_20260827_120000")
    File.mkdir_p!(report)

    File.write!(
      Path.join(report, "entrypoints.tsv"),
      Enum.join(
        [
          "SOURCE\tTYPE\tPATH",
          "whatsapp-agent\tPYTHON_WORKFLOW\t#{script}",
          "DokumentenSystem\tSYSTEMD_SERVICE\t#{service}",
          "Projects\tELIXIR_WORKFLOW\t#{test_file}"
        ],
        "\n"
      )
    )

    first = LocalWorkflowRegistry.snapshot(root)
    second = LocalWorkflowRegistry.snapshot(root)

    assert first.status == "DISCOVERED"
    assert first.counts.registered == 2
    assert first.counts.rejected == 1
    assert Enum.map(first.records, & &1.id) == Enum.map(second.records, & &1.id)

    assert Enum.all?(first.records, fn record ->
             String.starts_with?(record.id, "localwf_") and
               record.status == "DISCOVERED" and
               record.execution_status == "DISCOVERED" and
               record.executable == false and
               record.integration_mode == "REFERENCE_ONLY" and
               record.runtime_verified == false and
               record.governance_mapped == false and
               record.risk_level == "UNKNOWN" and
               not String.starts_with?(record.source_ref, "/")
           end)

    whatsapp = Enum.find(first.records, &(&1.source == "whatsapp-agent"))
    assert whatsapp.domain == "social"
    assert whatsapp.kind == "PYTHON_WORKFLOW"

    dokumente = Enum.find(first.records, &(&1.source == "DokumentenSystem"))
    assert dokumente.kind == "SYSTEMD_SERVICE"
  end

  test "paths outside the configured home and symlinks are rejected", %{root: root} do
    outside =
      Path.join(System.tmp_dir!(), "shadowops-outside-#{System.unique_integer([:positive])}.sh")

    File.write!(outside, "fixture")
    on_exit(fn -> File.rm(outside) end)

    target = Path.join(root, "whatsapp-agent/real.sh")
    link = Path.join(root, "whatsapp-agent/link.sh")
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, "fixture")
    File.ln_s!(target, link)

    report = Path.join(root, "reports/shadowops/workflow_correlation_20260827_130000")
    File.mkdir_p!(report)

    File.write!(
      Path.join(report, "entrypoints.tsv"),
      Enum.join(
        [
          "SOURCE\tTYPE\tPATH",
          "whatsapp-agent\tSHELL_WORKFLOW\t#{outside}",
          "whatsapp-agent\tSHELL_WORKFLOW\t#{link}"
        ],
        "\n"
      )
    )

    snapshot = LocalWorkflowRegistry.snapshot(root)

    assert snapshot.status == "NOT_CONFIGURED"
    assert snapshot.counts.registered == 0
    assert snapshot.counts.rejected == 2
  end

  test "virtual environments and dependency internals are rejected", %{root: root} do
    real = Path.join(root, "DokumentenSystem/07_AUTOMATION/real/run_sync.py")

    venv =
      Path.join(
        root,
        "DokumentenSystem/project/.venv/lib/python3.12/site-packages/httpx/_auth.py"
      )

    tests =
      Path.join(
        root,
        "DokumentenSystem/09_BOT_GATEWAY/tests/unit/test_config.py"
      )

    fixture =
      Path.join(
        root,
        "Projects/example/fixtures/demo.py"
      )

    for path <- [real, venv, tests, fixture] do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "fixture")
    end

    report =
      Path.join(
        root,
        "reports/shadowops/workflow_correlation_20260827_140000"
      )

    File.mkdir_p!(report)

    File.write!(
      Path.join(report, "entrypoints.tsv"),
      Enum.join(
        [
          "SOURCE\tTYPE\tPATH",
          "DokumentenSystem\tPYTHON_WORKFLOW\t#{real}",
          "DokumentenSystem\tPYTHON_WORKFLOW\t#{venv}",
          "DokumentenSystem\tPYTHON_WORKFLOW\t#{tests}",
          "Projects\tPYTHON_WORKFLOW\t#{fixture}"
        ],
        "\n"
      )
    )

    snapshot = LocalWorkflowRegistry.snapshot(root)

    assert snapshot.counts.registered == 1
    assert snapshot.counts.rejected == 3

    assert Enum.map(snapshot.records, & &1.source_ref) == [
             "DokumentenSystem/07_AUTOMATION/real/run_sync.py"
           ]
  end
end
