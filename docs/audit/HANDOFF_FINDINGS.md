# HANDOFF — Verifizierte Findings an Instance 1 / Instance 3

**Von:** INSTANCE 2 (INDEPENDENT_SAFE_AUDITOR), Safe Mode, 0 Verstöße
**Am:** 2026-10-08 07:55 CEST
**Basis-Commit:** `cbff00f` (`docs(audit): record verified recovery state`)
**Status aller Einträge:** OFFEN — der Auditor hat **nichts** davon behoben
**Grundregel:** Reparatur obliegt dem jeweiligen Owner; Instance 2 dokumentiert nur.

Wirkungsbereiche (Isolation):

- **Instance 1** = Ryzen Main Repair (`~/Projects/shadowops`, `~/.config/`, Systemd/Timer/Provider)
- **Instance 3** = i7 Worker / LLM Runtime (`~/Projects/shadowops-runtime-deploy`)

Beweisdateien liegen unter `docs/audit/evidence/`.

---

## Übergabetabelle

| ID | Sev | Owner | Status | Beweis |
|---|---|---|---|---|
| F-01 | MEDIUM | Inst 1/3 | OFFEN | `evidence/ollama-summary.txt` |
| F-02 | MEDIUM | Inst 1 | OFFEN | `evidence/opencode-status.txt`, `evidence/i7-connectivity.txt` |
| F-03 | MEDIUM | Inst 3 | OFFEN | `evidence/i7-connectivity.txt` |
| F-04 | MEDIUM | Inst 1 | OFFEN | `evidence/model-automation-summary.txt` |
| F-05 | LOW | Inst 1 | OFFEN | `evidence/systemd-summary.txt` |
| F-06 | LOW | Inst 1 | OFFEN | `evidence/ryzen-runtime-status.txt` |
| F-07 | LOW | Inst 3 | OFFEN | `evidence/worktree-summary.txt` |

---

## F-01 — Unzugeordneter automatischer Modell-Download (MEDIUM)

**Owner:** Instance 1 / Instance 3 (zur Klärung, wer es ausgelöst hat)

- **Befund:** Automatischer Ollama-Download 2026-10-08 **05:59:35–07:18:13 CEST**;
  Blob `sha256-a8cc1361f3145dc01f6d77c6c82c9116b9ffe3c97b34716fe20418455876c40e-partial`
  (5,6 G sichtbar, ~9,3 G apparent, unvollständig) auf `~/.ollama/models/blobs/`.
  Ergebnis: `connection reset by peer`, `max retries exceeded` → Download **fehlgeschlagen**.
- **Wirkung:** Widerspricht der Erwartung "keine automatischen Modell-Downloads", sofern es
  keine beabsichtigte Instanz-1/3-Aktion war. Modellzahl unverändert (29), Modell nicht
  registriert; unvollständiger Blob verbraucht Platz.
- **Ausgeschlossene Quellen (geprüft, kein `ollama pull` darin):**
  `shadow-opencode-model-sync`, `autoconfigure-all-opencode-llms.sh`, `discover-free-models.sh`.
  Einzige Texttreffer im System: `~/.local/bin/android_ssh_bridge.sh`,
  `~/Projects/shadowops-runtime-deploy/tools/shadowmaker-llm-node/install-i7-llm-stack.sh`
  (Vorhandensein ≠ Ausführung um 05:59).
- **Reproduktion:**
  ```bash
  grep -n 'download\|partial\|pull' ~/.ollama/logs/server.log | tail
  ls -la ~/.ollama/models/blobs/ | grep partial
  systemctl status shadow-opencode-model-sync shadowmaker-model-discovery
  ```
- **Vorgeschlagene Aktion (Owner):** Auslöser ermitteln (Journal/Cron/Timer um 05:59),
  ggf. partial-Blob nach Freigabe bereinigen (Löschfreigabe erforderlich — Auditor löscht nicht).

## F-02 — Provider `shadow-ollama-i7` von Ryzen aus nicht erreichbar (MEDIUM)

**Owner:** Instance 1

