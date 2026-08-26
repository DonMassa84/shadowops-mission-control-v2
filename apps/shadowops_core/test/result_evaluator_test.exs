defmodule ShadowOpsCore.ResultEvaluatorTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.ResultEvaluator

  test "successful workflow receives deterministic full score" do
    evaluation = ResultEvaluator.workflow("verified result", 0)

    assert evaluation.verdict == "EXCELLENT"
    assert evaluation.score == 100
    assert Enum.all?(evaluation.checks, &(&1.status == "PASS"))
  end

  test "failed workflow cannot be promoted by a present result" do
    evaluation = ResultEvaluator.workflow("some output", 1)

    assert evaluation.score == 50
    assert evaluation.verdict == "CRITICAL"
    assert Enum.any?(evaluation.checks, &(&1.id == "execution_exit_code" and &1.status == "FAIL"))
  end

  test "service start evaluates observed active state" do
    evaluation =
      ResultEvaluator.service(
        "start",
        %{active_state: "inactive", pid: nil},
        %{active_state: "active", pid: 1234},
        :ok
      )

    assert evaluation.score == 100
    assert evaluation.verdict == "EXCELLENT"
  end

  test "service restart also verifies process replacement when both pids are measurable" do
    evaluation =
      ResultEvaluator.service(
        "restart",
        %{active_state: "active", pid: 100},
        %{active_state: "active", pid: 200},
        :ok
      )

    assert evaluation.score == 100
    assert Enum.any?(evaluation.checks, &(&1.id == "process_replaced" and &1.status == "PASS"))
  end

  test "blocked execution remains blocked with zero score" do
    evaluation = ResultEvaluator.blocked("service", :approval_required)

    assert evaluation.verdict == "BLOCKED"
    assert evaluation.score == 0
    assert hd(evaluation.checks).status == "FAIL"
  end
end
