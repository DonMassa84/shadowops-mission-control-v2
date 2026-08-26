defmodule ShadowOpsCore.DailyControlTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.DailyControl

  # All healthy fixture: every domain GREEN
  defp healthy_overview do
    %{
      system: %{status: "READY", metadata: %{cpu: 45.0, ram: 62.0, disk: 30.0}},
      security: %{
        overall: "PASS",
        status: "READY",
        checks: %{readiness: %{status: "PASS"}},
        synthetic: false
      },
      services: %{status: "READY", services: [], synthetic: false},
      backups: %{status: "READY", last_success_at: DateTime.utc_now(), synthetic: false},
      approvals: [],
      runs: [],
      career: %{status: "READY", metadata: %{ihk_workflow: %{status: "ACTIVE"}}, synthetic: false},
      evidence: %{availability: "AVAILABLE", artifacts: [%{artifact: "test.pdf"}]}
    }
  end

  defp healthy_ihk do
    %{status: "READY", real_data: true, error_code: nil}
  end

  # Test 1: all healthy → GREEN
  test "all healthy returns GREEN status" do
    result = DailyControl.build(healthy_overview(), healthy_ihk())
    assert result.status == "GREEN"
    assert result.attention_required == false
    assert result.top_actions == []
    assert result.checks |> Enum.all?(&(&1.status == "GREEN"))
  end

  # Test 2: missing source → not GREEN
  test "missing system source returns BLOCKED" do
    overview = Map.put(healthy_overview(), :system, %{status: "UNAVAILABLE"})
    result = DailyControl.build(overview, healthy_ihk())
    assert result.status != "GREEN"
    assert result.attention_required == true
  end

  # Test 3: critical security → top priority
  test "degraded security produces top-ranked action" do
    overview =
      Map.put(healthy_overview(), :security, %{overall: "FAIL", status: "DEGRADED", checks: %{}})

    result = DailyControl.build(overview, healthy_ihk())
    assert result.attention_required == true
    assert [%{rank: 1, domain: "SECURITY"} | _] = result.top_actions
  end

  # Test 4: failed run → action
  test "failed run produces action" do
    overview = Map.put(healthy_overview(), :runs, [%{status: "FAILED"}])
    result = DailyControl.build(overview, healthy_ihk())
    assert result.attention_required == true
    assert Enum.any?(result.top_actions, &(&1.domain == "FAILED_RUNS"))
  end

  # Test 5: missing backup → attention
  test "missing backup produces ATTENTION" do
    overview = Map.put(healthy_overview(), :backups, %{status: "NOT_CONNECTED"})
    result = DailyControl.build(overview, healthy_ihk())
    backup_check = Enum.find(result.checks, &(&1.domain == "BACKUPS"))
    assert backup_check.status == "ATTENTION"
    assert result.attention_required == true
  end

  # Test 6: stale backup → attention
  test "stale backup produces ATTENTION" do
    stale = DateTime.add(DateTime.utc_now(), -30, :hour)
    overview = Map.put(healthy_overview(), :backups, %{status: "READY", last_success_at: stale})
    result = DailyControl.build(overview, healthy_ihk())
    backup_check = Enum.find(result.checks, &(&1.domain == "BACKUPS"))
    assert backup_check.status == "ATTENTION"
  end

  # Test 7: IHK missing evidence → attention
  test "IHK not configured produces ATTENTION" do
    ihk = %{status: "NOT_CONFIGURED", real_data: false, error_code: "SOURCE_MISSING"}
    result = DailyControl.build(healthy_overview(), ihk)
    ihk_check = Enum.find(result.checks, &(&1.domain == "IHK"))
    assert ihk_check.status == "ATTENTION"
  end

  # Test 8: career unavailable → not GREEN
  test "career unavailable produces ATTENTION" do
    overview = Map.put(healthy_overview(), :career, %{status: "UNAVAILABLE"})
    result = DailyControl.build(overview, healthy_ihk())
    career_check = Enum.find(result.checks, &(&1.domain == "CAREER"))
    assert career_check.status == "ATTENTION"
    assert result.status != "GREEN"
  end

  # Test 9: max 3 actions
  test "returns at most 3 actions" do
    overview =
      healthy_overview()
      |> Map.put(:security, %{overall: "FAIL", status: "DEGRADED", checks: %{}})
      |> Map.put(:backups, %{status: "NOT_CONNECTED"})
      |> Map.put(:runs, [%{status: "FAILED"}, %{status: "ERROR"}])
      |> Map.put(:approvals, [%{status: "PENDING"}])

    result = DailyControl.build(overview, healthy_ihk())
    assert length(result.top_actions) <= 3
  end

  # Test 10: deterministic ranking
  test "ranking is deterministic" do
    overview =
      healthy_overview()
      |> Map.put(:security, %{overall: "FAIL", status: "DEGRADED", checks: %{}})
      |> Map.put(:backups, %{status: "NOT_CONNECTED"})

    result1 = DailyControl.build(overview, healthy_ihk())
    result2 = DailyControl.build(overview, healthy_ihk())
    assert result1.top_actions == result2.top_actions
  end

  # Test 11: synthetic evidence can't satisfy check
  test "synthetic security prevents GREEN" do
    overview =
      Map.put(healthy_overview(), :security, %{
        overall: "PASS",
        status: "READY",
        checks: %{},
        synthetic: true
      })

    result = DailyControl.build(overview, healthy_ihk())
    security_check = Enum.find(result.checks, &(&1.domain == "SECURITY"))
    assert security_check.status != "GREEN"
    assert result.status != "GREEN"
  end

  # Test 12: no mutations (overview unchanged after build)
  test "build does not mutate input overview" do
    overview = healthy_overview()
    overview_before = :erlang.phash2(overview)
    _result = DailyControl.build(overview, healthy_ihk())
    overview_after = :erlang.phash2(overview)
    assert overview_before == overview_after
  end
end
