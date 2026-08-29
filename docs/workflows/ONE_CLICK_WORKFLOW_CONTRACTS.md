# One-Click Workflow Contracts (Preparation)

**Status:** Preparation / Contract Design only. No implementation yet.

All five workflows share one canonical result contract. Each workflow section
adds its domain-specific inputs, checks and ranking rules.

## Canonical output contract

Every workflow (later) returns:

```elixir
%{
  workflow_id: "shadowops.<name>",
  status: "GREEN" | "ATTENTION" | "BLOCKED" | "UNAVAILABLE",
  severity: "INFO" | "LOW" | "MEDIUM" | "HIGH" | "CRITICAL",
  summary: "...",
  attention_required: true | false,
  checks: [%{name: "...", status: "...", detail: "..."}],
  next_actions: [%{...}],
  evidence: [%{...}],
  source_status: [%{source: "...", status: "..."}],
  synthetic: false,
  generated_at: "ISO8601"
}
```

### Hard rules

- No fake values; no hard-coded successes.
- `UNAVAILABLE` source ⇒ workflow `status = "UNAVAILABLE"`.
- Missing data is **never** interpreted as `GREEN`.
- `synthetic: true` MUST NOT count as real evidence.
- `attention_required` is derived from checks, not assumed.

## 1. `daily_control`

**Purpose:** one click produces the daily overall situation.

**Later collects:** SYSTEM, SECURITY, RELEASE, CAREER, IHK, BACKUP,
APPROVALS, FAILED JOBS. In this phase only sources are mapped.

**Additional output:** `top_actions` — ranked list, maximum 3:

```elixir
top_actions: [
  %{rank: 1, workflow_id: "...", domain: "...", text: "...", severity: "..."},
  %{rank: 2, ...},
  %{rank: 3, ...}
]
```

**Ranking criteria (prepared):** impact, urgency, success_probability,
strategic_alignment, effort, evidence_confidence.

**Default mode:** read-only. **Risk:** L0 / L1.

## 2. `system_doctor`

**Purpose:** read-only diagnosis first.

**Sources to reuse:** failed systemd units (`RuntimeSources.services/0`),
service runtime classification, disk + inode usage, RAM, swap, CPU/load,
temperatures (`OperationalSources` helpers), broken packages / pending updates
(new probe), repository health, filesystem/storage warnings (new probe), recent
critical logs (`RuntimeSources.logs/1`), backup freshness
(`RuntimeSources.backups/0`), audit status (`Audit.verify/0`).

**Important:** Diagnosis ≠ Repair. Later repair actions are **separate**
governed capabilities (L2/L3). The diagnose workflow itself stays L0/L1.
No automatic `systemctl restart`, `apt upgrade`, `rm`, filesystem repair or
network mutation inside the diagnose workflow.

## 3. `release_acceptance`

**Purpose:** reuse existing gates; decide `release_ready`.

**Reuse (do not re-implement):** `shadowops-local.sh certify`, quality gates,
registry validation, MCP/WebMCP tests, Credo, Dialyzer, Sobelow, `mix test`,
`compile --warnings-as-errors`, `git diff --check`.

**Desired gate order:** git identity → worktree state → format → compile →
focused tests → full tests → registry → Credo → Dialyzer (if present) →
Sobelow (if present) → MCP → WebMCP → isolated runtime → API truth → audit
integrity → evidence bundle.

**Output:** `release_ready: true | false`. `release_ready` may be `true`
**only if all REQUIRED gates are green**. No automatic promotion; no 4013
mutation. **Risk:** L1.

## 4. `career_control`

**Purpose:** read-only pipeline + next-action suggestion.

**Later states:** NEW_LEAD, PREPARING, SENT, WAITING, FOLLOW_UP, INTERVIEW,
REJECTED, CONFIRMED, BOUNCE, CLOSED.

**Sources to map:** existing career state (`RuntimeSources.career/0`),
Gmail connector (capability stub today → `Deny`), Contacts, Documents/Evidence,
Calendar, application evidence.

**If Gmail/connector not configured:** `status = UNAVAILABLE` or
`NOT_CONFIGURED`. **Never fabricate applications.** Read-only phase: read
pipeline, detect missing follow-ups, classify new replies, produce next action.
**Sending remains a separate L3 action with approval.**

## 5. `ihk_evidence_gate`

**Purpose:** evidence-state gate for IHK project proof.

**Evidence states:** VERIFIED, WEAK, MISSING, NOT_APPLICABLE.

**Sources to map:** IHK project files (`ProjectDomains.snapshot(:ihk)`),
`docs/evidence`, tests, commits (audit journal), project hours, cost /
economic viability, acceptance, client proof, screenshots, CI evidence,
sources, project application.

**Output:** `evidence_score`, `verified_count`, `weak_count`,
`missing_count`, `blockers`, `next_actions`. **No invented evidence.**
**Risk:** L0 / L1.

## One-Click governance map (asserted for all five)

| Field                | Value                                                                 |
|---------------------|-----------------------------------------------------------------------|
| `workflow_id`       | `shadowops.<name>`                                                    |
| `type`              | `system` or `business` (per domain)                                   |
| `domain`            | system / security / ci / career / ihk / evidence / reporting          |
| `risk_level`        | L0 / L1 (read), L2/L3 (separate repair/send capabilities)             |
| `approval_required` | true only for mutating sub-capabilities                               |
| `read_only`         | true for the diagnostic/acceptance/gate contracts                      |
| `side_effect_class` | none (read) | L2/L3 (separate governed capability)                     |
| `source`            | existing `RuntimeSources` / `ShadowOpsApi` / scripts / registry        |
| `executor`          | `canonical_workflow` / `script` (existing adapters)                   |
| `runtime`           | existing (`VERIFIED_EXECUTABLE` script pattern)                        |
| `evidence_output`   | canonical contract map above                                          |

Mutations MUST later flow through: `CapabilityRegistry` → `Policy`/`RiskPolicy`
→ `Approval` → `PrivacyGate` → `ExecutionService` → `Adapter` → `Audit`.
Controllers/LiveViews receive no direct mutating adapter calls.
