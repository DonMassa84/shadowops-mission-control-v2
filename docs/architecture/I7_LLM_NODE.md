# Shadowserver i7 LLM Node

## Purpose
This document describes the architecture of the i7-based LLM worker node (shadowserver) in the ShadowOps distributed AI infrastructure. The i7 node serves as a **worker/fallback node** for GPU-accelerated inference, complementing the primary Ryzen host which has superior GPU resources (RTX 3060 12GB vs GTX 1050 Ti 4GB).

**Key Principle**: i7 = Worker/Fallback Node. Ryzen = Hauptsystem. i7 ist NICHT die kanonische Ryzen-Recovery-Instanz.

## Hardware
| Component | Specification |
|-----------|---------------|
| Hostname | shadowserver |
| CPU | Intel Core i7-3770 (4 cores / 8 threads, Ivy Bridge) |
| RAM | 31 GiB DDR3 |
| Swap | 4 GiB (swapfile) |
| GPU | NVIDIA GeForce GTX 1050 Ti 4GB VRAM (GP107) |
| NVIDIA Driver | 580.173.02 |
| CUDA Runtime | 13.0 |
| CUDA Toolkit | NOT INSTALLED (nvcc not available) |
| Storage | /dev/sdb2 116G (57G used), /dev/sda1 117G (93G used /mnt/data) |
| Network | Tailscale (100.98.17.110), LAN (10.42.0.44), libvirt networks |

## Network
- **Tailscale**: Connected, IP 100.98.17.110
- **LAN**: 10.42.0.44 (enp0s25)
- **libvirt networks**: Multiple virbr* bridges for VMs (10.70.10.0/24 through 10.70.40.0/24, 192.168.122.0/24)
- **WireGuard**: wg0 interface active

## Tailscale
- Mesh connectivity to Ryzen (100.86.67.56) verified via `tailscale ping`
- Used for inter-node LLM inference routing
- Ollama exposed on Tailscale via socat proxy on port 11434

## Runtime Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     shadowserver (i7)                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐    ┌─────────────────────────────────────┐   │
│  │  Tailscale   │───▶│  socat proxy (11434)                │   │
│  │  100.98.17.110│    │  shadow-ollama-tailnet-proxy      │   │
│  └──────────────┘    └───────────────┬─────────────────────┘   │
│                                      │                          │
│                                      ▼                          │
│                          ┌─────────────────────┐               │
│                          │  SSH Tunnel (11434) │               │
│                          │  (from Ryzen)       │               │
│                          └─────────────────────┘               │
│                                      │                          │
│                    ┌─────────────────┼─────────────────┐       │
│                    ▼                 ▼                 ▼       │
│           ┌─────────────┐    ┌─────────────┐    ┌─────────────┐ │
│           │   Ollama    │    │  llama.cpp  │    │  LocalAI    │ │
│           │  (PRIMARY)  │    │ (FALLBACK)  │    │ (OPTIONAL)  │ │
│           │  Port 11436 │    │  Port 8081  │    │  Port 8080  │ │
│           │  User proc  │    │  INACTIVE   │    │  INACTIVE   │ │
│           └─────────────┘    └─────────────┘    └─────────────┘ │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Health Monitoring                          │   │
│  │  shadow-llm-health.timer  →  shadow-llm-health.service  │   │
│  │  shadow-compute-health.timer → shadow-compute-health... │   │
│  │  State: /var/lib/shadowmaker-llm/status.json            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Learning Kiosk (Port 8765)                 │   │
│  │  Python HTTP server + Firefox kiosk mode                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Ollama
- **Version**: 0.35.1 (client warning: 0.33.2)
- **Installation**: /usr/local/bin/ollama
- **Service**: ollama.service (DISABLED, INACTIVE/DEAD, exit-code)
- **Actual Process**: Running as user `schattenmacher` PID 171321 on port 11436
- **Configured Port**: 11434 (via systemd drop-ins, but overridden by user env)
- **Models Directory**: /home/schattenmacher/.ollama/models (29 models)
- **GPU Acceleration**: CUDA via OLLAMA_LLM_LIBRARY=cuda_v12

**Critical Issue**: Port mismatch - Ollama user process listens on 11436, but:
- Systemd service configured for 11434
- socat tailnet proxy forwards to 11434
- SSH tunnel from Ryzen connects to 11434
- Healthcheck queries 11434 (returns empty models via SSH tunnel)

## llama.cpp
- **Service**: shadow-llamacpp.service (ENABLED, INACTIVE)
- **Endpoint**: http://127.0.0.1:8081/v1
- **Status**: NOT IMPLEMENTED - service exists but not running
- **Binary**: Not verified present

## LocalAI
- **Service**: shadow-localai.service (ENABLED, INACTIVE)
- **Endpoint**: http://127.0.0.1:8080/v1
- **Status**: NOT IMPLEMENTED - service exists but not running
- **Binary**: Not verified present

