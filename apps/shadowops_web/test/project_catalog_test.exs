defmodule ShadowOpsWeb.ProjectCatalogTest do
  use ExUnit.Case, async: false

  alias ShadowOpsWeb.ProjectCatalog

  setup do
    previous = System.get_env("SHADOWOPS_PROJECT_CATALOG")

    on_exit(fn ->
      if previous do
        System.put_env("SHADOWOPS_PROJECT_CATALOG", previous)
      else
        System.delete_env("SHADOWOPS_PROJECT_CATALOG")
      end
    end)

    :ok
  end

  test "missing catalog remains fail-visible" do
    path = Path.join(System.tmp_dir!(), "shadowops-project-catalog-missing-#{System.unique_integer([:positive])}.json")
    System.put_env("SHADOWOPS_PROJECT_CATALOG", path)

    catalog = ProjectCatalog.snapshot()

    assert catalog.status == "NOT_CONFIGURED"
    assert catalog.real_data == false
    assert catalog.synthetic == false
    assert catalog.reachable == false
    assert catalog.counts.total == nil
    assert catalog.projects == []
    assert catalog.error_code == "SOURCE_MISSING"
  end

  test "catalog sanitizes metadata and refuses fabricated READY state" do
    path = Path.join(System.tmp_dir!(), "shadowops-project-catalog-#{System.unique_integer([:positive])}.json")

    payload = %{
      "schema_version" => 1,
      "generated_at" => "2026-08-25T00:00:00Z",
      "github_discovery_mode" => "AUTHENTICATED_ALL",
      "projects" => [
        %{
          "id" => "github:DonMassa84/example",
          "name" => "example",
          "source_type" => "github_repository",
          "status" => "READY",
          "visibility" => "private",
          "default_branch" => "main",
          "reachable" => true,
          "real_data" => true,
          "synthetic" => false,
          "content_ingested" => false,
          "integration_mode" => "REFERENCE_ONLY",
          "url" => "https://github.com/DonMassa84/example",
          "secret" => "must-not-leak"
        },
        %{
          "id" => "chatgpt:local-project",
          "name" => "Local project",
          "source_type" => "chatgpt_library_project",
          "status" => "READY",
          "reachable" => false,
          "real_data" => false,
          "synthetic" => false,
          "content_ingested" => false,
          "integration_mode" => "LOCAL_MANIFEST_ONLY",
          "local_export_path" => "/private/path/must-not-leak"
        }
      ]
    }

    File.write!(path, Jason.encode!(payload))
    System.put_env("SHADOWOPS_PROJECT_CATALOG", path)

    catalog = ProjectCatalog.snapshot()

    assert catalog.status == "READY"
    assert catalog.counts.total == 2
    assert catalog.counts.github == 1
    assert catalog.counts.chatgpt == 1
    assert catalog.counts.ready == 1
    assert catalog.counts.not_configured == 1

    github = Enum.find(catalog.projects, &(&1.source_type == "github_repository"))
    chatgpt = Enum.find(catalog.projects, &(&1.source_type == "chatgpt_library_project"))

    assert github.status == "READY"
    assert github.real_data == true
    assert github.synthetic == false
    assert github.reachable == true
    refute Map.has_key?(github, :secret)

    assert chatgpt.status == "NOT_CONFIGURED"
    assert chatgpt.real_data == false
    assert chatgpt.reachable == false
    refute Map.has_key?(chatgpt, :local_export_path)

    File.rm(path)
  end

  test "browser route renders without requiring catalog connectivity" do
    path = Path.join(System.tmp_dir!(), "shadowops-project-catalog-route-missing-#{System.unique_integer([:positive])}.json")
    System.put_env("SHADOWOPS_PROJECT_CATALOG", path)

    conn = Plug.Test.conn(:get, "/projects/federated")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    assert response.resp_body =~ "Federated projects"
    assert response.resp_body =~ "NOT_CONFIGURED"
  end
end
