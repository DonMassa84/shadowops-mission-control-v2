defmodule ShadowOpsWeb.ChatGPTNodesTest do
  use ExUnit.Case, async: false

  alias ShadowOpsWeb.NodeCatalog

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

  test "ChatGPT projects become logical nodes without fabricating READY" do
    path = temp_catalog_path()

    payload = %{
      "schema_version" => 1,
      "generated_at" => "2026-08-25T06:00:00Z",
      "projects" => [
        %{
          "id" => "chatgpt:ready-project",
          "name" => "Ready project",
          "source_type" => "chatgpt_library_project",
          "status" => "READY",
          "real_data" => true,
          "synthetic" => false,
          "reachable" => true,
          "content_ingested" => false,
          "integration_mode" => "LOCAL_MANIFEST_ONLY"
        },
        %{
          "id" => "chatgpt:missing-project",
          "name" => "Missing project",
          "source_type" => "chatgpt_library_project",
          "status" => "READY",
          "real_data" => false,
          "synthetic" => false,
          "reachable" => false,
          "content_ingested" => false,
          "integration_mode" => "LOCAL_MANIFEST_ONLY"
        }
      ]
    }

    File.write!(path, Jason.encode!(payload))
    System.put_env("SHADOWOPS_PROJECT_CATALOG", path)

    nodes = NodeCatalog.snapshot()
    ready = Enum.find(nodes.records, &(&1.node_id == "chatgpt:ready-project"))
    missing = Enum.find(nodes.records, &(&1.node_id == "chatgpt:missing-project"))

    assert ready.kind == "logical_project_node"
    assert ready.status == "READY"
    assert ready.health == "HEALTHY"
    assert ready.real_data == true
    assert ready.synthetic == false
    assert ready.reachable == true
    assert ready.metadata.control_actions == ["status"]

    assert missing.status == "NOT_CONFIGURED"
    assert missing.health == "UNAVAILABLE"
    assert missing.real_data == false
    assert missing.synthetic == false
    assert missing.reachable == false
    assert missing.error_code == "CHATGPT_PROJECT_NOT_CONFIGURED"

    File.rm(path)
  end

  test "ChatGPT logical nodes are status-only" do
    path = temp_catalog_path()

    payload = %{
      "schema_version" => 1,
      "generated_at" => "2026-08-25T06:00:00Z",
      "projects" => [
        %{
          "id" => "chatgpt:status-only",
          "name" => "Status only",
          "source_type" => "chatgpt_library_project",
          "status" => "READY",
          "real_data" => true,
          "synthetic" => false,
          "reachable" => true,
          "content_ingested" => false,
          "integration_mode" => "LOCAL_MANIFEST_ONLY"
        }
      ]
    }

    File.write!(path, Jason.encode!(payload))
    System.put_env("SHADOWOPS_PROJECT_CATALOG", path)

    assert {:ok, node} = NodeCatalog.action("chatgpt:status-only", "status")
    assert node.status == "READY"
    assert {:error, :action_not_allowed} = NodeCatalog.action("chatgpt:status-only", "start")
    assert {:error, :action_not_allowed} = NodeCatalog.action("chatgpt:status-only", "stop")

    File.rm(path)
  end

  test "nodes page separates physical infrastructure from ChatGPT project nodes" do
    path = temp_catalog_path()

    payload = %{
      "schema_version" => 1,
      "generated_at" => "2026-08-25T06:00:00Z",
      "projects" => [
        %{
          "id" => "chatgpt:ui-project",
          "name" => "ChatGPT UI Project",
          "source_type" => "chatgpt_library_project",
          "status" => "NOT_CONFIGURED",
          "real_data" => false,
          "synthetic" => false,
          "reachable" => false,
          "content_ingested" => false,
          "integration_mode" => "LOCAL_MANIFEST_ONLY"
        }
      ]
    }

    File.write!(path, Jason.encode!(payload))
    System.put_env("SHADOWOPS_PROJECT_CATALOG", path)

    conn = Plug.Test.conn(:get, "/nodes")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    assert response.resp_body =~ "Physical infrastructure"
    assert response.resp_body =~ "ChatGPT project nodes"
    assert response.resp_body =~ "ChatGPT UI Project"
    assert response.resp_body =~ "chatgpt:ui-project"
    assert response.resp_body =~ "Status only"
    assert response.resp_body =~ "Reference only"
    assert response.resp_body =~ "NOT_CONFIGURED"

    File.rm(path)
  end

  defp temp_catalog_path do
    Path.join(
      System.tmp_dir!(),
      "shadowops-chatgpt-nodes-#{System.unique_integer([:positive])}.json"
    )
  end
end
