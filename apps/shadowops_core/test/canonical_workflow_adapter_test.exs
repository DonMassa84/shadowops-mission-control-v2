defmodule ShadowOpsCore.CanonicalWorkflowAdapterTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.Adapters.{
    CanonicalWorkflowAdapter,
    ScriptAdapter,
    SystemdAdapter
  }

  test "local script maps to ScriptAdapter" do
    assert {:ok, ScriptAdapter} =
             CanonicalWorkflowAdapter.adapter_for(%{source: "local_script"})
  end

  test "systemd maps to SystemdAdapter" do
    assert {:ok, SystemdAdapter} =
             CanonicalWorkflowAdapter.adapter_for(%{source: "systemd"})
  end

  test "GitHub execution remains disconnected" do
    assert {:error, :github_dispatch_not_connected} =
             CanonicalWorkflowAdapter.adapter_for(%{source: "github_actions"})
  end

  test "unknown source fails closed" do
    assert {:error, {:workflow_executor_not_connected, "unknown"}} =
             CanonicalWorkflowAdapter.adapter_for(%{source: "unknown"})
  end

  test "L2 and L3 require approval" do
    assert {:error, {:workflow_approval_required, "L2"}} =
             CanonicalWorkflowAdapter.risk_gate(
               %{risk_level: "L2"},
               "AUTO"
             )

    assert {:error, {:workflow_approval_required, "L3"}} =
             CanonicalWorkflowAdapter.risk_gate(
               %{risk_level: "L3"},
               "AUTO"
             )
  end
end
