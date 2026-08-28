defmodule ShadowOpsCore.KaliNodeTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.KaliNode

  test "successful bounded hostname probe exposes Kali as a security node" do
    node = KaliNode.from_probe("kali-vm", {"kali-2026\n", 0}, 12)

    assert node.node_id == "kali"
    assert node.hostname == "kali-2026"
    assert node.status == "READY"
    assert node.reachable
    assert node.real_data
    refute node.synthetic
    assert node.metadata.role == "security_node"
    assert node.metadata.control_actions == ["status"]

    assert node.metadata.capabilities == [
             "healthcheck",
             "security_audit",
             "evidence_collection"
           ]

    refute node.metadata.arbitrary_shell
    refute node.metadata.arbitrary_systemd
    refute node.metadata.production_control_plane
  end

  test "failed SSH probe remains unavailable and never reports false readiness" do
    node = KaliNode.from_probe("kali-vm", {"permission denied", 255}, 8)

    assert node.node_id == "kali"
    assert node.status == "OPTIONAL_UNAVAILABLE"
    refute node.reachable
    refute node.real_data
    assert node.error_code == "KALI_NODE_UNREACHABLE"
  end

  test "empty hostname evidence fails closed" do
    node = KaliNode.from_probe("kali-vm", {"\n", 0}, 4)

    assert node.status == "OPTIONAL_UNAVAILABLE"
    refute node.reachable
    assert node.error_code == "KALI_NODE_IDENTITY_EMPTY"
  end
end
