# CI Failures auf Candidate-SHA

Candidate SHA: `fda310acff54106c988801d5b36f67bc0791f6e7`
Run: `33193759820` (push auf feature/shadowops-verified-app), 2026-08-28T17:14:31Z

## Resultat

`COMPLETED / FAILURE` – abgebrochen im Schritt **Format** (`mix format --check-formatted`).

- Checkout exact candidate: PASS
- Candidate identity: PASS
- Set up Python: PASS
- Verified App tests: PASS
- Inventory gate: PASS
- Set up Erlang/Elixir: PASS
- Install dependencies: PASS
- Dependency lock unchanged: PASS
- **Format: FAIL** (exit 1) → `apps/shadowops_core/lib/shadow_ops_core/adapters/tcc_adapter.ex`
- Compile / Full tests / 4013-Capture / Freeze / Whitespace: nicht ausgeführt (Abbruch)

## Klassifikation

`FORMAT`

Detaillierte Ursache: Zeile `id = if String.starts_with?(raw_id || "", "so:wf:v1:"), ... was
vor Commit-Datum 82acd2a tests passend war, aber tcc_adapter.ex wurde in `d2cb6e8`
(unformatted) eingespielt.

## Lokal reproduziert (Worktree, Elixir 1.20.3/OTP 28)

- `mix format --check-formatted` → FAIL mit exakt derselben Datei
- Nach `mix format` der Datei → PASS
- Es existiert KEIN weiterer Format-Defekt im Repo.

## Weitere beobachtete Failure-Klasse (latent, nicht CI-Check-blockierend analysiert)

Lokaler `mix test --seed 12345` nach Format-Fix:
- `shadowops_core`: 195/197 (2 Failures)
  1. `workflow_fabric_contract_test.exs:131` „registry adapters preserve existing IDs..."
     erwartet `tcc_status.state in ["DEGRADED","UNAVAILABLE"]`, erhält `"CONNECTED"`.
  2. `workflow_fabric_contract_test.exs:104` „TCC adapter discovers a real registry file..."
     erwartet `workflow.id == "fixture-observation"`, erhält `"so:wf:v1:fixture-observation"`.
- Ursache: Produkt-Adapter in `d2cb6e8` wurde bewusst auf kanonische `so:wf:v1:`-IDS +
  `CONNECTED`-Status gehoben; der Produkt-Contract-Test wurde nicht mit angepasst.
- Einordnung: **Produkt-Test-Drift** – außerhalb des CI-Fix-Scopes dieser Instanz.
  Kein CI-Datei-Fix nötig; Produktinstanz 1 muss den Contract-Test nachführen.

## Klassifikation je Run (fehlgeschlagene Runs im Limit 20)

| Run | SHA | Ergebnis | Klasse |
|-----|-----|----------|--------|
| 33193759820 | fda310a (HEAD) | failure | FORMAT |
| 33189874592 | 4e28dd8 | failure | FORMAT (folgt aus d2cb6e8) |
| 33189862887 | 7988e3e | failure | FORMAT |
| 33189851168 | 01cc377 | cancelled | CANCELLED (concurrency) |
| 33189839198 | da08bbb | cancelled | CANCELLED (concurrency) |
| 33189827771 | d86a97a | cancelled | CANCELLED (concurrency) |
| 33189810629 | 1826a37 | failure | FORMAT |
| 33189791904 | d133a69 | failure | FORMAT |
| 33189778605 | 11a0a87 | failure | FORMAT |
| 33189752919 | 75eaee7 | failure | FORMAT |
| 33189692641 | d2cb6e8 | failure | FORMAT |
| 33189660465 | f2f297c | failure | FORMAT |
| 33187345505 | 82acd2a | success | - (letzter grüner Run) |
| 33186966205 | d6fb815 | success | - |

## Wichtig

`CURRENT_HEAD_RUNS=1` (nur fda310a). Grüne Runs (82acd2a/d6fb815) gehören zu einem
früheren SHA und zählen **nicht** als Beweis für fda310a.
