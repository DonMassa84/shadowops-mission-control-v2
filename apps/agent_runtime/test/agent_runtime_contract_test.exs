defmodule AgentRuntime.ContractTest do
  use ExUnit.Case, async: true

  alias AgentRuntime.AgentSpec
  alias AgentRuntime.ExternalWorkflowCatalog
  alias AgentRuntime.ExternalWorkflowSpec
  alias AgentRuntime.RiskPolicy
  alias AgentRuntime.TccImporter
  alias WorkflowEngine.Registry

  test "builds a valid generic agent spec" do
    assert {:ok, spec} =
             AgentSpec.new(%{
               id: "source_agent",
               version: "1.0.0",
               capabilities: ["documents.read"],
               required_inputs: ["document"],
               produced_outputs: ["claims"],
               permissions: ["documents:read"],
               timeout_ms: 10_000,
               retry_policy: %{max_attempts: 3, backoff_ms: 100},
               human_review_policy: :conditional,
               evidence_policy: %{required: true},
               executor: :elixir,
               metadata: %{}
             })

    assert spec.id == "source_agent"
    assert spec.retry_policy.max_attempts == 3
  end

  test "fails closed for malformed agent specs" do
    assert {:error, {:invalid_field, :id}} = AgentSpec.new(%{id: "", version: "1.0.0"})
  end

  test "maps L0 through L3 to explicit execution policy" do
    assert {:ok, %{automatic_execution: true, approval_required: false}} = RiskPolicy.get("L0")
    assert {:ok, %{effect_scope: :local_state_change}} = RiskPolicy.get("L1")
    assert {:ok, %{automatic_execution: false, approval_required: true}} = RiskPolicy.get("L2")
    assert {:ok, %{effect_scope: :privileged_high_risk}} = RiskPolicy.get("L3")
  end

  test "derives all 16 known WhatsApp specs from registry v2" do
    assert {:ok, registry} = Registry.load()
    assert {:ok, specs} = ExternalWorkflowCatalog.from_registry(registry)
    assert length(specs) == 16

    sync = Enum.find(specs, &(&1.id == "whatsapp-sync-status"))
    subscribe = Enum.find(specs, &(&1.id == "whatsapp-meta-subscribe"))

    assert %ExternalWorkflowSpec{risk_level: "L0", approval_required: false} = sync
    assert %ExternalWorkflowSpec{risk_level: "L2", approval_required: true} = subscribe
  end

  test "reports the remaining 32 shadowmaker workflows as unresolved" do
    assert {:ok, registry} = Registry.load()
    assert {:ok, summary} = ExternalWorkflowCatalog.summary(registry)
    assert summary.expected_shadowmaker_tasks == 48
    assert summary.known_individual_specs == 16
    assert summary.unresolved_shadowmaker_tasks == 32
  end

  test "imports list-shaped TCC JSON and derives risk distribution" do
    json =
      Jason.encode!([
        %{"id" => "status-a", "risk_level" => "L0", "capability" => "READ"},
        %{"id" => "maintain-b", "risk_level" => "L1", "capability" => "LOCAL"},
        %{"id" => "action-c", "risk_level" => "L2", "capability" => "ACTION"},
        %{"id" => "privileged-d", "risk_level" => "L3", "capability" => "PRIVILEGED"}
      ])

    assert {:ok, specs} = TccImporter.import_json(json)
    assert TccImporter.risk_distribution(specs) == %{"L0" => 1, "L1" => 1, "L2" => 1, "L3" => 1}
  end

  test "imports object-keyed TCC registries" do
    json = Jason.encode!(%{"status-a" => %{"risk_level" => "L0"}})
    assert {:ok, [%ExternalWorkflowSpec{id: "status-a"}]} = TccImporter.import_json(json)
  end

  test "rejects missing risk levels instead of guessing" do
    json = Jason.encode!([%{"id" => "unknown-risk"}])

    assert {:error, {:invalid_tcc_workflow, "unknown-risk", _reason}} =
             TccImporter.import_json(json)
  end

  test "rejects duplicate imported workflow ids" do
    json =
      Jason.encode!([
        %{"id" => "same", "risk_level" => "L0"},
        %{"id" => "same", "risk_level" => "L1"}
      ])

    assert {:error, {:duplicate_workflow_ids, ["same"]}} = TccImporter.import_json(json)
  end
end
