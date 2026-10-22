# ShadowOps Federation: sichere lokale Übergabe (Entwurf, 22.10.2026)

## Zweck und Grenzen

Der Datensammler gehört **ausschließlich** in das **private** GitHub-Repo
`DonMassa84/shadowops`, vgl. dessen
`automation/federation/README.md`. Er erzeugt einen read-only Snapshot über
GitHub-Repositories, öffentliche FRS-Website und den privaten
IHK-Status `PRE_PROJECT`. Andere private Repositories können ohne separat
genehmigte Leseberechtigung nur `UNKNOWN` liefern.

Dieses öffentliche Mission-Control-V2-Repository enthält **nur** den
quelloffenen, datenfreien **lokalen Adapter**
`scripts/inspect_shadowops_federation.py`. Er lädt keine GitHub-Daten,
führt keine Programme aus, schreibt keine Dateien und gibt aus einem
bereits lokal vorliegenden Snapshot ausschließlich Mengen/Statuswerte
aus, keine Repo-Namen, privaten PR-Titel, URLs oder Nachweise.

## Betrieb nur auf der eigenen lokalen Maschine

Nach **separater Genehmigung und Merge** des privaten Collector-Draft-PR:

1. Im privaten Repo `shadowops` den geplanten GitHub-Action-Report
   `ShadowOps Federation (read-only)` ausführen/laufen lassen.
2. Das Artefakt `shadowops-federation-sanitized` **nur lokal** herunterladen
   und außerhalb dieses öffentlichen Repositories entpacken, zum Beispiel
   nach `/tmp/shadowops-federation-private/`.
3. Im lokalen Checkout von `shadowops-mission-control-v2` ausführen:

```bash
python3 scripts/inspect_shadowops_federation.py \
  --input /tmp/shadowops-federation-private/snapshot.json
```

Es erscheint **ein einzelnes, sanitiertes JSON auf stdout**, beispielsweise
mit `repository_total`, `repository_unknown`, `proposals_p0`
und `agent_execution_allowed=false`. Die Quelle wird weder verändert
noch weitergeleitet. Der Adapter verbietet ausdrücklich, eine private
`snapshot.json` innerhalb dieses Git-Checkouts zu verwenden.

**WICHTIG:** Dies ist noch **keine** automatische Einbindung in Phoenix,
keine aktualisierte Kiosk-Seite, keine Remote-Synchronisation und kein
betriebsbereiter lokaler Agenten-Runtime-Connector. Diese Komponenten
brauchen eigene Tests, Betriebsfreigaben und sicher getrennte private
Datentransporte. Bis dahin bleiben Ausführungen und alle
IHK-Produktions-/Realdatenaktionen gesperrt.

## Read-only Contract v1

Input (nur privates JSON):
- `schema_version=1`
- `policy.mode=READ_ONLY`; `local_agent_execution`, `auto_merge`,
  `auto_deploy`, `auto_email`, `project_execution_allowed` alle
  exakt `false`
- `ihk_boundary.release_allowed=false`
- `repositories` (max. 12), `websites` (max. 2),
  `handoff_proposals` (max. 100; jede `PROPOSAL_ONLY`,
  `requires_operator_approval=true`, `execution_permitted=false`)

Ausgabe (auch für eine zukünftige nur lokale UI geeignet):
- Nur aggregierte Zähler und ein nichtfreigebender IHK-Status
- `ihk=BLOCKED_UNVERIFIED` bei unbestätigter/abweichender Freigabelage
- `project_execution_allowed=false` und `agent_execution_allowed=false`
- Kein tatsächlicher Agenten-/Host-Status, keine Job-Ausführung

**Aktualität:** Der Adapter akzeptiert ausschließlich eine mit UTC-Offset versehene `generated_utc`-Zeit. Berichte, die älter als 48 Stunden oder mehr als 10 Minuten in der Zukunft liegen, werden **fail-closed** abgewiesen. Es wird kein Zeitstempel oder Rohbericht an die öffentliche Oberfläche ausgegeben.

Falls die private Quelle manipuliert ist, der Vertrag verletzt wird oder
ein lokaler Einlesefehler auftritt, bricht das Programm **fail-closed**
ohne private Details auszugeben ab.

## Offline-QA

```bash
python3 -m py_compile \
  scripts/inspect_shadowops_federation.py tests/test_federation_adapter.py
python3 -m unittest discover -s tests -p 'test_federation_adapter.py' -v
```

Die neue GitHub Action `federation-adapter-check.yml` prüft ausschließlich
synthetische Fixtures und erhält nur `contents: read`. Sie darf kein
`snapshot.json` downloaden oder in Actions-Artifacts hochladen.

Die bestehenden Elixir-/Security-CI-Fehler dieser öffentlichen Mission Control
werden durch diesen separaten Python-Vertragstest **nicht** behoben und
müssen unabhängig davon bearbeitet werden.

**Freigabegrenze:** Beide Draft-PRs bleiben ungemergt bis zur gesonderten
Entscheidung. `host_gate=HOLD`, `PRE_PROJECT` und alle IHK-Schutzflags
bleiben bestehen.
