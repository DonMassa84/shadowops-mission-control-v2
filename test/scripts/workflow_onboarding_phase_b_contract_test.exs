defmodule WorkflowOnboardingPhaseBContractTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../..", __DIR__)
  @script Path.join(@repo_root, "scripts/workflow_onboarding_phase_b.exs")

  test "phase B implementation exists" do
    assert File.regular?(@script)
  end

  test "contains no registry writer" do
    body = File.read!(@script)

    refute body =~ "YamlElixir.write_to_file"
    refute body =~ "YamlElixir.write_to_string"
    refute body =~ ~s(File.write!("config/workflow_registry_v2.yaml")
  end

  test "does not execute workflows" do
    body = File.read!(@script)

    assert body =~ "RUNTIME_EXECUTION=NO"

    refute body =~ "System.cmd("
    refute body =~ "Port.open("
  end

  test "does not invent external IDs" do
    body = File.read!(@script)

    refute body =~ "opencode_standard-1"
    refute body =~ "telegram_workflow_controller-1"
  end

  test "preserves WhatsApp subset provenance" do
    body = File.read!(@script)

    assert body =~ "whatsapp_agent_pack"
    assert body =~ "shadowmaker_tasks"
    assert body =~ "subset_of"
  end

  test "has canonical collision gate" do
    assert File.read!(@script) =~ "CANONICAL_ID_COLLISION"
  end

  test "has L2/L3 approval gate" do
    assert File.read!(@script) =~ "UNAPPROVED_L2_L3"
  end

  test "has unresolved workflow blocker" do
    assert File.read!(@script) =~ "WORKFLOW_IDS_NOT_IMPORTED"
  end

  test "has unknown runtime blocker" do
    assert File.read!(@script) =~ "UNKNOWN_RUNTIME"
  end

  test "has unknown capability blocker" do
    assert File.read!(@script) =~ "UNKNOWN_CAPABILITY"
  end

  test "has unknown risk blocker" do
    assert File.read!(@script) =~ "UNKNOWN_RISK"
  end

  test "has deterministic SHA evidence" do
    body = File.read!(@script)

    assert body =~ ":crypto.hash(:sha256"
    assert body =~ "PROPOSAL_SHA256"
  end
end
