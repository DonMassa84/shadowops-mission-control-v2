# SAFE AUDIT RUNBOOK — INSTANCE 2 (Independent Safe Auditor)

Version: 2026-10-08
Applies to: `~/Projects/shadowops-audit`, branch `audit/recovery-20261007`

## 1. Safe Mode

Safe Mode = **READ-ONLY SYSTEM + WRITE-ONLY AUDIT WORKTREE**.

Every command is classified internally before execution:

| Class | Meaning | Allowed |
|---|---|---|
| `COMMAND_CLASS=READ_ONLY` | Observes state, changes nothing | yes |
| `COMMAND_CLASS=AUDIT_WRITE` | Writes only inside `~/Projects/shadowops-audit` | yes |
| `COMMAND_CLASS=MUTATING` | Changes system/service/config/other repos | **no** |
| `COMMAND_CLASS=UNCERTAIN` | Intent unclear | **no** — do not run |

If uncertain: do not execute. Record instead:

```
SAFE_MODE_BLOCKED_COMMAND=<command>
REASON=<why>
```

## 2. Allowed commands

- Read-only system probes: `hostname`, `uptime`, `free -h`, `df -h`, `ps`, `ss`, `pgrep`,
  `curl` (GET against local endpoints), `ollama list|ps`, `opencode --version`, `jq` reads,
  `systemctl status|cat|show|list-units|list-timers` (no start/stop/enable/disable),
  `journalctl` (reads), `tailscale ping|status`
- Read-only SSH diagnostics on `shadowserver-i7`: `hostname`, `uptime`, `systemctl --failed`,
  `systemctl status`, `ollama list`, local `curl` probes
- Audit writes **only** in `~/Projects/shadowops-audit`
- Git: `status`, `diff`, `add <audit files>`, `commit`, `push` of the audit branch

## 3. Forbidden commands

- `systemctl start|stop|restart|enable|disable|mask`
- `kill`, `pkill`, `reboot`, `shutdown`
- `apt install|remove`, `pip install`, `npm install`, `bun install`
- Ollama model downloads/deletes (`ollama pull`, `ollama rm`, `/api/pull`)
- Changing anything under `~/.config`
- Editing productive files in other repos/worktrees
- `gh auth login|logout`
- Git actions in foreign worktrees (no merge/rebase/reset/force-push/branch rewrite)
- SSH commands with any remote write effect
- Printing secrets, tokens, keys or environment dumps

## 4. Worktree isolation

Read paths (always read-only for the auditor):

- `~/Projects/shadowops`
- `~/Projects/shadowops-i7-worker`
- `~/Projects/shadowops-runtime-deploy`

Write path (the only one):

- `~/Projects/shadowops-audit`

Pre-flight before any git write action:

```bash
pwd
git rev-parse --show-toplevel
git branch --show-current
git remote -v
```

Expected:

- `ROOT=~/Projects/shadowops-audit`
- `BRANCH=audit/recovery-20261007`

If not expected: `AUDIT_GIT_WRITE_BLOCKED=YES` and stop.

## 5. Remote read-only policy

- Diagnosis only on `Ryzen` (local) and `shadowserver-i7` (remote)
- No productive remote changes, no service actions, no package actions
- SSH commands limited to read-only probes; each remote command is reviewed as READ_ONLY

## 6. Secret handling

- Never print token values, keys, passwords or environment dumps
- `gh auth status` output is redacted before storing
- Evidence files contain paths, counts, statuses — never secret material
- Filename/pattern scans only; report `PATH=` and `RISK=` on a hit, never the content

## 7. Regression tests (read-only)

Executed each audit run and recorded in `docs/audit/evidence/regression-analysis.txt`:

1. Ollama restart loop  2. API port conflict  3. OpenCode crash (SIGILL/SIGSEGV)
4. Invalid default model  5. New failed systemd units  6. systemd user bus hang
7. D-state regression  8. TinyFish failure  9. Tailscale failure
10. i7 connectivity loss  11. Wrong provider routing  12. Git worktree conflict
13. Secret leakage  14. Uncommitted productive changes

Classification: `CRITICAL | HIGH | MEDIUM | LOW | OK`.

## 8. Cross-instance reporting

Problems are reported, never fixed:

- Ryzen problem → `FINDING_FOR_INSTANCE1=`
- i7 problem → `FINDING_FOR_INSTANCE3=`

Instance 1 owns Ryzen main repair, Instance 3 owns i7 worker / LLM runtime.

## 9. Audit acceptance rules

`MAIN_RECOVERY_ACCEPTED=YES` requires **all** of:

- `OLLAMA_AUDIT=PASS`
- `OPENCODE_AUDIT=PASS`
- `WORKTREE_ISOLATION=PASS`
- `NEW_REGRESSIONS=NONE`
- `CRITICAL_REMAINING=0`

May remain as accepted remaining actions:

- GitHub browser login
- documented reboot
- obsolete TinyFish unit cleanly deactivated
- non-critical systemd degraded state with documented cause

No `PASS` without a real test. `UNVERIFIED` stays `UNVERIFIED`.

## 10. Commit & push policy

- Commit only audit artifacts: `RECOVERY_AUDIT.md`, `meta/audit/*`, `docs/audit/**`
- Never productive scripts, never other worktrees
- Commit message style: `docs(audit): record verified recovery state`
- Push only `audit/recovery-20261007`, never force
- If push is blocked: `GITHUB_PUSH=BLOCKED`, keep the local commit
