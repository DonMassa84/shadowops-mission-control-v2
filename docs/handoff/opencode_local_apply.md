# OpenCode Local Apply — ShadowOps Mission Control V2

Ziel: Den aktuellen GitHub-Stand von `feat/mission-control-v2` lokal **verlustfrei** übernehmen, validieren und auf einem isolierten Testport starten, damit die Anwendung angesehen werden kann.

## Harte Sicherheitsregeln

- Repository: `/home/schattenmacher/Projects/shadowops-mission-control-v2`
- Zielbranch: `feat/mission-control-v2`
- `main` nicht verändern.
- Keine produktiven Deployments auslösen.
- `shadowops-phoenix.service` auf Port 4013 nicht stoppen, restarten oder ersetzen.
- Kein `git reset --hard`, kein `git clean -fd`, kein Force-Push.
- Vor jedem Branchwechsel lokale Änderungen und untracked Dateien sichern.
- Keine Secrets ausgeben oder committen.
- `SHADOWOPS_START_PERSISTENCE=false` für die lokale Vorschau beibehalten.
- Falls ein Check fehlschlägt: Ursache zeigen; nicht durch Löschen/Überschreiben lokaler Daten "reparieren".

## Auftrag an OpenCode

Arbeite autonom bis zur lokalen Vorschau. Führe diese Schritte aus:

1. Wechsle nach `/home/schattenmacher/Projects/shadowops-mission-control-v2` und erfasse:
   - `git status --short`
   - aktuellen Branch
   - `git rev-parse HEAD`
   - `git remote -v`

2. Falls der Worktree Änderungen enthält, lege unter
   `~/.local/state/shadowops/backups/mission-v2-pre-apply-<timestamp>/`
   eine verlustfreie Sicherung an:
   - `git status --short`
   - `git diff`
   - `git diff --cached`
   - Kopie aller untracked Dateien unter Beibehaltung der relativen Pfade.
   Danach nichts verwerfen.

3. Hole ausschließlich den Zielstand:
   ```bash
   git fetch origin feat/mission-control-v2
   ```

4. Wechsle sicher auf den V2-Branch:
   - existiert er lokal: `git switch feat/mission-control-v2`
   - sonst: `git switch -c feat/mission-control-v2 --track origin/feat/mission-control-v2`
   - anschließend nur Fast-Forward: `git merge --ff-only origin/feat/mission-control-v2`

   Wenn wegen lokaler Änderungen kein sicherer Wechsel möglich ist, verwende einen **neuen isolierten Worktree** statt Änderungen zu verwerfen, z. B.:
   ```bash
   git worktree add /tmp/shadowops-mission-v2 origin/feat/mission-control-v2
   ```
   Arbeite dann dort weiter.

5. Beweise Source-Parität:
   ```bash
   git rev-parse HEAD
   git rev-parse origin/feat/mission-control-v2
   git status --short
   ```
   HEAD muss dem Remote-Branch entsprechen. Keine lokalen Source-Patches erzeugen, nur um Parität zu behaupten.

6. Installiere/aktualisiere Abhängigkeiten und führe die Code-Gates aus:
   ```bash
   MIX_ENV=test mix deps.get
   MIX_ENV=test mix format --check-formatted
   MIX_ENV=test mix compile --warnings-as-errors
   SHADOWOPS_START_PERSISTENCE=false MIX_ENV=test mix test --seed 12345
   ```

7. Führe zusätzlich aus und protokolliere das Ergebnis, aber ändere keinen Altcode nur zum kosmetischen Silencen bestehender Findings:
   ```bash
   MIX_ENV=test mix credo --strict
   MIX_ENV=test mix dialyzer
   MIX_ENV=test mix sobelow --exit
   MIX_ENV=test mix shadowops.registry validate
   MIX_ENV=test mix shadowops.workflow_ids.validate
   MIX_ENV=test mix hex.audit
   git diff --check
   ```
   Falls Credo/Dialyzer/Sobelow wegen bereits vorhandener Baseline-Probleme scheitern, die konkreten Findings nennen und sauber von neuen V2-Regressionen trennen.

