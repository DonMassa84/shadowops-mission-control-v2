# i7 LLM Node Operations Runbook

## Verbindung

```bash
# SSH via Tailscale alias
ssh shadowserver-i7

# Direkte Tailscale IP
ssh schattenmacher@100.98.17.110
```

## Health Checks

### System Basic
```bash
ssh shadowserver-i7 'uptime'
ssh shadowserver-i7 'free -h'
ssh shadowserver-i7 'df -h /'
ssh shadowserver-i7 'tailscale ip -4'
```

### Ollama Service
```bash
# Service Status (systemd - currently inactive)
ssh shadowserver-i7 'systemctl status ollama --no-pager'

# User Process Status (actual running instance)
ssh shadowserver-i7 'ps aux | grep "ollama serve" | grep -v grep'

# Local API (via SSH tunnel port 11434)
ssh shadowserver-i7 'curl -fsS http://127.0.0.1:11434/api/tags'

# Actual Ollama Port (11436)
ssh shadowserver-i7 'curl -fsS http://127.0.0.1:11436/api/tags'

# Model List
ssh shadowserver-i7 'ollama list'

# Running Models
ssh shadowserver-i7 'ollama ps'
```

### Tailnet API Test (from Ryzen)
```bash
# Via Tailscale socat proxy (port 11434 on Tailscale IP)
curl --max-time 10 http://100.98.17.110:11434/api/tags

# Expected: Currently returns 403 or empty due to port mismatch
# Fix needed: socat should forward to 11436
```

### Healthcheck Services
```bash
# LLM Healthcheck Timer/Service
systemctl status shadow-llm-health.timer
systemctl status shadow-llm-health.service

# Compute Healthcheck
systemctl status shadow-compute-health.timer
systemctl status shadow-compute-health.service

# View Current Health State
ssh shadowserver-i7 'cat /var/lib/shadowmaker-llm/status.json'
```

### GPU / NVIDIA
```bash
ssh shadowserver-i7 'nvidia-smi'
ssh shadowserver-i7 'nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv'
```

### Failed Units
```bash
ssh shadowserver-i7 'systemctl --failed'
```

## Backend Selection

```bash
# Show selected backend
ssh shadowserver-i7 'shadow-llm-select'

# Output format:
# BACKEND=ollama
# OPENAI_BASE_URL=http://127.0.0.1:11434/v1
```

## Service Management

### Ollama
```bash
# Start user process manually (current method)
ssh shadowserver-i7 'nohup ollama serve > /tmp/ollama.log 2>&1 &'

# Enable systemd service (requires config fix first)
ssh shadowserver-i7 'sudo systemctl enable ollama'
ssh shadowserver-i7 'sudo systemctl start ollama'

# Check systemd drop-in conflicts
ssh shadowserver-i7 'systemctl cat ollama'
```

### Tailnet Proxy
```bash
# Restart socat proxy
ssh shadowserver-i7 'sudo systemctl restart shadow-ollama-tailnet-proxy'

# Check proxy config
ssh shadowserver-i7 'systemctl cat shadow-ollama-tailnet-proxy'

# Current: forwards to 127.0.0.1:11434 (SSH tunnel)
# Should: forward to 127.0.0.1:11436 (actual Ollama)
```

### Learning Kiosk
```bash
# Check status
ssh shadowserver-i7 'curl -fsS http://127.0.0.1:8765/health'

# Restart server
ssh shadowserver-i7 'pkill -f "learning-kiosk/app/server.py" && cd /home/schattenmacher/Projects/learning-kiosk && nohup python3 app/server.py > /tmp/kiosk.log 2>&1 &'

# Restart kiosk browser
ssh shadowserver-i7 'pkill -f "kiosk-browser.sh" && /home/schattenmacher/Projects/learning-kiosk/scripts/kiosk-browser.sh &'
```

## Logs

```bash
# Ollama user process logs
ssh shadowserver-i7 'tail -f /tmp/ollama.log'

# Healthcheck logs
ssh shadowserver-i7 'journalctl -u shadow-llm-health -f'

# Systemd journal for Ollama service
ssh shadowserver-i7 'journalctl -u ollama -f'

# Tailnet proxy logs
ssh shadowserver-i7 'journalctl -u shadow-ollama-tailnet-proxy -f'
```

## Model Management

```bash
# List models
ssh shadowserver-i7 'ollama list'

# Pull model
ssh shadowserver-i7 'ollama pull qwen2.5-coder-7b'

# Remove model
ssh shadowserver-i7 'ollama rm old-model:latest'

# Show model info
ssh shadowserver-i7 'ollama show qwen2.5-coder-7b'
```

## Common Issues & Fixes

### Ollama Not Accessible via Tailscale (403/empty)
**Cause**: socat proxy forwards to 11434, but Ollama runs on 11436
**Fix**: Update socat target port
```bash
ssh shadowserver-i7 'sudo sed -i "s/TCP:127.0.0.1:11434/TCP:127.0.0.1:11436/" /etc/systemd/system/shadow-ollama-tailnet-proxy.service'
ssh shadowserver-i7 'sudo systemctl daemon-reload && sudo systemctl restart shadow-ollama-tailnet-proxy'
```

### Ollama Service Won't Start (exit-code)
**Cause**: Conflicting systemd drop-ins (shadow-i7.conf forces 127.0.0.1:11434, nemo-gpu.conf forces 0.0.0.0:11434)
**Fix**: Consolidate drop-ins or disable conflicting ones
```bash
ssh shadowserver-i7 'sudo systemctl edit ollama --full'
# Remove shadow-i7.conf or align all to same port
```

### Healthcheck Shows Empty Models
**Cause**: Healthcheck queries 11434 (SSH tunnel), not 11436 (actual Ollama)
**Fix**: Update healthcheck script or fix port alignment

## Verification Checklist (Post-Change)

- [ ] `ssh shadowserver-i7 'uptime'` - System responsive
- [ ] `ssh shadowserver-i7 'tailscale ip -4'` - Tailscale connected
- [ ] `ssh shadowserver-i7 'nvidia-smi'` - GPU visible
- [ ] `ssh shadowserver-i7 'curl -fsS http://127.0.0.1:11436/api/tags'` - Ollama local API works
- [ ] `curl --max-time 10 http://100.98.17.110:11434/api/tags` - Tailnet API works
- [ ] `ssh shadowserver-i7 'shadow-llm-select'` - Backend selector returns ollama
- [ ] `ssh shadowserver-i7 'systemctl --failed'` - No failed units
- [ ] `ssh shadowserver-i7 'curl -fsS http://127.0.0.1:8765/health'` - Learning kiosk healthy
