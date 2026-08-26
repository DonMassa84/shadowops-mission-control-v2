defmodule WorkflowEngine.AgentContractTest do
  use ExUnit.Case, async: true

  alias WorkflowEngine.{AgentContract, Registry}
  alias WorkflowEngine.Registry.Error

  setup do
    assert {:ok, registry} = Registry.load()
    %{registry: registry}
  end

  test "validates every canonical workflow non-vacuously", %{registry: registry} do
    assert map_size(registry["workflows"]) == 9
    assert map_size(registry["agent_contracts"]) == 9
    assert Map.keys(registry["workflows"]) |> Enum.sort() ==
             Map.keys(registry["agent_contracts"]) |> Enum.sort()

    assert :ok = AgentContract.validate_registry(registry)

    for {workflow_id, workflow} <- registry["workflows"] do
      contract = registry["agent_contracts"][workflow_id]
      assert is_map(contract), workflow_id

      assert :ok =
               AgentContract.validate(
                 Map.put(workflow, "agent_contract", contract),
                 ["workflows", workflow_id]
               )
    end
  end

  test "fails closed when a workflow has no contract", %{registry: registry} do
    invalid = update_in(registry["agent_contracts"], &Map.delete(&1, "daily_digest"))

    assert {:error, %Error{code: :agent_contract_workflow_set_mismatch}} =
             AgentContract.validate_registry(invalid)
  end

  test "fails closed for a contract referencing an unknown workflow", %{registry: registry} do
    template = registry["agent_contracts"]["daily_digest"]
    invalid = put_in(registry, ["agent_contracts", "unknown_workflow"], template)

    assert {:error, %Error{code: :agent_contract_workflow_set_mismatch}} =
             AgentContract.validate_registry(invalid)
  end

  test "blocks unknown capabilities", %{registry: registry} do
    invalid =
      registry
      |> put_in(
        ["agent_contracts", "daily_digest", "agent_spec", "capability"],
        "unknown.capability"
      )
      |> put_in(
        ["agent_contracts", "daily_digest", "capabilities"],
        ["unknown.capability"]
      )

    assert {:error, %Error{code: :unknown_agent_capability}} =
             AgentContract.validate_registry(invalid)
  end

  test "blocks executor and capability mismatches", %{registry: registry} do
    invalid =
      put_in(
        registry,
        ["agent_contracts", "daily_digest", "agent_spec", "executor"],
        "service_runtime"
      )

    assert {:error, %Error{code: :agent_capability_or_executor_mismatch}} =
             AgentContract.validate_registry(invalid)
  end

  test "blocks risk mismatches", %{registry: registry} do
    invalid =
      put_in(
        registry,
        ["agent_contracts", "daily_digest", "agent_spec", "risk_level"],
        "L1"
      )

    assert {:error, %Error{code: :agent_risk_mismatch}} =
             AgentContract.validate_registry(invalid)
  end

  test "blocks approval bypass", %{registry: registry} do
    invalid =
      put_in(
        registry,
        ["agent_contracts", "daily_digest", "agent_spec", "approval_required"],
        false
      )

    assert {:error, %Error{code: :agent_approval_policy_mismatch}} =
             AgentContract.validate_registry(invalid)
  end

  test "blocks human-review bypass for approval-required workflows", %{registry: registry} do
    invalid =
      put_in(
        registry,
        ["agent_contracts", "daily_digest", "human_review_policy", "required"],
        false
      )

    assert {:error, %Error{code: :human_review_required_for_approval}} =
             AgentContract.validate_registry(invalid)
  end

  test "blocks runtime binding drift", %{registry: registry} do
    invalid =
      put_in(
        registry,
        ["agent_contracts", "daily_digest", "agent_spec", "runtime_binding"],
        "/tmp/untrusted-runtime"
      )

    assert {:error, %Error{code: :agent_runtime_binding_mismatch}} =
             AgentContract.validate_registry(invalid)
  end

  test "requires fail-closed evidence policy", %{registry: registry} do
    invalid =
      put_in(
        registry,
        ["agent_contracts", "daily_digest", "evidence_policy", "audit_required"],
        false
      )

    assert {:error, %Error{code: :agent_evidence_policy_must_fail_closed}} =
             AgentContract.validate_registry(invalid)
  end

  test "requires all contract fields", %{registry: registry} do
    invalid =
      update_in(
        registry["agent_contracts"]["daily_digest"],
        &Map.delete(&1, "required_inputs")
      )

    assert {:error, %Error{code: :agent_contract_missing_keys}} =
             AgentContract.validate_registry(invalid)
  end
end
