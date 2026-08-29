defmodule ShadowOpsCore.DailyControlTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.DailyControl

  # All healthy fixture: every domain GREEN
  defp healthy_overview do
    %{
      system: %{status: "READY", metadata: %{cpu: 45.0, memory: 62.0, disk: 30.0}},
      security: %{overall: "PASS", checks: %{firewall: "PASS", ssh: "PASS"}},
      services: %{status: "READY", records: [%{status: "READY"}, %{status: "HEALTHY"}]},
      backups: %{status: "READY", last_success_at: DateTime.utc_now()},
      approvals: %{status: "READY", records: []},
      runs: %{status: "READY", records: []},
      career: %{status: "READY", metadata: %{ihk_workflow: %{status: "ACTIVE"}}},
      evidence: %{
        status: "READY",
        real_data: true,
        synthetic: false,
        records: [%{synthetic: false}]
      }
    }
  end

  defp healthy_ihk do
    %{status: "READY", records: [%{kind: "IHK"}], synthetic: false}
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
    overview = Map.put(healthy_overview(), :security, %{overall: "DEGRADED", checks: %{}})
    result = DailyControl.build(overview, healthy_ihk())
    assert result.attention_required == true
    assert [%{rank: 1, domain: "SECURITY"} | _] = result.top_actions
  end

  # Test 4: failed run → action
  test "failed run produces action" do
    overview = put_in(healthy_overview(), [:runs, :records], [%{status: "FAILED"}])
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
  test "IHK with no records produces ATTENTION" do
    ihk = %{status: "READY", records: [], synthetic: false}
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
      |> Map.put(:security, %{overall: "DEGRADED", checks: %{}})
      |> Map.put(:backups, %{status: "NOT_CONNECTED"})
      |> put_in([:runs, :records], [%{status: "FAILED"}, %{status: "ERROR"}])
      |> put_in([:approvals, :records], [%{status: "PENDING"}])

    result = DailyControl.build(overview, healthy_ihk())
    assert length(result.top_actions) <= 3
  end

  # Test 10: deterministic ranking
  test "ranking is deterministic" do
    overview =
      healthy_overview()
      |> Map.put(:security, %{overall: "DEGRADED", checks: %{}})
      |> Map.put(:backups, %{status: "NOT_CONNECTED"})

    result1 = DailyControl.build(overview, healthy_ihk())
    result2 = DailyControl.build(overview, healthy_ihk())
    assert result1.top_actions == result2.top_actions
  end

  # Test 11: synthetic evidence can't satisfy check
  test "synthetic evidence prevents GREEN" do
    overview =
      Map.put(healthy_overview(), :evidence, %{
        status: "READY",
        real_data: true,
        synthetic: true,
        records: []
      })

    result = DailyControl.build(overview, healthy_ihk())
    evidence_check = Enum.find(result.checks, &(&1.domain == "EVIDENCE"))
    assert evidence_check.status != "GREEN"
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