- **Befund:** `~/.config/opencode/opencode.json` → `shadow-ollama-i7.baseUrl =
  http://127.0.0.1:11437/v1`. Isolation korrekt (zeigt **nicht** auf 11434), aber auf Ryzen
  lauscht **nichts** auf 11437; i7 bindet 11437 nur an `127.0.0.1` (dort per socat OK).
  `GET http://127.0.0.1:11437/v1/models` von Ryzen → **Fehler/kein Listener**.
  Auch `10.42.0.44:11435` und `:11437` von Ryzen aus ohne Antwort.
- **Wirkung:** Jeder OpenCode-Aufruf über `shadow-ollama-i7` schlägt von Ryzen aus fehl.
- **Reproduktion:**
  ```bash
  curl -sS -m 3 http://127.0.0.1:11437/v1/models   # erwartet: Fehler
  ss -tlnp | grep -E '1143[57]'
  ```
- **Vorgeschlagene Aktion (Owner):** Lokalen Forward schaffen (socat/SSH-Tunnel/`Reverse`)
  ODER Provider-URL auf einen erreichbaren Endpunkt setzen — nach Freigabe durch Instance 1.
  Hinweis: es existiert bereits `socat TCP4-LISTEN:11436 → 10.36.26.21:11434` (Android-Bridge);
  11436 ist von hier ebenfalls nicht erreichbar → Bind-Adresse prüfen.

## F-03 — i7 `ollama.service` inaktiv trotz 29 Manifesten (MEDIUM)

**Owner:** Instance 3

- **Befund:** Auf `shadowserver-i7`: `systemctl is-active ollama` → **`inactive`**;
  `ollama list` → 29 Modelle; `GET http://127.0.0.1:11437/v1/models` (lokal auf i7) → **OK**;
  0 fehlgeschlagene System-Units; Branch `feat/i7-llm-runtime-stack-20261007` aktiv.
- **Wirkung:** Unklar, ob beabsichtigt (z. B. nur Proxy-Modus) oder Regression der
  LLM-Runtime-Arbeit. Modell-Inspektion funktioniert, der Daemon selbst läuft nicht.
- **Reproduktion (von Ryzen aus):**
  ```bash
  ssh shadowserver-i7 'systemctl is-active ollama; curl -sS -m3 localhost:11437/v1/models | head -c 200'
  ```
- **Vorgeschlagene Aktion (Owner):** Beabsichtigt vs. Regression feststellen; bei Regression
  Dienst gezielt hochfahren (Owner-Recht, nicht Auditor-Recht).

## F-04 — `model_cleanup.sh` KEEP-Liste inkonsistent (MEDIUM)

**Owner:** Instance 1

- **Befund:** `~/.local/bin/model_cleanup.sh` (tägliche `model-cleanup.timer`, next 2026-10-09 00:21):
  `KEEP_MODELS=("llama3:latest" "mistral:latest")`.
  - `mistral:latest` ist **nicht installiert** (tote Referenz)
  - der konfigurierte Default `qwen2.5-coder:14b` ist **nicht** in der Liste
  - Verhalten ist ausschließlich `ollama stop` (VRAM-Freigabe), **kein** `ollama rm`
    → verletzt "keine Modelllöschungen" **nicht**, würde aber den Default anhalten.
- **Wirkung:** Täglicher Cleanup stoppt den konfigurierten Default-Provider-Modell →
  mögliche Auswirkung auf OpenCode-Latenz/verfügbaren Kontext.
- **Reproduktion:**
  ```bash
  grep -n 'KEEP_MODELS\|ollama stop\|ollama rm' ~/.local/bin/model_cleanup.sh
  ollama list | grep -c mistral   # erwartet: 0
  ```
- **Vorgeschlagene Aktion (Owner):** KEEP-Liste um `qwen2.5-coder:14b` ergänzen und
  tote Referenz entfernen (Änderung erst nach Freigabe).

## F-05 — Obsoleter TinyFish-Timer nicht sauber deaktiviert (LOW)

**Owner:** Instance 1

