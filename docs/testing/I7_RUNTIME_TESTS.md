# i7 LLM Runtime Tests - 2026-10-08

## Test Execution Summary
**Date**: 2026-10-08T08:40:00+02:00 (Post-Fix Verification)  
**Executor**: Instance 3 (I7_REPAIR_AND_WORKER_INTEGRATION)  
**Method**: Live SSH verification via `shadowserver-i7` alias

---

## Test Results (Post-Fix)

| Test ID | Test Name | Result | Details |
|---------|-----------|--------|---------|
| T01 | TAILSCALE | **PASS** | `tailscale ping shadowserver` → 1ms pong from 100.98.17.110, direct connection |
| T02 | SSH | **PASS** | `ssh shadowserver-i7` → successful connection, hostname verified |
| T03 | OLLAMA_SERVICE | **PASS** | `systemctl status ollama` → active (running), enabled, schattenmacher user |
| T04 | OLLAMA_LOCAL_API | **PASS** | `curl http://127.0.0.1:11434/api/tags` → 3 models returned |
| T05 | OLLAMA_TAILNET_API | **PASS** | `curl http://100.98.17.110:11434/api/tags` → 3 models returned |
| T06 | OLLAMA_TAILNET_INFERENCE | **PASS** | `curl http://100.98.17.110:11434/api/generate` → qwen2.5:3b responded |
| T07 | OLLAMA_MODELS | **PARTIAL** | `ollama list` → 29 models on disk; API returns 3 (manifest issue) |
| T08 | NVIDIA | **PASS** | `nvidia-smi` → GTX 1050 Ti, Driver 580.173.02, CUDA 13.0 |
| T09 | CUDA_TOOLKIT | **FAIL** | `command -v nvcc` → not found |
| T10 | LLAMA_CPP | **NOT_IMPLEMENTED** | Service enabled but inactive; binary not verified |
| T11 | LOCALAI | **NOT_IMPLEMENTED** | Service enabled but inactive; binary not verified |
| T12 | HEALTHCHECK | **PASS** | Script executes, writes JSON to /var/lib/shadowmaker-llm/status.json |
| T13 | HEALTH_TIMER | **PASS** | `shadow-llm-health.timer` active, triggers service every 5 min |
| T14 | BACKEND_SELECTOR | **PASS** | `shadow-llm-select` → BACKEND=ollama, OPENAI_BASE_URL=... |
| T15 | SYSTEMD_FAILED_UNITS | **PARTIAL** | `systemctl --failed` → 1 unit (system-recovery-peer, unrelated) |
| T16 | BOOT_AUTOSTART | **PASS** | ollama, shadow-ollama-tailnet-proxy, timers all enabled |
| T17 | REBOOT_TEST | **UNVERIFIED** | Not performed |

---

## Detailed Test Outputs (Post-Fix)

### T03 - OLLAMA_SERVICE
```bash
$ ssh shadowserver-i7 'systemctl status ollama --no-pager -l'
● ollama.service - Ollama Service
     Loaded: loaded (/etc/systemd/system/ollama.service; enabled; preset: enabled)
    Drop-In: /etc/systemd/system/ollama.service.d
             └─10-unified.conf
     Active: active (running) since Thu 2026-10-08 08:30:53 CEST
   Main PID: 289562 (ollama)
      Tasks: 14 (limit: 38314)
     Memory: 12.1M
```

### T04 - OLLAMA_LOCAL_API
```bash
$ ssh shadowserver-i7 'curl -fsS http://127.0.0.1:11434/api/tags'
{"models":[{"name":"qwen3:4b",...},{"name":"nomic-embed-text:latest",...},{"name":"qwen2.5:3b",...}]}
```

### T05 - OLLAMA_TAILNET_API
```bash
$ curl --max-time 10 http://100.98.17.110:11434/api/tags
{"models":[{"name":"qwen3:4b",...},{"name":"nomic-embed-text:latest",...},{"name":"qwen2.5:3b",...}]}
```

### T06 - OLLAMA_TAILNET_INFERENCE
```bash
$ curl -s --max-time 60 http://100.98.17.110:11434/api/generate -d '{"model": "qwen2.5:3b", "prompt": "Hi", "stream": false}' | jq -r '.response'
Hello! How can I assist you today?
```

### T07 - OLLAMA_MODELS
```bash
$ ssh shadowserver-i7 'ollama list'
NAME                            ID              SIZE      MODIFIED
shadowops-coder:16k             e9b77e3058e0    4.4 GB    2 hours ago
qwen3-embedding:4b              df5bd2e3c74c    2.5 GB    2 hours ago
qwen2.5-coder:14b               9ec8897f747e    9.0 GB    2 hours ago
... (29 total on disk)

$ ssh shadowserver-i7 'curl -fsS http://127.0.0.1:11434/api/tags | jq ".models | length"'
3
```

### T12 - HEALTHCHECK
```bash
$ ssh shadowserver-i7 '/usr/local/sbin/shadow-llm-health'
{
  "node": "shadowserver",
  "timestamp": "2026-10-08T08:34:24+02:00",
  "tailscale": {"ok": true, "ip": "100.98.17.110"},
  "gpu": {"ok": true, "name": "NVIDIA GeForce GTX 1050 Ti", "memory_mib": "4096"},
  "runtimes": {
    "ollama": {"ok": true, "base_url": "http://127.0.0.1:11434/v1"},
    "llamacpp": {"ok": false, "base_url": "http://127.0.0.1:8081/v1"},
    "localai": {"ok": false, "base_url": "http://127.0.0.1:8080/v1"}
  },
  "preferred_backend": "ollama",
  "ollama_models": ["qwen3:4b", "nomic-embed-text:latest", "qwen2.5:3b"],
  "failed_units": [],
  "root_free_bytes": 57068576768
}
```

### T14 - BACKEND_SELECTOR
```bash
$ ssh shadowserver-i7 'shadow-llm-select'
BACKEND=ollama
OPENAI_BASE_URL=http://127.0.0.1:11434/v1
```

### T15 - SYSTEMD_FAILED_UNITS
```bash
$ ssh shadowserver-i7 'systemctl --failed'
  UNIT                         LOAD   ACTIVE SUB    DESCRIPTION
● system-recovery-peer.service loaded failed failed System Recovery Mesh - Remote Peer Health Check
```

### T16 - BOOT_AUTOSTART
```bash
$ ssh shadowserver-i7 'systemctl is-enabled ollama shadow-ollama-tailnet-proxy shadow-llm-health.timer shadow-compute-health.timer'
enabled
enabled
enabled
enabled
```

---

## Fixes Applied (During This Session)

| Fix | Description | Verified |
|-----|-------------|----------|
| Socat proxy target | Changed from 11436 → 11434 | ✓ |
| Ollama systemd drop-ins | Consolidated 4 conflicting files into 10-unified.conf | ✓ |
| Ollama service user | Changed from ollama → schattenmacher | ✓ |
| ollama-reverse-tunnel | Stopped, disabled, removed (was blocking 11434) | ✓ |
| Healthcheck state dir | chown schattenmacher:schattenmacher | ✓ |
| Ollama user process | Stopped (replaced by systemd service) | ✓ |

---

## Legend
- **PASS**: Test executed successfully, expected result observed
- **FAIL**: Test executed, result indicates problem
- **NOT_IMPLEMENTED**: Component/service exists but not functional
- **UNVERIFIED**: Test not executed
- **PARTIAL**: Some aspects work, others don't
