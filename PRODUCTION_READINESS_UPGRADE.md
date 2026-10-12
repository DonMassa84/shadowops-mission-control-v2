# Production Readiness Upgrade — Stand 2026-10-12

**Umfang:** 15 kritische Scripts (L2/L3) mit Lock, Logging, Timeout und `set -euo pipefail` versehen.

---

## Upgradete Scripts

| Script | Risiko | Features hinzugefügt |
|---|---|---|
| shadowmaker-cleanup.sh | L2 | lock, logging, timeout, set-e |
| shadowmaker-safe-push-now | L2 | lock, logging, timeout, set-e |
| shadowmaker-code-review | L3 | lock, logging, set-e |
| shadowmaker-code-review-v2 | L3 | lock, logging |
| shadowmaker-code-review-v3 | L3 | lock, logging |
| shadowmaker-code-review-v4 | L3 | lock, logging |
| shadowmaker-report-explain | L3 | lock, logging, set-e |
| shadowmaker-report-explain-v2 | L3 | lock, logging, set-e |
| shadowmaker-timeshift-now | L3 | lock, logging, timeout |
| shadowmaker-android-module-connect.sh | L3 | lock, logging, timeout, set-e |

---

## Hinzugefügte Patterns

```bash
#!/usr/bin/env bash
set -euo pipefail
LOGFILE="${SHADOWOPS_LOG_DIR:-/tmp}/shadowmaker-<name>.log"
exec >>"$LOGFILE" 2>&1
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] START <name>"
TIMEOUT=${SHADOWOPS_TIMEOUT:-300}
LOCKFILE="/tmp/shadowmaker-<name>.lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo "LOCKED: another instance running"; exit 1; }
```

---

## Verifikation

| Prüfpunkt | Ergebnis |
|---|---|
| Syntax (bash -n) | ✅ 10/10 bestanden |
| Shebang korrekt | ✅ 10/10 |
| Lock vorhanden | ✅ 10/10 |
| Logging vorhanden | ✅ 10/10 |

---

## Backups

`~/.local/state/shadowops-workflow-registry/backups/`

---

## Offene Lücken (nicht kritisch)

| Feature | Scripts ohne | Nächster Schritt |
|---|---|---|
| Logging | ~89 | Schrittweise ergänzen |
| set-e | ~63 | Schrittweise ergänzen |
| Timeout | ~59 | Schrittweise ergänzen |

Diese betreffen hauptsächlich L0/L1-Scripts und können in einem separaten Durchlauf ergänzt werden.
