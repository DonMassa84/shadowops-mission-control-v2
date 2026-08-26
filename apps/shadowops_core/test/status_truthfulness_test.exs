defmodule ShadowOpsCore.StatusTruthfulnessTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.{Status, Truthfulness}

  test "status classification is centralized and stable" do
    assert Status.normalize(:ready) == "READY"
    assert Status.positive?("READY")
    assert Status.degraded?("WARN")
    assert Status.failed?("CRITICAL")
    assert Status.unavailable?("NOT_CONFIGURED")

    assert Status.tone("READY") == "success"
    assert Status.tone("FAILED") == "error"
    assert Status.tone("DEGRADED") == "review"
    assert Status.tone("NOT_ASSESSED") == "muted"
    assert Status.tone("CUSTOM") == "neutral"
  end

  test "truthfulness requires positive state and evidenced non-synthetic reachability when fields exist" do
    assert Truthfulness.ready?(%{
             status: "READY",
             real_data: true,
             synthetic: false,
             reachable: true
           })

    refute Truthfulness.ready?(%{
             status: "READY",
             real_data: false,
             synthetic: false,
             reachable: true
           })

    refute Truthfulness.ready?(%{
             status: "READY",
             real_data: true,
             synthetic: true,
             reachable: true
           })

    refute Truthfulness.ready?(%{
             status: "READY",
             real_data: true,
             synthetic: false,
             reachable: false
           })
  end

  test "truthfulness supports atom or string keyed projections" do
    assert Truthfulness.ready?(%{"status" => "AVAILABLE", "real_data" => true})
    assert Truthfulness.normalize_ready_state(%{status: "NOT_CONFIGURED"}) == "NOT_CONFIGURED"

    assert {:error, :positive_without_real_data} =
             Truthfulness.validate(%{"status" => "READY", "real_data" => false})
  end
end
