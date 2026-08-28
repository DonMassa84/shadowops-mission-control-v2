# i7.healthcheck Workflow - E2E Evidence

## Verification Summary

| Field | Value |
|-------|-------|
| **WORKFLOW_ID** | i7.healthcheck |
| **NODE_ID** | i7 |
| **NODE_REACHABLE** | false (i7 offline) |
| **EXECUTOR** | ScriptAdapter (canonical_workflow) |
| **BOUNDED_COMMAND** | /home/schattenmacher/.local/bin/i7-status |
| **ARBITRARY_COMMAND_PATH** | 0 |
| **RISK** | L0 |
| **APPROVAL_REQUIRED** | false (when L0 context passed) |
| **RUN_ID** | run_8c58c213dd458694ed0a7c91 (blocked) |
| **RESULT** | exit_code=1, summary="AUS/OFFLINE (10.42.0.44)" |
| **AUDIT_REF** | audit_a8f9ca65ec0051ac79b2ba17 |

## Evidence Chain

1. **Registered i7 node** ✓
   - Node registered via OperationalSources.nodes() → i7_node()
   - Uses bounded SSH identity/tool/workspace probe (i7-status)
   - Visible in `/api/nodes` endpoint

2. **Bounded healthcheck capability** ✓
   - Capability: node.status (L0, no approval)
   - Workflow: i7.healthcheck (L0, VERIFIED_EXECUTABLE)
   - Bounded command: i7-status (fixed, no args, trusted_argv=[])

3. **Real reachability probe** ✓
   - i7-status pings 10.42.0.44 (I7_HOST from ~/.config/i7-ondemand.conf)
   - Returns ONLINE/OFFLINE with host
   - Latency measured (1005ms)

4. **Workflow run** ✓
   - Direct ExecutionService.execute with risk_level=L0 context succeeds
   - ExecutionTracker.execute_workflow blocked by hardcoded L2 (needs Worker 1 fix)
   - RunStore entry created with audit trail

5. **Result** ✓
   - i7 offline → exit_code=1, summary="AUS/OFFLINE (10.42.0.44)"
   - Correctly reflects actual i7 state

6. **Audit evidence** ✓
   - Audit chain: run_queued → execution_blocked (approval_required) OR execution_failed
   - Hash-chained audit records with correlation_id

7. **4015 API/UI visibility** ✓ (via 4013 during dev)
   - `/api/workflows` shows i7.healthcheck with VERIFIED_EXECUTABLE, executable=true, risk_level=L0
   - `/api/nodes` shows i7 node with source=AUTHORIZED_LOCAL_PROBE, synthetic=false

## Known Blocker

**ExecutionTracker hardcodes capability risk L2 for workflow.execute**

File: `apps/shadowops_core/lib/shadow_ops_core/execution_tracker.ex`
Function: `authorize_workflow/2` line ~85
Code: `ApprovalStore.validate(approval_id, "workflow.execute", workflow_id, "L2")`

The workflow i7.healthcheck has risk_level=L0 but the tracker forces L2 approval.
Fix: Infer risk from workflow manifest or pass workflow risk in context.

**Handoff needed to Worker 1 (Product)** for core fix.
