# i7 LLM Node Changelog - 2026-10-08

## 2026-10-08T08:40:00+02:00 - CRITICAL FIXES APPLIED

**COMPONENT**=i7-llm-node
**PROBLEM**=Ollama port mismatch breaking tailnet inference; systemd service inactive; SSH tunnel blocking port
**ROOT_CAUSE**=Multiple conflicting Ollama port configurations; systemd service disabled; ollama-reverse-tunnel creating forward tunnel on 11434
**CHANGE**=Fixed Ollama port alignment, consolidated systemd drop-ins, disabled blocking tunnel, enabled systemd service
**FILES_CHANGED**=
- /etc/systemd/system/ollama.service.d/10-unified.conf (created)
- /etc/systemd/system/ollama.service.d/10-parked.conf (removed)
- /etc/systemd/system/ollama.service.d/20-nemo-gpu.conf (removed)
- /etc/systemd/system/ollama.service.d/90-env.conf (removed)
- /etc/systemd/system/ollama.service.d/shadow-i7.conf (removed)
- /etc/systemd/system/ollama.service (User=schattenmacher, Group=schattenmacher)
- /etc/systemd/system/shadow-ollama-tailnet-proxy.service (socat target: 11436→11434)
- /etc/systemd/system/ollama-reverse-tunnel.service (removed)
- /var/lib/shadowmaker-llm/ (chown schattenmacher:schattenmacher)
**BACKUP**=N/A (system config changes, no user data)
**TEST**=All Phase 11 tests re-run post-fix
**RESULT**=Tailnet inference WORKING; Ollama systemd service ACTIVE; Healthcheck operational
**ROLLBACK**=Restore drop-ins, re-enable ollama-reverse-tunnel, revert ollama.service user
**RISK**=MEDIUM (system service changes)

---

## 2026-10-08T07:30:00+02:00 - INITIAL AUDIT

**COMPONENT**=i7-llm-node
**PROBLEM**=No authoritative documentation of i7 LLM runtime state; port mismatch breaking tailnet inference
**ROOT_CAUSE**=Multiple conflicting Ollama port configurations; systemd service inactive; socat proxy targets wrong port
**CHANGE**=Complete live inventory and documentation of i7 LLM node state (Phase 1-12)
**FILES_CHANGED**=
- meta/i7-llm-node.json (created)
- meta/i7-models.json (created)
- docs/architecture/I7_LLM_NODE.md (created)
- docs/runbooks/I7_LLM_OPERATIONS.md (created)
- docs/recovery/I7_RECOVERY_2026-10-08.md (created)
- docs/testing/I7_RUNTIME_TESTS.md (created)
- docs/recovery/evidence/i7/system-info.txt (created)
- docs/recovery/evidence/i7/gpu-summary.txt (created)
- docs/recovery/evidence/i7/ollama-models.txt (created)
- docs/recovery/evidence/i7/service-summary.txt (created)
- docs/recovery/evidence/i7/port-summary.txt (created)
- docs/recovery/evidence/i7/healthcheck-status.json (created)
- docs/recovery/evidence/i7/boot-verification.txt (created)
**BACKUP**=N/A (read-only audit)
**TEST**=All Phase 11 tests executed and documented
**RESULT**=Audit complete; critical port mismatch identified; no production changes made
**ROLLBACK**=N/A
**RISK**=LOW (documentation only)
