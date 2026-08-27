# Curated Workflow Runtime Correlation — 2026-08-27

## Zweck

Diese Entscheidung dokumentiert die Korrelation zwischen dem kuratierten lokalen Workflow-Bestand unter `openclaw_training/workflows`, dem breiten Discovery-Inventar und der kanonischen ShadowOps-Workflow-Registry.

Ziel ist, Runtime-Evidenz nicht mit kanonischer Workflow-Identität zu verwechseln und keine externen IDs ohne belegte Definition in die ShadowOps-Registry zu übernehmen.

## Beobachtete Runtime-ID

```text
external_runtime_id=ee9e2d05-c61e-a3c0-1844-e9c6537d8e4b
run_records=857
first_run_started_at=2026-08-13T17:31:34Z
first_run_finished_at=2026-08-13T17:33:01Z
last_run_started_at=2026-08-27T01:46:08Z
last_run_finished_at=2026-08-27T01:48:16Z
```

Die Abfrage gegen `workflow_runs.jsonl` liefert 857 historische Run-Datensätze für diese UUID.

Die direkte Statuszählung über `.status` ergab `null=857`. Frühere Safe-Views normalisierten den Ergebniswert über alternative Felder und zeigten SUCCESS. Daraus folgt: Das konkrete Statusfeldschema muss vor einer Status-Migration explizit normalisiert werden; `null` darf nicht stillschweigend als FAILURE oder SUCCESS interpretiert werden.

## Registry-Korrelation der UUID

Die gezielte Abfrage gegen `workflows.jsonl` lieferte keinen Definitionsdatensatz für:

```text
ee9e2d05-c61e-a3c0-1844-e9c6537d8e4b
```

Daher gilt bis zu einer expliziten Definitions-Evidenz:

```text
classification=ORPHAN_RUNTIME_ID
runtime_evidence=AVAILABLE
registry_definition=MISSING
canonical_shadowops_id=NONE
ready=false
verified_executable=false
```

857 historische Runs sind starke Ausführungsevidenz für eine externe Runtime-ID, aber kein Beweis für eine kanonische Workflow-Definition.

## Kuratierte Workflow-Kandidaten

### Mail → Telegram + Discord Priority Watch

Lokale Definition vorhanden.

Discovery-Artefakte:

```text
shadowmaker-mail-telegram-workflow.service = NEEDS_REVIEW
shadowmaker-mail-telegram-workflow.timer   = VALIDATED_STATIC
```

Vorläufige ShadowOps-Klassifikation:

```text
correlation=NEW_CANDIDATE
runtime_verified=false
execution_ready=false
```

Der dokumentierte Timer läuft morgens und abends. Die beobachtete orphan Runtime-ID lief dagegen wesentlich häufiger. Deshalb dürfen deren 857 Runs dem Mail-Workflow nicht zugerechnet werden.

### PDF Governance Regular Workflow

Lokale Definition vorhanden.

Discovery-Artefakte:

```text
shadowmaker-pdf-governance-workflow.service = VALIDATED_STATIC
shadowmaker-pdf-governance-workflow.timer   = VALIDATED_STATIC
```

Der Workflow ist fachlich mit `so:wf:v1:document-ai` verwandt, aber nicht identisch. Er umfasst zusätzlich Inventarisierung, Klassifikation, Priorisierung, Governance und Distribution.

Vorläufige Klassifikation:

```text
correlation=NEW_CANDIDATE
related_to=so:wf:v1:document-ai
duplicate=false
runtime_verified=false
```

### Repo Governance Regular Workflow

Lokale Definition vorhanden.

Discovery-Artefakte:

```text
shadowmaker-repo-governance-workflow.service = VALIDATED_STATIC
shadowmaker-repo-governance-workflow.timer   = VALIDATED_STATIC
```

Der Workflow ist fachlich mit `so:wf:v1:repository-quality` verwandt, aber nicht identisch. `repository-quality` ist ein kanonischer CI-/GitHub-Actions-Workflow; der lokale Repo-Governance-Workflow inventarisiert lokale Repositories read-only und erzeugt Governance-/Prioritätsartefakte.

Vorläufige Klassifikation:

```text
correlation=NEW_CANDIDATE
related_to=so:wf:v1:repository-quality
duplicate=false
read_only=true
runtime_verified=false
```

## Governance-Entscheidung

Es gilt:

```text
RUN HISTORY != REGISTRY DEFINITION
STATIC VALIDATION != RUNTIME VERIFICATION
RELATED != DUPLICATE
EXTERNAL UUID != CANONICAL SHADOWOPS ID
```

Die orphan UUID wird nicht in `workflow_ids.yaml` oder `workflow_registry_v2.yaml` als kanonischer Workflow übernommen, solange keine eindeutige Definition vorliegt.

Für externe Runtime-Quellen bleibt der zulässige Pfad:

```text
DISCOVERED
  -> STRUCTURE_VALIDATED
  -> RUNTIME_VERIFIED
  -> DEFINITION_CORRELATED
  -> REAL_DATA / EVIDENCE
  -> CONNECTED
  -> READY
```

Kein Schritt darf übersprungen werden.

## Nächster Verifikationsschritt

Die drei kuratierten Workflows sollen read-only gegen die realen systemd-Einheiten geprüft werden:

1. effektives `ExecStart` / Runner,
2. Timer-Zeitplan,
3. aktueller Unit-/Timer-Status,
4. letzte erfolgreiche systemd-Ausführung,
5. erzeugte Status-/Evidence-Artefakte,
6. Side-Effect-Grenzen,
7. Privacy-/Secret-Grenzen.

Erst dann kann ein Kandidat auf `RUNTIME_VERIFIED` angehoben werden.

## Sicherheitsregeln

- Keine unbekannte externe UUID als kanonische ID erfinden.
- Keine 857 Runs einem der drei kuratierten Workflows ohne Definition-Mapping zuschreiben.
- `VALIDATED_STATIC` ist kein `READY`.
- `NEEDS_REVIEW` bleibt fail-closed.
- Secret-Artefakte bleiben blockiert und werden nicht über API/UI exponiert.
- Lokale absolute Pfade sind interne Evidenz und dürfen nicht in öffentliche API-/UI-Projektionen gelangen.
- Keine zweite Workflow-Registry erzeugen; die bestehende ShadowOps-Registry bleibt kanonisch.

## Aktueller Entscheidungsstatus

```text
CURATED_WORKFLOWS=3
ORPHAN_RUNTIME_IDS_CONFIRMED=1
ORPHAN_RUNTIME_RUNS=857
MAIL=NEW_CANDIDATE
PDF_GOVERNANCE=NEW_CANDIDATE_RELATED_TO_DOCUMENT_AI
REPO_GOVERNANCE=NEW_CANDIDATE_RELATED_TO_REPOSITORY_QUALITY
RUNTIME_VERIFIED_CURATED=0
CANONICAL_REGISTRY_MUTATION=NO
FINAL_STATUS=CORRELATION_RECORDED_FAIL_CLOSED
```
