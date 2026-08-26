defmodule ShadowOpsCore.NodeTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.Node

  test "logical ChatGPT node is READY only with truthful evidence" do
    project = %{
      id: "chatgpt:verified",
      name: "Verified",
      status: "READY",
      real_data: true,
      synthetic: false,
      reachable: true,
      integration_mode: "LOCAL_MANIFEST_ONLY",
      content_ingested: false
    }

    node = Node.logical_project(project, "2026-08-25T06:00:00Z")

    assert node.status == "READY"
    assert node.health == "HEALTHY"
    assert node.real_data == true
    assert node.synthetic == false
    assert node.reachable == true
    assert Node.logical?(node)
    assert Node.provider(node) == :chatgpt
    assert Node.action_allowed?(node, "status")
    refute Node.action_allowed?(node, "start")
    refute Node.action_allowed?(node, "stop")
  end

  test "unproven logical node remains NOT_CONFIGURED" do
    project = %{
      "id" => "chatgpt:unproven",
      "name" => "Unproven",
      "status" => "READY",
      "real_data" => false,
      "synthetic" => false,
      "reachable" => false,
      "integration_mode" => "LOCAL_MANIFEST_ONLY",
      "content_ingested" => false
    }

    node = Node.logical_project(project, nil)

    assert node.status == "NOT_CONFIGURED"
    assert node.health == "UNAVAILABLE"
    assert node.error_code == "CHATGPT_PROJECT_NOT_CONFIGURED"
    assert Node.id(node) == "chatgpt:unproven"
  end

  test "physical projections are not constrained to logical status-only controls" do
    physical = %{node_id: "local-ryzen", metadata: %{logical: false, provider: "local"}}

    refute Node.logical?(physical)
    assert Node.provider(physical) == :local
    assert Node.action_allowed?(physical, "start")
  end
end
