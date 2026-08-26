defmodule ShadowOpsCore.ProjectCatalogTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.ProjectCatalog

  test "normalization strips unknown fields and enforces truthfulness" do
    ready =
      ProjectCatalog.normalize_project(%{
        "id" => "github:owner/repo",
        "name" => "repo",
        "source_type" => "github_repository",
        "status" => "READY",
        "real_data" => true,
        "synthetic" => false,
        "reachable" => true,
        "url" => "https://github.com/owner/repo",
        "secret" => "must-not-survive"
      })

    unproven =
      ProjectCatalog.normalize_project(%{
        "id" => "chatgpt:project",
        "name" => "project",
        "source_type" => "chatgpt_library_project",
        "status" => "READY",
        "real_data" => false,
        "synthetic" => false,
        "reachable" => false,
        "local_export_path" => "/private/path"
      })

    assert ready.status == "READY"
    assert ready.url == "https://github.com/owner/repo"
    refute Map.has_key?(ready, :secret)

    assert unproven.status == "NOT_CONFIGURED"
    refute Map.has_key?(unproven, :local_export_path)
  end

  test "non-GitHub URLs are removed from the projection" do
    project =
      ProjectCatalog.normalize_project(%{
        "id" => "chatgpt:project",
        "name" => "project",
        "status" => "NOT_CONFIGURED",
        "url" => "file:///private/project"
      })

    assert project.url == nil
  end
end
