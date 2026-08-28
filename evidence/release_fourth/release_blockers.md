# Release Blocker

Candidate SHA: `fda310acff54106c988801d5b36f67bc0791f6e7`
PR #36: mergeable=CONFLICTING, mergeStateStatus=DIRTY

## Blocker 1 – Merge-Konflikt opencode.jsonc (add/add)

- `main` fügte in `593df86` eine eigene opencode.jsonc (GitHub MCP) hinzu.
- `feature/shadowops-verified-app` fügte in dieser Linie eine eigene opencode.jsonc
  (lokale ShadowOps-Runtime/Provider) hinzu.
- `opencode.jsonc` existiert NICHT am Merge-Base `f3c88d4` → Git behandelt beide als
  „add/add". `git merge-tree --write-tree` meldet exakt diesen einen Konflikt.
- Notwendige Entscheidung: konfigurativ zusammenführen (GitHub MCP + lokale Provider)
  oder eine der beiden Versionen kanonisch wählen. Kein automatisierter Merge möglich.

## Blocker 2 – CI Rot auf aktuellem SHA (FORMAT)

- Einziger CheckRun auf fda310a: `Verified Product Gate` FAILURE (Run 33193759820),
  abgebrochen bei `mix format --check-formatted`.
- Betroffene Datei: `apps/shadowops_core/lib/shadow_ops_core/adapters/tcc_adapter.ex`.
- **PURA-Formatfix lokal angewendet und verifiziert**; ABER der GitHub-Run selbst bleibt
  rot, bis der Fix auf dem Branch liegt (kein Grün auf fda310a).

## Blocker 3 – Produkt-Test-Drift (nach Format-Fix persistierend)

- Nach Format-Fix: `mix test --seed 12345` → 2 Failures
  - `workflow_fabric_contract_test.exs:104` (ID: `so:wf:v1:`-Präfix)
  - `workflow_fabric_contract_test.exs:131` (Status `CONNECTED` vs `DEGRADED/UNAVAILABLE`)
- Ursache: Produkt-Adapter in `d2cb6e8` auf kanonische IDs + CONNECTED gehoben,
  Contract-Test nicht angepasst. Liegt außerhalb des CI-Fix-Scopes dieser Instanz.
- Wird vom Verified Product Gate im Schritt „Tests" weiterhin fehlschlagen, sobald FORMAT
  grün ist. → Produktinstanz 1 muss den Contract-Test nachführen.

## Kein Blocker, aber zu dokumentieren

- `main` ist ungeschützt (`required_status_checks` leer) → Merge-Heuristik verzichtet
  auf CI-Zwang; trotzdem ist Grün auf fda310a Voraussetzung für Release-Empfehlung.
- Hohe Divergenz (501/2) und 5 NOOP-Dokumentations-Commits (identischer Tree) dokumentiert;
  Historie bleibt unangetastet.
