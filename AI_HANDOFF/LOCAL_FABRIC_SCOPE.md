# ShadowOps Local Fabric Scope

Purpose: connect all useful local capabilities and evidence to ShadowOps without indiscriminate raw-data ingestion.

## Core path

`Local Source -> Discovery -> Authorization -> PrivacyGate -> Normalization -> Truthfulness -> Audit/Evidence -> Storage/Query -> UI`

No UI, workflow or adapter may bypass the governed path.

## Automatic discovery classes

### Host/runtime
- systemd user/system services
- Docker containers
- listening local ports and bounded process metadata
- CPU, memory, filesystem capacity, uptime and load
- GPU/NVIDIA availability and bounded device metadata when available
- network interface/reachability metadata without packet/content capture

### Compute/AI
- local Ollama endpoint and installed model metadata
- OpenCode availability/version
- ShadowOps stable/dev runtime identities
- optional i7 node reachability and declared capabilities

### Local code/projects
- Git repositories under explicitly configured discovery roots
- branch, HEAD, dirty/clean, remote name, last commit timestamp
- no repository file content is ingested merely because a repository is discovered

### Local knowledge/files
- explicitly configured roots such as Obsidian/knowledge/document roots
- file counts, types, timestamps and evidence hashes by default
- content indexing only through an explicit governed importer and classification policy

### ShadowOps local state
- import evidence manifests
- project/domain manifests
- audit/run/approval state
- backups and restore evidence
- workflow registries and local execution evidence

### Existing source adapters
- Gmail, Calendar, Drive, GitHub, ChatGPT project, WhatsApp, Telegram, Obsidian, Finance and i7 continue to use their source-specific truthfulness/evidence contracts.
- local presence of a file or credential does not automatically make a provider READY.

## Never auto-ingest

Do not automatically read, copy, index or publish raw contents from:
- SSH/private keys
- browser cookies/session stores/password databases
- keyrings/password managers
- OAuth/access/refresh tokens
- shell history containing secrets
- private message bodies merely because local application storage exists
- raw health/legal/financial documents without a scoped importer and PrivacyGate policy
- arbitrary home-directory content

These may only be handled by a separately approved, purpose-specific governed connector.

## Evidence semantics

Discovery and connectivity are separate from content availability.

Use explicit fields such as:
- `discovered`
- `reachable`
- `real_data`
- `synthetic`
- `content_ingested`
- `status`
- `health`
- `last_success_at`
- `record_count`
- `classification`
- `error_code`

`READY` requires real evidence appropriate to the source. Missing/unreadable/stale sources fail closed.

## Runtime isolation

- stable user runtime: port 4013, last-known-good immutable release
- development runtime: port 4014, isolated worktree/state
- local-fabric development must not interrupt stable 4013
- promotion remains a separate validated transaction with rollback ready

## Security boundary

Nothing private/raw is committed to GitHub. GitHub receives code, schemas, tests and sanitized bounded evidence only.

Operating rules:

`FINISH BEFORE EXPAND`

`STABLE WHILE DEVELOPING`

`LAST-KNOWN-GOOD ALWAYS AVAILABLE`
