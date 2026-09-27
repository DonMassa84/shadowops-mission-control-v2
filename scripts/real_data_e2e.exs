# Executed inside the isolated production release by production_readiness.py.
# This exercises the existing allowlisted i7.status source; no fixture or external delivery.
alias ShadowOpsCore.{ApprovalStore, Audit, ExecutionTracker, GovernanceGate, RunStore}
assert! = fn value, label -> unless value, do: raise(label) end
state = System.fetch_env!("SHADOWOPS_STATE_DIR")
actor = "production-readiness"
workflow = "i7.healthcheck"
evidence_ref = "runtime:i7-healthcheck:" <> DateTime.to_iso8601(DateTime.utc_now())

{:ok, registry} = WorkflowEngine.Registry.load()
definition = registry["workflows"][workflow]
assert!.(definition["argv"] == [], "i7 workflow must retain fixed empty argv")
assert!.(File.regular?(definition["runtime"]), "real i7 runtime missing")

{:ok, pending} =
  ApprovalStore.create(%{
    requested_by: actor,
    action: "workflow.execute",
    resource: workflow,
    reason: "Authorized production readiness read-only i7 probe",
    evidence_ref: evidence_ref
  })

{:ok, approval} = ApprovalStore.approve(pending.id, actor)
# The operator's mission authorizes this read-only probe. This does not approve other actions.
context = %{approval_id: approval.id}
input = %{"evidence_ref" => evidence_ref, "trigger" => "production-readiness"}
{:ok, run} = ExecutionTracker.execute_workflow(workflow, actor, input, context)
assert!.(run.status == "SUCCESS" and run.exit_code == 0, "real i7 probe failed")
assert!.(String.starts_with?(run.result, "ONLINE ("), "real input is not an ONLINE i7 response")
{:ok, persisted} = RunStore.get(run.id)
assert!.(persisted.status == "SUCCESS", "run not persisted")
{:ok, consumed} = ApprovalStore.get(approval.id)
assert!.(consumed.status == "CONSUMED", "approval not consumed")

assert!.(
  match?(
    {:error, {:approval_required, _}},
    ExecutionTracker.execute_workflow(workflow, actor, input, context)
  ),
  "approval replay not blocked"
)

{:ok, privacy_pending} =
  ApprovalStore.create(%{
    requested_by: actor,
    action: "workflow.execute",
    resource: workflow,
    reason: "Negative privacy gate smoke",
    evidence_ref: evidence_ref
  })

{:ok, _} = ApprovalStore.approve(privacy_pending.id, actor)

{:error, {:privacy_gate_blocked, _}} =
  GovernanceGate.authorize(
    "workflow.execute",
    actor,
    workflow,
    %{password: "readiness-negative-test"},
    %{approval_id: privacy_pending.id}
  )

{:ok, %{status: "APPROVED"}} = ApprovalStore.get(privacy_pending.id)

{:ok, _} =
  GovernanceGate.authorize("workflow.execute", actor, workflow, %{}, %{
    approval_id: privacy_pending.id
  })

{:ok, %{valid: true} = audit} = Audit.verify()
rows = Audit.list(100_000)

assert!.(
  Enum.any?(
    rows,
    &(&1["action"] == "approval_consumed" and
        get_in(&1, ["metadata", "approval_id"]) == approval.id)
  ),
  "consumption audit missing"
)

assert!.(
  Enum.any?(rows, &(&1["action"] == "execution_finished" and &1["actor"] == actor)),
  "execution audit missing"
)

assert!.(
  Enum.any?(
    rows,
    &(&1["action"] == "run_finished" and get_in(&1, ["metadata", "run_id"]) == run.id)
  ),
  "run audit missing"
)

# Share only metadata, hashes and identifiers, never the i7 address or raw output.
report = %{
  timestamp: DateTime.to_iso8601(DateTime.utc_now()),
  synthetic: false,
  real_data: true,
  source: "existing i7-status live ICMP probe",
  input: "LIVE_NETWORK_RESPONSE",
  ingest: "existing fixed-argv workflow executor",
  normalization: "ResultEvaluator.workflow -> persisted SUCCESS and exit_code=0",
  workflow: workflow,
  run_id: run.id,
  approval_id: approval.id,
  policy: "GovernanceGate",
  approval: "CONSUMED",
  replay: "BLOCKED",
  privacy: "BLOCKED_BEFORE_CONSUMPTION",
  audit: audit,
  output_sha256: Base.encode16(:crypto.hash(:sha256, run.result), case: :lower),
  runtime_sha256:
    Base.encode16(:crypto.hash(:sha256, File.read!(definition["runtime"])), case: :lower),
  result: "PASS"
}

File.write!(Path.join(state, "real-data-e2e.json"), Jason.encode!(report, pretty: true) <> "\n")
IO.puts("REAL_DATA_E2E=PASS GOVERNANCE_SMOKE=PASS")
