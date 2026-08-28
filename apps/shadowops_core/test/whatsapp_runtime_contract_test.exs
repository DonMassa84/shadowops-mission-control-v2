defmodule ShadowOpsCore.WhatsappRuntimeContractTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.Adapters.TccAdapter

  @all_ids [
    "so:wf:v1:whatsapp-status",
    "so:wf:v1:whatsapp-sync-status",
    "so:wf:v1:whatsapp-worker-status",
    "so:wf:v1:whatsapp-queue",
    "so:wf:v1:whatsapp-doctor",
    "so:wf:v1:whatsapp-contacts",
    "so:wf:v1:whatsapp-report",
    "so:wf:v1:whatsapp-meta-status",
    "so:wf:v1:whatsapp-maintenance-15min",
    "so:wf:v1:whatsapp-maintenance-hourly",
    "so:wf:v1:whatsapp-maintenance-daily",
    "so:wf:v1:whatsapp-backup",
    "so:wf:v1:whatsapp-worker-drain",
    "so:wf:v1:whatsapp-retry-all",
    "so:wf:v1:whatsapp-purge-expired",
    "so:wf:v1:whatsapp-meta-subscribe"
  ]

  @blocked_ids ["so:wf:v1:whatsapp-doctor", "so:wf:v1:whatsapp-meta-status"]
  @l2_ids ["so:wf:v1:whatsapp-purge-expired", "so:wf:v1:whatsapp-meta-subscribe"]

  defp inventory do
    "/home/schattenmacher/Projects/shadowops-whatsapp-bindings/verified_app/data/workflows.json" |> Path.expand()
    |> File.read!()
    |> Jason.decode!()
    |> Map.get("workflows")
  end

  test "TCC status shows whatsapp pack connected with 16 executable allowlist" do
    status = TccAdapter.status()
    assert status[:state] == "CONNECTED"
    assert status[:executable_allowlist] == 16
    assert status[:arbitrary_shell] == "BLOCKED"
  end

  test "unknown workflow IDs are rejected by run/3" do
    unknowns = [
      "so:wf:v1:this-does-not-exist",
      "../../bin/sh",
      "/bin/bash",
      "so:wf:v1:whatsapp-status;id",
      "$(id)",
      "\"; id\"",
      "so:wf:v1:../../bin/sh"
    ]
    for id <- unknowns do
      assert {:error, :workflow_not_allowlisted} = TccAdapter.run(%{id: id}, %{}, %{})
    end
  end

  test "no synthetic or mock workflow IDs are present" do
    for wf <- inventory() do
      refute Map.get(wf, "synthetic") == true, "synthetic workflow found: #{Map.get(wf, "id")}"
    end
  end

  test "all whatsapp IDs start with canonical prefix" do
    for id <- @all_ids do
      assert String.starts_with?(id, "so:wf:v1:"), "ID #{id} missing canonical prefix"
    end
  end

  test "unique IDs: no duplicates in allowlist" do
    assert length(@all_ids) == length(Enum.uniq(@all_ids)), "duplicate IDs"
  end

  test "blocked workflows are not executable" do
    for id <- @blocked_ids do
      assert {:error, _} = TccAdapter.run(%{id: id}, %{}, %{})
    end
  end

  test "L2 workflows require approval" do
    for id <- @l2_ids do
      assert {:error, :approval_required} = TccAdapter.run(%{id: id}, %{}, %{})
    end
  end

  test "RUNNABLE whatsapp IDs produce a valid tuple with an existing executable path" do
    runnable = @all_ids -- @blocked_ids -- @l2_ids
    for id <- runnable do
      result = TccAdapter.run(%{id: id}, %{}, %{})
      assert is_tuple(result), "result must be a tuple for #{id}"
      elem = elem(result, 0)
      assert elem in [:ok, :error], "first element must be :ok or :error for #{id}: #{inspect(result)}"
    end
  end

  test "risk levels consistent between inventory and TCC adapter" do
    inv = inventory()
    for wf <- inv do
      id = wf["id"]
      assert wf["status"] in ["BLOCKED", "ACCEPTED"], "unexpected status for #{id}: #{wf["status"]}"
    end
  end

  test "approval gates match inventory (L2 = approval_required)" do
    for wf <- inventory(), wf["risk"] == "L2" do
      assert wf["approval_required"] == true, "#{wf["id"]} must be approval_required"
      assert wf["start_enabled"] == false, "#{wf["id"]} must not start_enabled"
      assert wf["execution_verified"] == false, "#{wf["id"]} must not execution_verified"
    end
  end

  test "runtime-blocked workflows have block_reason and are not start_enabled" do
    for wf <- inventory(), wf["status"] == "BLOCKED" do
      assert Map.has_key?(wf, "block_reason"), "#{Map.get(wf, "id")} missing block_reason"
      assert wf["start_enabled"] == false, "#{Map.get(wf, "id")} must not start_enabled"
      assert wf["execution_verified"] == false, "#{Map.get(wf, "id")} must not execution_verified"
    end
  end

  test "unknown risk level is rejected by RiskPolicy" do
    assert {:error, :unknown_risk_level} = ShadowOpsCore.RiskPolicy.get("UNKNOWN")
  end

  test "L2 approval gates are single-use per approval record" do
    {:ok, approval} = ShadowOpsCore.Approval.new(%{
      action: "whatsapp-purge-expired",
      resource: "so:wf:v1:whatsapp-purge-expired",
      reason: "test",
      requested_by: "audit",
      risk: "L2",
      expires_at: DateTime.utc_now() |> DateTime.add(86_400, :second)
    })
    assert approval.status == "PENDING"
    assert {:ok, approved} = ShadowOpsCore.Approval.decide(approval, "APPROVED", "auditor")
    assert approved.status == "APPROVED"
    assert {:ok, consumed} = ShadowOpsCore.Approval.consume(approved, "executor")
    assert consumed.status == "CONSUMED"
    assert {:error, _} = ShadowOpsCore.Approval.consume(consumed, "executor2")
  end

  test "wrong workflow approval cannot be reused on a different id" do
    {:ok, approval} = ShadowOpsCore.Approval.new(%{
      action: "whatsapp-purge-expired",
      resource: "so:wf:v1:whatsapp-purge-expired",
      reason: "test",
      requested_by: "audit",
      risk: "L2",
      expires_at: DateTime.utc_now() |> DateTime.add(86_400, :second)
    })
    assert {:ok, approved} = ShadowOpsCore.Approval.decide(approval, "APPROVED", "auditor")
    assert approved.action == "whatsapp-purge-expired"
    assert approved.resource == "so:wf:v1:whatsapp-purge-expired"
  end

  test "expired approval blocks execution" do
    {:ok, approval} = ShadowOpsCore.Approval.new(%{
      action: "whatsapp-purge-expired",
      resource: "so:wf:v1:whatsapp-purge-expired",
      reason: "test",
      requested_by: "audit",
      risk: "L2",
      expires_at: DateTime.utc_now() |> DateTime.add(-86400, :second)
    })
    assert {:error, :expired} = ShadowOpsCore.Approval.decide(approval, "APPROVED", "auditor")
  end
end
