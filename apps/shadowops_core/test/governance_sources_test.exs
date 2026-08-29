defmodule ShadowOpsCore.GovernanceSourcesTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.OperationalSources

  # --- PDF governance ---

  test "PDF complete evidence is READY" do
    root = pdf_root()
    result = OperationalSources.pdf_governance_at(root, root)
    assert result.status == "READY"
    assert result.real_data
    refute result.synthetic
    assert result.reachable
    assert result.record_count > 0
    assert result.artifact_count == 5
    assert result.artifacts_missing == []
  end

  test "PDF missing artifact is DEGRADED" do
    root = pdf_root()
    File.rm!(Path.join(root, "reports/pdf_governance/PDF_GOVERNANCE_REPORT.md"))
    result = OperationalSources.pdf_governance_at(root, root)
    assert result.status == "DEGRADED"
    assert result.artifacts_missing != []
    refute result.artifact_count == 5
  end

  test "PDF malformed status JSON is DEGRADED" do
    root = pdf_root()
    File.write!(Path.join(root, "data/workflow_status/pdf_governance_status.json"), "{not valid")
    result = OperationalSources.pdf_governance_at(root, root)
    assert result.status == "DEGRADED"
    refute result.real_data
  end

  test "PDF synthetic evidence never becomes READY" do
    root = pdf_root()
    write_pdf_status(root, true)
    result = OperationalSources.pdf_governance_at(root, root)
    assert result.status != "READY"
    assert result.synthetic
  end

  test "PDF connector output carries no raw PDF content" do
    root = pdf_root()
    File.write!(Path.join(root, "data/pdf_governance/pdf_inventory.jsonl"), "")
    result = OperationalSources.pdf_governance_at(root, root)
    output = inspect(result)
    refute output =~ "PDFMAGIC"
    refute output =~ "%PDF"
  end

  # --- Repo governance ---

  test "Repo complete evidence is READY" do
    root = repo_root()
    result = OperationalSources.repo_governance_at(root, root)
    assert result.status == "READY"
    assert result.real_data
    refute result.synthetic
    assert result.reachable
    assert result.priority_check == "PASS"
    assert result.artifact_count == 6
    assert result.same_dataset
  end

  test "Repo counter mismatch is DEGRADED" do
    root = repo_root()
    write_repo_status(root, %{"total" => 100, "P0" => 10, "P1" => 90, "P2" => 0, "P3" => 0})
    result = OperationalSources.repo_governance_at(root, root)
    assert result.status == "DEGRADED"
    assert result.priority_check == "FAIL"
  end

  test "Repo missing artifact is DEGRADED" do
    root = repo_root()
    File.rm!(Path.join(root, "reports/discord_documentation/GITHUB_REPO_CANONICAL_INDEX.md"))
    result = OperationalSources.repo_governance_at(root, root)
    assert result.status == "DEGRADED"
    assert result.artifacts_missing != []
  end

  test "Repo malformed status JSON is DEGRADED" do
    root = repo_root()
    File.write!(Path.join(root, "data/workflow_status/repo_governance_status.json"), "nope")
    result = OperationalSources.repo_governance_at(root, root)
    assert result.status == "DEGRADED"
  end

  test "Repo synthetic evidence never becomes READY" do
    root = repo_root()

    write_repo_status(
      root,
      %{"total" => 130, "P0" => 18, "P1" => 38, "P2" => 46, "P3" => 28},
      true
    )

    result = OperationalSources.repo_governance_at(root, root)
    assert result.status != "READY"
    assert result.synthetic
  end

  test "Repo governance has repository mutation disabled" do
    root = repo_root()
    result = OperationalSources.repo_governance_at(root, root)
    assert result.deletion_allowed == false
    assert result.mutation_allowed == false
  end

  test "Repo governance has Discord and Telegram writes disabled" do
    root = repo_root()
    result = OperationalSources.repo_governance_at(root, root)
    assert result.discord_write_enabled == false
    assert result.telegram_write_enabled == false
  end

  test "Discord failure does not make local read source unavailable" do
    # Both sources are local reads; they must stay READY even if a Discord
    # publishing channel is unavailable. Our sources never depend on Discord.
    pdf = OperationalSources.pdf_governance_at(pdf_root(), pdf_root())
    repo_root = repo_root()
    repo = OperationalSources.repo_governance_at(repo_root, repo_root)
    assert pdf.status == "READY"
    assert repo.status == "READY"
  end

  # --- helpers ---

  defp pdf_root do
    root = tmp("pdf")
    File.mkdir_p!(Path.join(root, "reports/pdf_governance"))
    File.mkdir_p!(Path.join(root, "data/pdf_governance"))
    File.mkdir_p!(Path.join(root, "data/workflow_status"))
    write_pdf_status(root, false)

    File.write!(
      Path.join(root, "reports/pdf_governance/PDF_GOVERNANCE_REPORT.md"),
      "# PDF Report\n"
    )

    File.write!(Path.join(root, "reports/pdf_governance/PDF_DISTRIBUTION_BOARD.md"), "# Board\n")

    File.write!(
      Path.join(root, "data/pdf_governance/pdf_inventory.csv"),
      "path,cat\n/pdf1.pdf,a\n/pdf2.pdf,b\n"
    )

    File.write!(
      Path.join(root, "data/pdf_governance/pdf_inventory.jsonl"),
      ~s({"path":"/pdf1.pdf","cat":"a"}\n{"path":"/pdf2.pdf","cat":"b"}\n)
    )

    File.write!(
      Path.join(root, "data/pdf_governance/pdf_discord_distribution_plan.json"),
      ~s([]\n)
    )

    root
  end

  defp write_pdf_status(root, synthetic) do
    status = %{
      "pdf_total" => 2,
      "text_extracted" => 2,
      "updated_at" => "2026-08-27T00:00:00Z",
      "synthetic" => synthetic,
      "priority_counts" => %{"P2" => 1, "P3" => 1},
      "category_counts" => %{"ihk" => 2}
    }

    File.write!(
      Path.join(root, "data/workflow_status/pdf_governance_status.json"),
      Jason.encode!(status)
    )
  end

  defp repo_root do
    root = tmp("repo")
    File.mkdir_p!(Path.join(root, "reports/discord_documentation"))
    File.mkdir_p!(Path.join(root, "data/workflow_status"))

    write_repo_status(
      root,
      %{"total" => 130, "P0" => 18, "P1" => 38, "P2" => 46, "P3" => 28},
      false
    )

    Enum.each(
      [
        "GITHUB_REPO_CHANNEL_ASSIGNMENT.md",
        "github_repo_channel_assignment.json",
        "GITHUB_REPO_CANONICAL_INDEX.md",
        "github_repo_canonical_index.json",
        "REPO_CLEANUP_PRIORITY_BOARD.md",
        "repo_cleanup_priority_board.json"
      ],
      fn f -> File.write!(Path.join(root, "reports/discord_documentation/#{f}"), "{}") end
    )

    root
  end

  defp write_repo_status(root, priority, synthetic \\ false) do
    status = %{
      "raw_repo_entries" => 225,
      "canonical_repo_groups" => 130,
      "multi_copy_groups" => 54,
      "dirty_groups" => 75,
      "no_remote_groups" => 26,
      "updated_at" => "2026-08-23T20:34:24Z",
      "synthetic" => synthetic,
      "priority_counts" => priority
    }

    File.write!(
      Path.join(root, "data/workflow_status/repo_governance_status.json"),
      Jason.encode!(status)
    )
  end

  defp tmp(name) do
    root =
      Path.join(
        System.tmp_dir!(),
        "shadowops-governance-#{name}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    root
  end
end