8. Starte die Anwendung **nicht** auf 4013. Suche zuerst einen freien Preview-Port ab 14014:
   ```bash
   PREVIEW_PORT=14014
   while ss -ltn | grep -q ":${PREVIEW_PORT} "; do PREVIEW_PORT=$((PREVIEW_PORT+1)); done
   echo "PREVIEW_PORT=$PREVIEW_PORT"
   ```

9. Starte eine isolierte lokale Preview mit Persistence aus:
   ```bash
   mkdir -p ~/.local/state/shadowops/mission-v2-preview
   LOG=~/.local/state/shadowops/mission-v2-preview/server.log
   PIDFILE=~/.local/state/shadowops/mission-v2-preview/server.pid

   PORT="$PREVIEW_PORT" \
   SHADOWOPS_START_PERSISTENCE=false \
   MIX_ENV=dev \
   nohup mix phx.server >"$LOG" 2>&1 &
   echo $! >"$PIDFILE"
   ```

10. Warte kurz und prüfe mindestens:
    ```bash
    curl -fsS "http://127.0.0.1:${PREVIEW_PORT}/health"
    curl -fsS "http://127.0.0.1:${PREVIEW_PORT}/ready"
    curl -I "http://127.0.0.1:${PREVIEW_PORT}/"
    curl -I "http://127.0.0.1:${PREVIEW_PORT}/projects"
    curl -I "http://127.0.0.1:${PREVIEW_PORT}/workflows"
    curl -I "http://127.0.0.1:${PREVIEW_PORT}/infrastructure"
    curl -I "http://127.0.0.1:${PREVIEW_PORT}/security"
    curl -I "http://127.0.0.1:${PREVIEW_PORT}/audit"
    ```

11. Wenn eine grafische Sitzung vorhanden ist, öffne die Preview ohne den bestehenden 4013-Dienst zu verändern:
    ```bash
    xdg-open "http://127.0.0.1:${PREVIEW_PORT}/" >/dev/null 2>&1 || true
    ```

12. Gib am Ende exakt diese Abschlussdaten aus:
    - `LOCAL_BRANCH=`
    - `LOCAL_HEAD=`
    - `REMOTE_HEAD=`
    - `SOURCE_PARITY=PASS|FAIL`
    - `FORMAT=PASS|FAIL`
    - `COMPILE=PASS|FAIL`
    - Testzahlen pro Umbrella-App
    - `CREDO=PASS|FAIL`
    - `DIALYZER=PASS|FAIL`
    - `SOBELOW=PASS|FAIL`
    - `REGISTRY=PASS|FAIL`
    - `WORKFLOW_IDS=PASS|FAIL`
    - `HEX_AUDIT=PASS|FAIL`
    - `PREVIEW_PORT=`
    - `PREVIEW_URL=http://127.0.0.1:<port>/`
    - `PREVIEW_PID=`
    - `PREVIEW_LOG=`
    - `PRODUCTION_4013_TOUCHED=NO`
    - kurze Liste der sichtbar veränderten UI-/Governance-Bereiche.

## Erwartete sichtbare Änderungen

Beim Vergleich mit dem älteren Stand besonders prüfen:

- überarbeitetes Mission-Control-Dark-UI und responsive Shell,
- Project-Domain-/Federation-Sichten,
- Workflow-/Run-/Service-/Node-Operationsflächen,
- Security/Approvals/Audit/Evidence,
- i7-Display-Sicht,
- fail-visible `NOT_CONFIGURED`/`UNKNOWN` statt erfundener grüner Zustände,
- actor-basiertes Hammer-Rate-Limiting auf sensiblen Control-Plane-Write-Routen,
- Auditierung der Rate-Limit-Entscheidungen,
- Commanded/EventStore-Entscheidungsdokument unter `docs/decisions/commanded_eventstore_comparison.md`.

Die lokale Preview ist eine Inspektionsinstanz, kein Produktionsdeployment.