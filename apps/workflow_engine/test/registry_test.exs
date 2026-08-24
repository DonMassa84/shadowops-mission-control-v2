defmodule WorkflowEngine.RegistryTest do
  use ExUnit.Case, async: true

  alias WorkflowEngine.Registry
  alias WorkflowEngine.Registry.Error

  setup do
    assert {:ok, registry} = Registry.load()
    %{registry: registry}
  end

  test "loads and validates the schema-v2 registry", %{registry: registry} do
    assert registry["schema_version"] == 2
    assert is_map(registry["workflows"])
    assert is_map(registry["workflow_runs"])
    assert is_map(registry["external_runtime_sets"])
    assert :ok = Registry.validate(registry)
  end

  test "preserves the original workflows and imports only approved candidates" do
    workflows = Registry.list_workflows()

    for id <-
          ~w(finanzabgleich career_email_only document_ai repository_quality finance_quality_gate) do
      assert id in workflows
    end

    for id <- ~w(agent_state_sync career_funnel_ihk daily_digest shadow_system_overnight_audit) do
      assert id in workflows
    end

    refute "sg_scan" in workflows
  end

  test "preserves WhatsApp and unresolved Shadowmaker counts", %{registry: registry} do
    shadowmaker = registry["external_runtime_sets"]["shadowmaker_tasks"]
    whatsapp = registry["external_runtime_sets"]["whatsapp_agent_pack"]

    whatsapp_ids =
      whatsapp["risk_groups"]
      |> Map.values()
      |> Enum.flat_map(& &1["workflows"])

    assert whatsapp["workflow_count"] == 16
    assert length(whatsapp_ids) == 16
    assert shadowmaker["total_workflow_count"] - length(whatsapp_ids) == 32
  end

  test "uses trusted argv only for locally verified executable workflows", %{registry: registry} do
    workflows = registry["workflows"]

    assert workflows["agent_state_sync"]["type"] == "system"
    assert workflows["agent_state_sync"]["status"] == "VERIFIED_EXECUTABLE"

    assert workflows["agent_state_sync"]["argv"] == [
             "-n",
             "/home/schattenmacher/.local/state/agent-state-hub/sync.lock",
             "/home/schattenmacher/DokumentenSystem/08_KONFIGRATION/bin/agent-state-sync"
           ]

    assert workflows["daily_digest"]["argv"] == []
    assert workflows["shadow_system_overnight_audit"]["argv"] == []
    assert workflows["career_funnel_ihk"]["status"] == "DISABLED_BY_CONFIGURATION"
    assert workflows["career_funnel_ihk"]["optional"]
    assert workflows["career_funnel_ihk"]["configuration_status"] == "NOT_CONFIGURED"
    refute Map.has_key?(workflows["career_funnel_ihk"], "argv")
  end

  test "fails closed when optional configuration metadata is incomplete", %{registry: registry} do
    invalid = put_in(registry, ["workflows", "career_funnel_ihk", "optional"], false)

    assert {:error, %Error{code: :invalid_optional_configuration_contract}} =
             Registry.validate(invalid)
  end

  test "rejects malformed registry argv", %{registry: registry} do
    invalid = put_in(registry, ["workflows", "daily_digest", "argv"], ["valid", 42])

    assert {:error, %Error{code: :invalid_workflow_argv}} = Registry.validate(invalid)
  end

  test "requires absolute runtimes only for verified executable workflows", %{registry: registry} do
    invalid = put_in(registry, ["workflows", "daily_digest", "runtime"], "daily-digest")

    assert {:error, %Error{code: :invalid_verified_runtime}} = Registry.validate(invalid)
    assert registry["workflows"]["repository_quality"]["runtime"] == "github_actions"
    assert :ok = Registry.validate(registry)
  end

  test "keeps career wave 07 as a workflow run", %{registry: registry} do
    assert registry["workflow_runs"]["career_wave_07"]["workflow"] == "career_email_only"
  end

  test "returns a typed error for an unsupported schema version", %{registry: registry} do
    invalid = Map.put(registry, "schema_version", 99)

    assert {:error,
            %Error{
              code: :unsupported_schema_version,
              path: ["schema_version"]
            }} = Registry.validate(invalid)
  end

  test "returns a typed error for an unknown workflow run reference", %{registry: registry} do
    invalid =
      put_in(registry, ["workflow_runs", "career_wave_07", "workflow"], "missing_workflow")

    assert {:error,
            %Error{
              code: :unknown_workflow_reference,
              path: ["workflow_runs", "career_wave_07", "workflow"]
            }} = Registry.validate(invalid)
  end

  test "checks the external risk distribution against the declared total", %{registry: registry} do
    invalid =
      put_in(
        registry,
        ["external_runtime_sets", "shadowmaker_tasks", "risk_distribution", "L0"],
        25
      )

    assert {:error,
            %Error{
              code: :risk_total_mismatch,
              path: ["external_runtime_sets", "shadowmaker_tasks", "risk_distribution"]
            }} = Registry.validate(invalid)
  end

  test "checks WhatsApp workflow count and uniqueness", %{registry: registry} do
    invalid =
      put_in(
        registry,
        ["external_runtime_sets", "whatsapp_agent_pack", "workflow_count"],
        15
      )

    assert {:error,
            %Error{
              code: :workflow_count_mismatch,
              path: ["external_runtime_sets", "whatsapp_agent_pack", "risk_groups"]
            }} = Registry.validate(invalid)
  end

  test "summarizes the registry" do
    assert {:ok, summary} = Registry.summary()
    assert summary.schema_version == 2
    assert summary.registry_name == "shadowops-workflows"
    assert summary.workflows >= 5
    assert summary.workflow_runs >= 1
    assert summary.external_runtime_sets >= 4
  end

  test "returns a typed load error for a missing file" do
    assert {:error, %Error{code: :registry_load_failed}} =
             Registry.load("/definitely/not/a/registry.yaml")
  end
end