## Model Routing
The backend selector (`/usr/local/bin/shadow-llm-select`) reads from `/var/lib/shadowmaker-llm/status.json` and selects:
1. **ollama** (preferred) - if Ollama API responds on 127.0.0.1:11434
2. **llama.cpp** - if Ollama fails and llama.cpp responds on 8081
3. **localai** - if both above fail and LocalAI responds on 8080
4. **none** - if all fail

Currently: `preferred_backend: "ollama"` (via healthcheck on 11434 which hits SSH tunnel)

## ShadowOps Worker
- **Learning Kiosk**: Port 8765, Python server + Firefox kiosk
- **OpenCode Server**: Port 4098
- **ShadowOps Web**: Port 43283 (Tailscale IP only)
- **Uptime Kuma**: Port 3001 (localhost only)

## Health Monitoring
| Component | Service | Timer | Status |
|-----------|---------|-------|--------|
| LLM Health | shadow-llm-health.service | shadow-llm-health.timer | ENABLED, ACTIVE |
| Compute Health | shadow-compute-health.service | shadow-compute-health.timer | ENABLED, ACTIVE |
| Shadow Detect | shadow-detect.service | shadow-detect.timer | ENABLED, ACTIVE |
| Observability | shadow-observatory.service | shadow-observatory.timer | ENABLED, ACTIVE |
| Nightly Improvement | shadowmaker-nightly-improvement.service | shadowmaker-nightly-improvement.timer | ENABLED, ACTIVE |

Healthcheck script: `/usr/local/sbin/shadow-llm-health` → writes JSON to `/var/lib/shadowmaker-llm/status.json`

## Boot Sequence
1. systemd starts enabled services:
   - ollama-i7-local.service (enabled)
   - ollama-proxy.service (enabled)
   - shadow-llamacpp.service (enabled)
   - shadow-localai.service (enabled)
   - shadow-ollama-tailnet-proxy.service (enabled) ✓ RUNNING
   - shadow-vm-autostart.service (enabled)
   - shadowops-i7-learning-display.service (enabled)
2. Timers start periodic healthchecks
3. User `schattenmacher` auto-login starts Ollama user process on port 11436
4. Learning kiosk Python server starts on port 8765
5. Firefox kiosk launches pointing to learning kiosk

## Security Boundaries
- **No public LLM ports**: Ollama only on localhost (11436) and Tailscale (11434 via socat)
- **Tailnet only**: All inter-node communication via Tailscale mesh
- **No secrets in repo**: Verified - no API keys, tokens, or private keys in repository
- **dnsmasq**: ACTIVE (provides local DNS/DHCP for libvirt VMs)
- **User services**: Run as `schattenmacher` user, not root

## Main Host Integration (Ryzen)
- **Ryzen Role**: Primary GPU inference host (RTX 3060 12GB)
- **i7 Role**: Fallback/worker, 24/7 infrastructure (Uptime Kuma, monitoring)
- **Communication**: Tailscale mesh (100.86.67.56 ↔ 100.98.17.110)
- **Inference Routing**: Ryzen can route to i7 via Tailscale if needed
- **Shared Storage**: /mnt/ryzen-data (SSHFS from Ryzen 1.7T)

## Failure Modes
| Scenario | Impact | Detection | Recovery |
|----------|--------|-----------|----------|
| Ollama user process dies | No local inference | Healthcheck (ollama=false) | Restart user process or enable ollama.service |
| socat proxy fails | No tailnet access | Healthcheck (tailscale=false) | Restart shadow-ollama-tailnet-proxy |
| GPU driver issue | No GPU acceleration | nvidia-smi fails, healthcheck gpu=false | Reinstall NVIDIA driver |
| Tailscale down | No inter-node communication | tailscale ping fails | Restart tailscaled |
| Port mismatch (11434 vs 11436) | Tailnet proxy returns 403/empty | curl 100.98.17.110:11434/api/tags fails | Fix socat target port to 11436 |

## Recovery Path
1. **Quick**: Restart healthcheck timer → `systemctl restart shadow-llm-health.timer`
2. **Ollama**: Start user process manually or fix systemd service config → `ollama serve`
3. **Port Fix**: Update socat proxy to target 11436, or align Ollama to 11434
4. **Full**: Reboot i7 → verify boot sequence (see Phase 14)

## Known Limits
- **VRAM**: 4GB limits model size (max ~7B Q4 quantized)
- **No CUDA Toolkit**: Cannot compile llama.cpp with CUDA; runtime only
- **CPU**: i7-3770 (2012) - slow for CPU-only inference
- **Ollama Service Inactive**: Relies on user auto-login process (fragile)
- **Port Conflict**: SSH tunnel occupies 11434, blocking systemd Ollama
- **Model Count**: 29 models consume ~80GB disk in /home/schattenmacher/.ollama/models

## Audit Status
- **Last Audit**: 2026-10-08T07:30:00+02:00
- **Auditor**: Instance 3 (I7_REPAIR_AND_WORKER_INTEGRATION)
- **Verification**: All components live-verified via SSH except where marked UNVERIFIED
