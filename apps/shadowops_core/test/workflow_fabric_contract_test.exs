defmodule ShadowOpsCore.WorkflowFabricContractTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.Adapters.{
    AgentAdapter,
    GitHubActionsAdapter,
    OpenCodeAdapter,
    ScriptAdapter,
    TccAdapter
  }

  alias ShadowOpsCore.{
    CanonicalEvent,
    Correlation,
    EventBus,
    Evidence,
    Resource,
    WorkflowFabric
  }

  setup do
    EventBus.reset()
    :ok
  end

  test "canonical resources reject unsupported kinds and evidence-free READY claims" do
    base = %{
      id: "workflow:test",
      kind: "workflow",
      name: "Test",
      source: "registry",
      state: "DEGRADED",
      health: "FAIL",
      risk: "L2",
      synthetic: false,
      privacy: "metadata_only"
    }

    assert {:ok, %Resource{kind: "workflow"}} = Resource.new(base)
    assert {:error, {:invalid_field, :kind}} = Resource.new(%{base | kind: "unknown"})

    assert {:error, {:invalid_field, :provenance}} =
             Resource.new(%{base | state: "READY", health: "PASS"})

    verified =
      Map.merge(base, %{
        state: "READY",
        health: "PASS",
        provenance: "live registry probe",
        last_verified_at: "2026-08-23T19:00:00Z",
        evidence_ref: "evidence:test"
      })

    assert {:ok, %Resource{state: "READY", synthetic: false}} = Resource.new(verified)
  end

  test "canonical events validate privacy and correlation and reject raw metadata" do
    correlation_id = Correlation.generate()

    attrs = %{
      type: "workflow.started",
      source: "shadowops",
      resource_id: "workflow:repository_quality",
      correlation_id: correlation_id,
      privacy: "metadata_only",
      synthetic: false,
      metadata: %{run_id: "run_safe"}
    }

    assert {:ok, %CanonicalEvent{correlation_id: ^correlation_id}} = EventBus.publish(attrs)
    assert [%CanonicalEvent{}] = EventBus.list(%{correlation_id: correlation_id})

    assert {:error, :private_event_metadata} =
             CanonicalEvent.new(put_in(attrs, [:metadata], %{body: "private"}))

    assert {:error, :invalid_correlation_id} =
             CanonicalEvent.new(%{attrs | correlation_id: "not-canonical"})
  end

  test "evidence and trust score are derived from real gates and drift never remediates itself" do
    assert {:ok, evidence} =
             Evidence.build(
               "service:shadowops",
               "runtime_acceptance",
               [
                 %{gate: "systemd", result: "PASS", evidence_ref: "systemctl"},
                 %{gate: "listener", result: "PASS", evidence_ref: "tcp"},
                 %{gate: "health", result: "FAIL", evidence_ref: "/health"},
                 %{gate: "ready", result: "PASS", evidence_ref: "/ready"}
               ],
               "authorized local probes"
             )

    assert evidence.result == "FAIL"
    assert evidence.trust_score == 75

    assert %{drift: true, remediation: "POLICY_REQUIRED", risk: "L1"} =
             Evidence.drift("RUNNING", "STOPPED", "restart", "L1")

    assert %{drift: false, suggested_action: nil, remediation: "NONE"} =
             Evidence.drift("RUNNING", "RUNNING", "restart", "L1")
  end

  test "TCC adapter discovers a real registry file shape without inventing workflows" do
    path = Path.join(System.tmp_dir!(), "tcc-registry-#{System.unique_integer([:positive])}.json")

    File.write!(
      path,
      Jason.encode!(%{
        "schema_version" => 1,
        "workflows" => [
          %{
            "id" => "fixture-observation",
            "risk_level" => "L0",
            "executor" => %{"impl" => "shell", "command" => "/usr/bin/true"},
            "allowed_targets" => ["localhost"]
          }
        ]
      })
    )

    on_exit(fn -> File.rm(path) end)

    assert {:ok, [workflow]} = TccAdapter.discover(path: path)
    assert workflow.id == "fixture-observation"
    assert workflow.risk_level == "L0"
    assert workflow.synthetic == false
    assert TccAdapter.validate(workflow) == :ok
  end

  test "registry adapters preserve existing IDs and unresolved OpenCode state" do
    assert {:ok, scripts} = ScriptAdapter.discover()
    ids = Enum.map(scripts, & &1.id)
    assert "agent_state_sync" in ids
    assert "daily_digest" in ids
    assert "shadow_system_overnight_audit" in ids
    assert length(scripts) == 4

    available = Enum.count(scripts, &(ScriptAdapter.validate(&1) == :ok))

    expected_state =
      if available == length(scripts) and available > 0, do: "READY", else: "DEGRADED"

    assert %{state: ^expected_state, discovered: 4, available: ^available} =
             ScriptAdapter.status()

    assert %{state: "DEGRADED", reason: "workflow_ids_not_imported"} =
             OpenCodeAdapter.status()

    tcc_status = TccAdapter.status()
    assert tcc_status.state in ["DEGRADED", "UNAVAILABLE"]
    refute tcc_status.state == "READY"

    if tcc_status.state == "DEGRADED" do
      assert tcc_status.reason == "tcc_execution_not_connected"
    else
      assert tcc_status.source == "tcc"
      assert tcc_status.discovered == 0
    end

    assert %{state: "DEGRADED", reason: "agent_execution_not_connected"} =
             AgentAdapter.status()

    assert %{state: "DEGRADED", reason: "github_dispatch_not_connected"} =
             GitHubActionsAdapter.status()

    summary = WorkflowFabric.summary()
    assert summary.workflows_discovered >= 9
    assert summary.workflows_connected <= summary.workflows_discovered

    career_drift =
      Enum.find(summary.drift, &(&1.resource_id == "workflow:career_funnel_ihk"))

    assert career_drift.desired == "STOPPED"

    disabled = Enum.find(WorkflowFabric.workflows(), &(&1.id == "workflow:career_funnel_ihk"))
    assert disabled.state == "DEGRADED"
    assert is_binary(disabled.evidence_ref)

    github = Enum.find(WorkflowFabric.workflows(), &(&1.id == "workflow:repository_quality"))
    assert github.state == "DEGRADED"
    assert is_binary(github.evidence_ref)

    refute summary.status == "READY" and
             summary.workflows_connected < summary.workflows_discovered
  end
end
