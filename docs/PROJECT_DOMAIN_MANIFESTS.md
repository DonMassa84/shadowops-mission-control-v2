# Private project-domain manifests

ShadowOps reads normalized project summaries from local JSON files. These files are runtime data and must not be committed.

Default directory:

```text
~/.local/share/shadowops/domains/
```

Default files:

```text
finance.json
investigations.json
ihk.json
community.json
```

Environment overrides:

```text
SHADOWOPS_DOMAIN_DIR
SHADOWOPS_FINANCE_MANIFEST
SHADOWOPS_INVESTIGATIONS_MANIFEST
SHADOWOPS_IHK_MANIFEST
SHADOWOPS_COMMUNITY_MANIFEST
```

## Schema

```json
{
  "status": "READY",
  "health": "HEALTHY",
  "summary": "Short privacy-safe operational summary",
  "open_items": 3,
  "next_deadline": "2026-09-30",
  "updated_at": "2026-08-24T20:00:00+02:00",
  "classification": "PRIVATE_LOCAL"
}
```

Only these normalized summary fields are rendered by the project-domain UI. Raw transactions, case documents, messages, account identifiers, evidence files and other sensitive records must stay in their authoritative local source systems.

Missing files are shown as `NOT_CONFIGURED`; malformed JSON is shown as unavailable. ShadowOps does not infer missing values.
