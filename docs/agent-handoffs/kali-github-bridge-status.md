# Kali GitHub Bridge and Capability Routing

STATUS=IMPLEMENTED_PENDING_CI
BRANCH=hardening/kali-bridge-convergence
BASE_INTEGRATION_HEAD=472cbeea8900680ff59346b278dce7556ccc5f59
PRODUCTION_MUTATION=NO
MERGE=NO
DEPLOY=NO
4013_MUTATION=NO

## Implemented

- `scripts/shadowops-kali-github-bridge.py`
  - GitHub Issue/PR comments -> bounded local Kali inbox
  - explicit standalone `KALI_TASK_BEGIN` / `KALI_TASK_END` schema only
  - allow-listed authors, capability names, repository scope and revision format
  - base64 task text decoded as data; never passed to a shell interpreter
  - append-only inbox/outbox records with SHA-256 integrity evidence
  - duplicate, stale revision, conflicting revision and revocation handling
  - L2/L3 tasks require a local single-use approval record and consume it atomically
  - isolated handoff to `scripts/shadowops-opencode-auto.sh`
  - bounded status-only publication back to the originating GitHub Issue/PR
  - recovery from persisted inbox/outbox state after restart
  - explicit transport blocks for 4013, systemd control, merge/push/rebase/force-push and production deploy instructions
- `ShadowOpsCore.KaliNode`
  - fixed SSH identity probe
  - fixed allow-listed `command -v` tool evidence probe
  - declared capabilities remain separate from `verified_capabilities`
  - tool probe failure leaves the node reachable but activates only `healthcheck`
- `ShadowOpsCore.NodeCapabilityRouter`
  - security/forensics preference: Kali -> Ryzen -> i7
  - AI preference: Ryzen -> i7 -> Kali
  - QA/repository preference: i7 -> Ryzen -> Kali
  - fallback requires the same independently verified capability
  - synthetic, unreachable, degraded or declaration-only nodes are not selectable
  - active assessment requires explicitly authorized target
  - L2/L3 requires consumed approval; evidence cannot lower the supplied effective risk
  - arbitrary shell/systemd/production-control capabilities are never routable

## GitHub task schema

A task comment must contain only this envelope:

```text
KALI_TASK_BEGIN
KALI_TASK_ID=KALI-EXAMPLE-1
KALI_TASK_REVISION=1
KALI_TASK_STATE=ACTIVE
KALI_TASK_RISK=L1
KALI_TASK_PHASE=security-review
KALI_TASK_CAPABILITY=security_audit
KALI_TASK_SCOPE=repository
KALI_TASK_PROMPT_B64=<base64 UTF-8 task text>
KALI_TASK_APPROVAL_ID=
KALI_TASK_END
```

Unknown fields are rejected. `KALI_TASK_STATE=REVOKED` creates a durable revocation record. A new execution after revocation requires an explicit higher revision.

## L2/L3 approval record

The bridge does not trust a GitHub task comment to self-approve. Before an L2/L3 task can run, an external governed process must create a local file in:

`$SHADOWOPS_STATE_DIR/kali/github-bridge/approvals/pending/<approval_id>.json`

with:

```json
{
  "status": "APPROVED",
  "approval_id": "approval-123",
  "task_id": "KALI-EXAMPLE-1",
  "revision": 1
}
```

The bridge atomically moves the record to `approvals/consumed/` before execution. Reuse is blocked.

## Kali commands

```bash
python3 scripts/shadowops-kali-github-bridge.py --self-test
python3 scripts/shadowops-kali-github-bridge.py --status
python3 scripts/shadowops-kali-github-bridge.py --receive
python3 scripts/shadowops-kali-github-bridge.py --run
python3 scripts/shadowops-kali-github-bridge.py --publish
python3 scripts/shadowops-kali-github-bridge.py --sync
```

Required runtime credentials remain outside the repository. `gh auth status` and `SHADOWOPS_CODER_MODEL` must be valid on Kali before live processing can pass.

## Acceptance gates

```text
KALI_GITHUB_READ=PASS
KALI_GITHUB_INBOX=PASS
KALI_TASK_RECEIVE=PASS
KALI_TASK_DEDUP=PASS
KALI_OPENCODE_HANDOFF=PASS
KALI_OUTBOX=PASS
KALI_GITHUB_STATUS_PUBLISH=PASS
KALI_RECOVERY=PASS
ARBITRARY_EXECUTION=BLOCKED
ARBITRARY_SYSTEMD=BLOCKED
4013_MUTATION=NO
FORMAT_RC=0
COMPILE_RC=0
TARGET_TEST_RC=0
FULL_TEST_RC=0
REMOTE_HEAD_MATCH=YES
READY_FOR_INTEGRATION=YES
```

Runtime acceptance on Kali must be tied to the final immutable integration SHA. Repository CI success alone is not sufficient evidence that Kali has current GitHub credentials, OpenCode model configuration or live network reachability.
