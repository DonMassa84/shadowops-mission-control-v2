# Kali 4015 Security Acceptance — 472cbee

## Scope

This evidence record preserves the independent Kali acceptance results for the exact ShadowOps integration candidate:

- TESTED_HEAD: `472cbeea8900680ff59346b278dce7556ccc5f59`
- integration branch: `local/all-developments`
- acceptance port: `4015`
- Kali target path: `192.168.122.1:4015` via libvirt bridge
- production port `4013`: not mutated
- development port `4014`: not mutated

This evidence commit is intentionally stored on a separate evidence branch so the tested integration SHA remains immutable.

## GitHub-verified state

- `local/all-developments` remote HEAD = `472cbeea8900680ff59346b278dce7556ccc5f59`
- Commit message: `4015 acceptance bind: add SHADOWOPS_BIND_IP for libvirt/shadowlab bridge`
- Parent: `f4a61dc35a6afd2120e7630d5c7389f1bbdbfbb1`
- GitHub Hardening CI run #108 / run id `33142308564` is associated with the exact tested HEAD.

At the time this evidence record was created, CI #108 had already passed:

- dependency lock
- format
- compile with warnings as errors
- full test suite
- strict Credo on changed hardening code
- full-repository Credo baseline

Dialyzer baseline was still running; Sobelow, registry validation, workflow ID validation, Hex audit, diff check, production acceptance, prod compile and release build were still pending. Therefore this record certifies **4015/Kali acceptance**, not yet the final repository-wide release gate.

## Kali network acceptance

Reported from the Kali VM:

```text
22/tcp   open     ssh
4013/tcp filtered acl-manager
4014/tcp filtered taiclock
4015/tcp open     talarian-mcast1
```

Interpretation:

- `4013` remains inaccessible from Kali and remains production-protected.
- `4014` remains inaccessible from Kali.
- `4015` is intentionally reachable on the libvirt bridge.

## 4015 HTTP acceptance

```text
/                              HTTP=200 TIME=3.75s
/health                        HTTP=200 TIME=0.008s
/ready                         HTTP=200 TIME=0.020s
/workflows                     HTTP=200 TIME=0.196s
/approvals                     HTTP=200 TIME=0.002s
/audit                         HTTP=200 TIME=0.004s
/security                      HTTP=200 TIME=0.020s
/knowledge                     HTTP=200 TIME=2.02s
/api/health                    HTTP=200 TIME=0.008s
/api/ready                     HTTP=200 TIME=0.018s
/api/workflows                 HTTP=200 TIME=0.012s
/api/approvals                 HTTP=200 TIME=0.001s
/api/audit                     HTTP=200 TIME=0.005s
/api/security/status           HTTP=200 TIME=0.019s
```

Unknown route result:

```text
HTTP=404
```

Debug-disclosure probe:

```text
DEBUG_DISCLOSURE=NONE_OBSERVED
```

## Bind implementation

`config/runtime.exs` now uses an environment-gated bind contract:

- Production / 4013: loopback-only `127.0.0.1`
- Development / 4014: defaults to loopback-only `127.0.0.1`
- Acceptance / 4015: may use explicit `SHADOWOPS_BIND_IP`
- IPv4 input is validated
- Invalid or absent override falls back to loopback

Acceptance deployment used:

```text
SHADOWOPS_BIND_IP=192.168.122.1
PORT=4015
```

## Locally reported quality gates

```text
FORMAT=PASS
COMPILE=PASS
TESTS=PASS (106)
REGISTRY=PASS
WORKFLOW_IDS=PASS
HEX_AUDIT=PASS
DIFF_CHECK=PASS
```

These local results are preserved as operator/worker evidence. GitHub CI #108 remains the authoritative repository-wide CI attestation for the exact SHA.

## Acceptance result

```text
TESTED_HEAD=472cbeea8900680ff59346b278dce7556ccc5f59
REMOTE_HEAD_MATCH=YES
4013_MUTATION=NO
4014_MUTATION=NO
4015_LISTENER=PASS
4015_BIND_SCOPE=LIBVIRT_BRIDGE_ONLY
KALI_TO_4015=PASS
UNKNOWN_ROUTE_FAIL_CLOSED=PASS
DEBUG_DISCLOSURE=NONE_OBSERVED
4015_ACCEPTANCE=PASS
KALI_SECURITY_ACCEPTANCE=PASS
CRITICAL_BLOCKERS=NONE_FOR_4015_KALI_ACCEPTANCE
GLOBAL_HARDENING_CI=IN_PROGRESS_AT_EVIDENCE_CAPTURE
FINAL_RELEASE_ACCEPTANCE=PENDING_FULL_CI
```

## Governance

No merge, production deployment, force push or `4013` promotion is authorized by this evidence record.