- **Befund:** `tinyfish-monitor-GITHUB_WORKFLOW_MONITOR.service` = `failed`, `disabled`,
  letzter Lauf 07:20:34 exit 1 — **aber** der zugehörige `.timer` ist weiterhin **`enabled`**
  und startete den fehlschlagenden Dienst erneut (beobachtet 07:30:50). Dadurch bleibt
  `systemctl --user --failed` bei 1 Unit und `is-system-running` = `degraded`.
- **Wirkung:** Dauerhaft `degraded` trotz "dienst deaktiviert"; verdeckt ggf. neue Fehler im
  gleichen Anzeige-Slot.
- **Reproduktion:**
  ```bash
  systemctl --user list-timers | grep -i tinyfish
  systemctl --user status tinyfish-monitor-GITHUB_WORKFLOW_MONITOR.timer tinyfish-monitor-GITHUB_WORKFLOW_MONITOR.service
  ```
- **Vorgeschlagene Aktion (Owner):** Timer gezielt deaktivieren (`systemctl --user disable --now …timer`)
  — **MUTATING**, daher Owner-Aktion. Ausdrücklich gelistet als *accepted remaining action*.

## F-06 — Kein Swap auf Ryzen (LOW)

**Owner:** Instance 1

- **Befund:** `free -h` → Swap **0B**; RAM 31Gi total / 11Gi benutzt / 336Mi frei / 19Gi cache.
  Unverändert zum Referenzstand.
- **Wirkung:** Bei gleichzeitiger Last (Load 4.05, 29 Modelle, Ollama + OpenCode) besteht
  OOM-Risiko, da kein Swap-Puffer existiert.
- **Reproduktion:**
  ```bash
  free -h; swapon --show
  ```
- **Vorgeschlagene Aktion (Owner):** Swapfile/Documented option prüfen — Anlage ist
  MUTATING (Root) → nur nach expliziter Freigabe.

## F-07 — Uncommitted Productive Changes in `shadowops-runtime-deploy` (LOW)

**Owner:** Instance 3

- **Befund:** Branch `feat/i7-llm-runtime-stack-20261007`, Stand 2026-10-08:
  7 modified + 2 untracked, ausschließlich unter `tools/shadowmaker-data-indexer/`
  (`.gitignore`, `README.md`, `config/policy.json`, `docs/MANIFEST_SCHEMA.md`,
  `docs/PIPELINE.md`, `scripts/index_data.py` + `docs/LOCAL_DATA_INDEXER_IMPLEMENTATION.md`,
  `systemd/`).
- **Wirkung:** Offene Instanz-3-Arbeit; **nicht** durch diese Audit-Session verursacht
  (Auditor hat dort ausschließlich gelesen).
- **Reproduktion:**
  ```bash
  git -C ~/Projects/shadowops-runtime-deploy status --short
  git -C ~/Projects/shadowops-runtime-deploy branch --show-current
  ```
- **Vorgeschlagene Aktion (Owner):** Arbeit abschließen/committen oder bewusst belassen;
  beim nächsten Audit erneut prüfen.

---

## Annahme durch Owner (zum Abhaken)

- [ ] Instance 1 — F-01 Quelle geklärt
- [ ] Instance 1 — F-02 Endpunkt/Forward hergestellt
- [ ] Instance 1 — F-04 KEEP-Liste korrigiert (nach Freigabe)
- [ ] Instance 1 — F-05 TinyFish-Timer sauber deaktiviert
- [ ] Instance 1 — F-06 Swap-Entscheidung dokumentiert
- [ ] Instance 3 — F-03 i7-Dienstzustand bestätigt (beabsichtigt/regression)
- [ ] Instance 3 — F-07 Indexer-Arbeit committed/abgeschlossen

## Nicht enthalten (Bewusst)

- Keine Reparatur, keine Systemänderung, keine Löschung durch Instance 2
- Keine Secrets/Tokens in dieser Datei
- Kein Merge/Rebase/Force-Push; Audit-Branch nur vorwärts gepusht
