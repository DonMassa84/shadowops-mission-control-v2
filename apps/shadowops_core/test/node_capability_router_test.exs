defmodule ShadowOpsCore.NodeCapabilityRouterTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.NodeCapabilityRouter

  test "security capability prefers Kali when current evidence verifies it" do
    nodes = [
      node("local-ryzen", ["security_audit"]),
      node("i7", ["security_audit"]),
      node("kali", ["security_audit"])
    ]

    assert {:ok, route} = NodeCapabilityRouter.route("security_audit", nodes, %{risk_level: "L1"})
    assert route.node_id == "kali"
    assert route.preferred_node == "kali"
    refute route.fallback
  end

  test "security fallback requires independently verified equivalent capability" do
    nodes = [
      node("kali", ["security_audit"], status: "OPTIONAL_UNAVAILABLE", reachable: false),
      node("local-ryzen", ["security_audit"]),
      node("i7", [])
    ]

    assert {:ok, route} = NodeCapabilityRouter.route("security_audit", nodes, %{risk_level: "L1"})
    assert route.node_id == "local-ryzen"
    assert route.fallback

    nodes = [
      node("kali", ["security_audit"], status: "OPTIONAL_UNAVAILABLE", reachable: false),
      node("local-ryzen", []),
      node("i7", [])
    ]

    assert {:error, :no_verified_executor} =
             NodeCapabilityRouter.route("security_audit", nodes, %{risk_level: "L1"})
  end

  test "declared, synthetic, stale, or unreachable evidence cannot make a node selectable" do
    declared_only =
      node("kali", [])
      |> put_in([:metadata, :capabilities], ["forensic_triage"])

    synthetic = node("local-ryzen", ["forensic_triage"], synthetic: true)
    stale = node("i7", ["forensic_triage"], status: "DEGRADED")

    assert {:error, :no_verified_executor} =
             NodeCapabilityRouter.route("forensic_triage", [declared_only, synthetic, stale], %{
               risk_level: "L1"
             })
  end

  test "active assessment requires authorized target and L2/L3 consumed approval" do
    nodes = [node("kali", ["vulnerability_assessment"])]

    assert {:error, :target_not_authorized} =
             NodeCapabilityRouter.route("vulnerability_assessment", nodes, %{
               risk_level: "L2",
               approval_status: :consumed
             })

    assert {:error, :approval_required} =
             NodeCapabilityRouter.route("vulnerability_assessment", nodes, %{
               risk_level: "L2",
               target_authorized: true,
               evidence_risk_level: "L0"
             })

    assert {:ok, route} =
             NodeCapabilityRouter.route("vulnerability_assessment", nodes, %{
               risk_level: "L2",
               target_authorized: true,
               approval_status: :consumed,
               evidence_risk_level: "L0"
             })

    assert route.node_id == "kali"
  end

  test "AI prefers Ryzen and QA prefers i7 only when verified" do
    nodes = [
      node("local-ryzen", ["ai_inference", "qa"]),
      node("i7", ["ai_inference", "qa"]),
      node("kali", ["qa"])
    ]

    assert {:ok, %{node_id: "local-ryzen", fallback: false}} =
             NodeCapabilityRouter.route("ai_inference", nodes, %{risk_level: "L0"})

    assert {:ok, %{node_id: "i7", fallback: false}} =
             NodeCapabilityRouter.route("qa", nodes, %{risk_level: "L0"})
  end

  test "arbitrary shell, systemd, production control, and unknown capabilities fail closed" do
    nodes = [node("kali", ["arbitrary_shell", "arbitrary_systemd"])]

    for capability <- ["arbitrary_shell", "arbitrary_systemd", "production_control_plane"] do
      assert {:error, :capability_not_routable} =
               NodeCapabilityRouter.route(capability, nodes, %{risk_level: "L0"})
    end

    assert {:error, :unsupported_capability} =
             NodeCapabilityRouter.route("unknown_capability", nodes, %{risk_level: "L0"})
  end

  defp node(id, verified, opts \\ []) do
    %{
      id: "node-#{id}",
      node_id: id,
      status: Keyword.get(opts, :status, "READY"),
      reachable: Keyword.get(opts, :reachable, true),
      real_data: Keyword.get(opts, :real_data, true),
      synthetic: Keyword.get(opts, :synthetic, false),
      metadata: %{
        verified_capabilities: verified,
        capability_evidence_source: "test runtime evidence",
        capability_evidence_at: "2026-08-28T00:00:00Z"
      }
    }
  end
end
