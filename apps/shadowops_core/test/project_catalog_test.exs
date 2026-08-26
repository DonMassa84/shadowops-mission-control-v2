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

  test "IHK domain truth correlates the existing catalog project" do
    ihk =
      ProjectCatalog.normalize_project(%{
        "id" => "ihk:zero-trust-project",
        "name" => "IHK Zero Trust",
        "domain" => "ihk",
        "source_type" => "local_project",
        "status" => "DISCOVERED",
        "real_data" => false,
        "synthetic" => false,
        "reachable" => false
      })

    other =
      ProjectCatalog.normalize_project(%{
        "id" => "shadowops:mission-control-v2",
        "name" => "ShadowOps",
        "domain" => "shadowops",
        "source_type" => "local_project",
        "status" => "DISCOVERED",
        "real_data" => false,
        "synthetic" => false,
        "reachable" => false
      })

    catalog = %{
      status: "READY",
      projects: [ihk, other],
      counts: %{}
    }

    source_truth = %{
      status: "READY",
      health: "HEALTHY",
      real_data: true,
      synthetic: false,
      reachable: true,
      source: "/private/local/ihk.json",
      source_paths: %{
        project_root: "/private/local/project"
      }
    }

    result =
      ProjectCatalog.correlate_project(
        catalog,
        "ihk:zero-trust-project",
        source_truth
      )

    correlated =
      Enum.find(result.projects, &(&1.id == "ihk:zero-trust-project"))

    untouched =
      Enum.find(result.projects, &(&1.id == "shadowops:mission-control-v2"))

    assert correlated.status == "READY"
    assert correlated.real_data == true
    assert correlated.synthetic == false
    assert correlated.reachable == true
    assert correlated.integration_mode == "LOCAL_MANIFEST_CORRELATED"

    # Private paths must not escape into the federated project catalog.
    refute Map.has_key?(correlated, :source)
    refute Map.has_key?(correlated, :source_paths)

    assert untouched.status == "DISCOVERED"
    assert untouched.real_data == false

    assert result.counts.ready == 1
    assert result.counts.discovered == 1
  end

  test "unproven READY domain truth remains fail-closed" do
    project =
      ProjectCatalog.normalize_project(%{
        "id" => "ihk:zero-trust-project",
        "name" => "IHK Zero Trust",
        "domain" => "ihk",
        "source_type" => "local_project",
        "status" => "DISCOVERED",
        "real_data" => false,
        "synthetic" => false,
        "reachable" => false
      })

    catalog = %{
      status: "READY",
      projects: [project],
      counts: %{}
    }

    result =
      ProjectCatalog.correlate_project(
        catalog,
        "ihk:zero-trust-project",
        %{
          status: "READY",
          real_data: false,
          synthetic: false,
          reachable: false
        }
      )

    correlated = hd(result.projects)

    refute correlated.status == "READY"
    assert correlated.real_data == false
  end
end
