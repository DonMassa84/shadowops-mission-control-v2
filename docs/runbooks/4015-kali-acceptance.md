# 4015 Kali Acceptance Runbook

This runbook defines the bounded integration/acceptance path between the Ryzen ShadowOps host and Kali `kali-2026`.

## Safety invariants

- 4015 is integration/acceptance only.
- 4013 production must not be stopped, restarted, rebound, deployed to or otherwise mutated.
- 4014 preview/runtime must not be stopped or mutated by this runbook.
- Never use broad process-name killing such as `pkill -f phx.server`.
- Stop only a process proven to own TCP/4015.
- Do not bind 4015 to `0.0.0.0` unless separately justified and explicitly approved.
- Prefer the Ryzen host address on the libvirt/shadowlab network reachable from Kali.
- Determine the bind address from actual interface/routing evidence; do not assume it.

## Phase 1 — Diagnose 4015 without broad mutation

```bash
set -euo pipefail

echo "=== 1. 4015 ONLY — CURRENT LISTENER ==="
ss -ltnp | grep ':4015' || true

echo
echo "=== 2. HOST INTERFACES ==="
ip -br addr
ip route

echo
echo "=== 3. FIND PHOENIX BIND CONFIG ==="
cd /tmp/shadowops-4015-current
grep -RniE \
  '127\.0\.0\.1|0\.0\.0\.0|http:|PHX_HOST|PORT|ip:' \
  config apps/shadowops_web/config 2>/dev/null | head -120 || true

echo
echo "=== 4. CURRENT 4015 LOG ==="
tail -100 /tmp/phx4015.log 2>/dev/null || true

echo
echo "=== 5. PROCESS HOLDING 4015 ==="
PIDS="$(lsof -tiTCP:4015 -sTCP:LISTEN 2>/dev/null || true)"
printf 'PIDS=%s\n' "$PIDS"

# Only terminate processes proven to own TCP/4015.
if [ -n "$PIDS" ]; then
  kill -TERM $PIDS
  sleep 3
fi

echo
echo "=== 6. VERIFY 4013/4014 UNTOUCHED ==="
ss -ltnp | grep -E ':(4013|4014)\b' || true

echo "4015_DIAGNOSTIC_COMPLETE"
```

## Phase 2 — Bind only to the acceptance network

From the Phase 1 evidence, determine:

```text
BIND_TARGET=<RYZEN-LIBVIRT-OR-SHADOWLAB-IP>
PORT=4015
```

For Kali NAT IP `192.168.122.238`, `192.168.122.1` may be the host-side libvirt bridge, but this value must be proven from `ip -br addr` and routing evidence before use.

If Phoenix is hard-coded to loopback, implement an environment-driven acceptance bind with this contract:

```text
Default bind: 127.0.0.1
4015 override: explicit SHADOWOPS_BIND_IP
Production behavior: unchanged and fail-closed
```

Do not make `0.0.0.0` the new default.

## Phase 3 — Detached 4015 start

Use a fully detached process so orchestration tools do not remain blocked on the child process:

```bash
cd /tmp/shadowops-4015-current

nohup setsid env \
  MIX_ENV=dev \
  PHX_SERVER=true \
  PORT=4015 \
  SHADOWOPS_BIND_IP="$BIND_TARGET" \
  mix phx.server \
  </dev/null >/tmp/phx4015.log 2>&1 &

printf 'START_PID=%s\n' "$!"

PASS=0
for i in $(seq 1 30); do
  if curl -fsS --max-time 2 \
       "http://${BIND_TARGET}:4015/health" >/dev/null; then
    echo "4015_LOCAL_HEALTH=PASS"
    PASS=1
    break
  fi
  sleep 1
done

if [ "$PASS" -ne 1 ]; then
  echo "4015_LOCAL_HEALTH=FAIL"
fi

ss -ltnp | grep ':4015' || true
tail -80 /tmp/phx4015.log
```

## Phase 4 — Kali network acceptance

From Kali:

```bash
curl -sS --max-time 5 \
  -o /dev/null \
  -w 'KALI_TO_4015 HTTP=%{http_code} TIME=%{time_total}s\n' \
  "http://<RYZEN-BRIDGE-IP>:4015/health"
```

Required network gate:

```text
4013_UNTOUCHED=YES
4014_UNTOUCHED=YES
4015_LISTENER=PASS
4015_BIND_SCOPE=LIBVIRT_OR_SHADOWLAB_ONLY
KALI_TO_4015=PASS
```

## Phase 5 — Exact-head HTTP acceptance

Only after the candidate SHA is frozen and the remote branch matches it, test these routes on 4015:

```text
/
/health
/ready
/workflows
/approvals
/audit
/security
/knowledge
/api/health
/api/ready
/api/workflows
/api/approvals
/api/audit
/api/security/status
```

Collect HTTP status and latency. The root UI must be browser-usable and must not time out.

## Phase 6 — Governance acceptance

Required:

```text
APPROVAL_SINGLE_USE=PASS
AUDIT_VERIFY=PASS
RISK_DOWNGRADE_BLOCKED=PASS
UNKNOWN_WORKFLOW_FAIL_CLOSED=PASS
PRIVACY_GATE=PASS
FALSE_READY=0
```

Do not weaken policy or tests to obtain PASS.

## Phase 7 — Independent Kali defensive security acceptance

Permitted bounded checks include:

- connectivity and expected-port verification,
- service exposure inventory,
- HTTP response/header review,
- TLS/DNS/SSH configuration inspection where relevant,
- unknown-route behavior,
- debug/stacktrace disclosure checks,
- passive/bounded application security checks,
- evidence hashing and timestamping.

Forbidden:

- credential attacks,
- exploit frameworks against non-lab systems,
- aggressive external scans,
- destructive network/firewall changes,
- production 4013 mutation.

## Final exact-head report

```text
TESTED_HEAD=
REMOTE_HEAD=
REMOTE_HEAD_MATCH=YES|NO
HEALTH_HTTP=
READY_HTTP=
ROOT_HTTP=
WORKFLOWS_HTTP=
APPROVALS_HTTP=
AUDIT_HTTP=
SECURITY_HTTP=
KNOWLEDGE_HTTP=
APPROVAL_SINGLE_USE=PASS|FAIL
AUDIT_VERIFY=PASS|FAIL
RISK_DOWNGRADE_BLOCKED=PASS|FAIL
UNKNOWN_WORKFLOW_FAIL_CLOSED=PASS|FAIL
PRIVACY_GATE=PASS|FAIL
4015_ACCEPTANCE=PASS|FAIL
KALI_SECURITY_ACCEPTANCE=PASS|FAIL|BLOCKED
CRITICAL_BLOCKERS=
FINAL_ACCEPTANCE=PASS|FAIL
4013_MUTATION=NO
```

After exact-head acceptance starts, do not create repository commits on the candidate branch. Persist final acceptance in Issue #27 so the tested SHA remains immutable.
