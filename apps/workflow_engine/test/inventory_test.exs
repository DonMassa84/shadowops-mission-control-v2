defmodule WorkflowEngine.InventoryTest do
  use ExUnit.Case, async: true

  alias WorkflowEngine.{Inventory, Registry}

  setup do
    assert {:ok, registry} = Registry.load()
    %{registry: registry}
  end

  test "counts canonical and external workflow slots without double-counting domain packs", %{
    registry: registry
  } do
    summary = Inventory.summary(registry)

    assert summary["canonical_count"] == 10
    assert summary["external_count"] == 61
    assert summary["total_count"] == 71
    assert summary["named_external_count"] == 16
    assert summary["named_count"] == 26
    assert summary["unresolved_count"] == 45
  end

  test "keeps WhatsApp inside Shadowmaker total while exposing all source-listed IDs", %{
    registry: registry
  } do
    summary = Inventory.summary(registry)
    sets = Map.new(summary["sets"], &{&1["id"], &1})

    assert sets["shadowmaker_tasks"]["workflow_count"] == 48
    assert sets["shadowmaker_tasks"]["named_workflow_count"] == 16
    assert sets["shadowmaker_tasks"]["unresolved_count"] == 32
    assert sets["shadowmaker_tasks"]["counted_in_total"]

    assert sets["whatsapp_agent_pack"]["workflow_count"] == 16
    assert sets["whatsapp_agent_pack"]["named_workflow_count"] == 16
    assert sets["whatsapp_agent_pack"]["unresolved_count"] == 0
    refute sets["whatsapp_agent_pack"]["counted_in_total"]

    assert sets["opencode_standard"]["unresolved_count"] == 7
    assert sets["telegram_workflow_controller"]["unresolved_count"] == 6
  end

  test "external named workflows are visible but fail closed for execution", %{registry: registry} do
    workflows = Inventory.external_workflows(registry)

    assert length(workflows) == 16

    status = Enum.find(workflows, &(&1["id"] == "whatsapp-status"))
    purge = Enum.find(workflows, &(&1["id"] == "whatsapp-purge-expired"))

    assert status["source_set"] == "whatsapp_agent_pack"
    assert status["risk_level"] == "L0"
    assert status["approval_required"] == false
    assert status["status"] == "REGISTRY_ONLY"
    assert status["execution_status"] == "EXTERNAL_REGISTRY_ONLY"
    refute status["executable"]

    assert purge["risk_level"] == "L2"
    assert purge["approval_required"] == true
    refute purge["executable"]
  end
end
