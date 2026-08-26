defmodule ShadowOpsCore.ChatGPTCatalogMergeTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.ProjectCatalog

  test "ChatGPT replacement preserves GitHub records and removes stale ChatGPT records" do
    existing = [
      %{
        id: "github:repo",
        name: "Repo",
        source_type: "github_repository",
        status: "READY",
        real_data: true,
        synthetic: false,
        reachable: true,
        integration_mode: "REFERENCE_ONLY",
        url: "https://github.com/example/repo"
      },
      %{
        id: "chatgpt:stale",
        name: "Stale",
        source_type: "chatgpt_library_project",
        status: "READY",
        real_data: true,
        synthetic: false,
        reachable: true,
        integration_mode: "REFERENCE_ONLY"
      }
    ]

    incoming = [
      %{
        id: "chatgpt:current",
        name: "Current",
        source_type: "chatgpt_library_project",
        status: "READY",
        real_data: true,
        synthetic: false,
        reachable: true,
        integration_mode: "REFERENCE_ONLY"
      }
    ]

    merged =
      ProjectCatalog.merge_provider_projects(existing, incoming, "chatgpt_library_project")

    assert Enum.any?(merged, &(&1.id == "github:repo"))
    assert Enum.any?(merged, &(&1.id == "chatgpt:current"))
    refute Enum.any?(merged, &(&1.id == "chatgpt:stale"))
    assert length(merged) == 2
  end

  test "provider merge de-duplicates by source type and id" do
    duplicate = %{
      "id" => "chatgpt:project",
      "name" => "Project",
      "source_type" => "chatgpt_library_project",
      "status" => "READY",
      "real_data" => true,
      "synthetic" => false,
      "reachable" => true,
      "integration_mode" => "REFERENCE_ONLY"
    }

    merged =
      ProjectCatalog.merge_provider_projects(
        [],
        [duplicate, duplicate],
        "chatgpt_library_project"
      )

    assert length(merged) == 1
    assert hd(merged).id == "chatgpt:project"
  end
end
