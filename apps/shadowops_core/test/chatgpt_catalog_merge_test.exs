defmodule ShadowOpsCore.ChatGPTCatalogMergeTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.ProjectCatalog

  test "existing non-ChatGPT provider records can coexist with ChatGPT records" do
    github =
      ProjectCatalog.normalize_project(%{
        "id" => "github:repo",
        "name" => "Repo",
        "source_type" => "github_repository",
        "status" => "READY",
        "real_data" => true,
        "synthetic" => false,
        "reachable" => true,
        "integration_mode" => "REFERENCE_ONLY",
        "url" => "https://github.com/example/repo"
      })

    chatgpt =
      ProjectCatalog.normalize_project(%{
        "id" => "chatgpt:project",
        "name" => "Project",
        "source_type" => "chatgpt_library_project",
        "status" => "READY",
        "real_data" => true,
        "synthetic" => false,
        "reachable" => true,
        "integration_mode" => "REFERENCE_ONLY"
      })

    assert github.source_type == "github_repository"
    assert chatgpt.source_type == "chatgpt_library_project"
    assert github.id != chatgpt.id
  end
end
