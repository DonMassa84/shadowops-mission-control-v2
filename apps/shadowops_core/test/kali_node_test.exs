defmodule ShadowOpsCore.KaliNodeTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.KaliNode

  test "successful bounded hostname probe exposes Kali as preferred security and forensics node" do
    node = KaliNode.from_probe("kali-vm", {"kali-2026\n", 0}, 12)

    assert node.node_id == "kali"
    assert node.hostname == "kali-2026"
    assert node.status == "READY"
    assert node.reachable
    assert node.real_data
    refute node.synthetic
    assert node.metadata.role == "security_node"
    assert node.metadata.specialization == "security_forensics"
    assert node.metadata.scheduler_priority == "preferred_for_matching_capability"
    assert node.metadata.control_actions == ["status"]
    assert node.metadata.capability_activation == "requires_current_runtime_tool_evidence"
    assert node.metadata.execution_policy == "bounded_workflows_only"
    assert node.metadata.target_policy == "owned_or_explicitly_authorized_scope_only"

    for capability <- [
          "security_audit",
          "network_discovery",
          "vulnerability_assessment",
          "forensic_triage",
          "pcap_analysis",
          "malware_scan",
          "yara_scan",
          "secrets_scan",
          "container_security_audit",
          "web_passive_assessment"
        ] do
      assert capability in node.metadata.capabilities
    end

    for workload <- [
          "security",
          "network_security",
          "vulnerability_management",
          "digital_forensics",
          "incident_response"
        ] do
      assert workload in node.metadata.preferred_workloads
    end

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
