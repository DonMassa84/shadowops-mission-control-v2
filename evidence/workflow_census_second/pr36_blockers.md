# PR #36 Blocker Decomposition (read-only audit, second instance)

Base SHA under audit: `fda310acff54106c988801d5b36f67bc0791f6e7`
PR state (confirmed via gh): OPEN, DRAFT=NO, MERGED=NO, MERGEABLE=NO (CONFLICTING), 501 commits / 246 files vs main.
Note: PR-triggered workflow runs for this head SHA were NOT independently retrievable from the GitHub linkage used here; therefore CI_GREEN=NOT_PROVEN.

## BLOCKER 1 — Merge conflict vs `main` (causes MERGEABLE=NO)
**Conflicting file:** `opencode.jsonc` (true **add/add** conflict; file absent at merge-base `f3c88d4`).

- `origin/main:opencode.jsonc` → github remote MCP server (api.githubcopilot.com/mcp, readonly, PAT via env).
- `origin/feature/shadowops-verified-app:opencode.jsonc` → `default_agent: shadowops-coder`, `share: disabled`, `snapshot: true`, and a **local** MCP server `shadowops-runtime` (`bash scripts/run-shadowops-mcp.sh`, `SHADOWOPS_BASE_URL=http://127.0.0.1:4014`).

Both sides added the same path with incompatible schemas → GitHub cannot auto-merge → CONFLICTING.

**Resolution direction (for Worker 1, not performed here):**
Merge both MCP server blocks into a single `opencode.jsonc`: keep the github remote server AND the shadowops-runtime local server; preserve `default_agent`, `share`, `snapshot`, `instructions`, `tool_output`, `compaction` from the branch side; ensure no duplicate top-level keys. No 4013/4014 production mutation required — `shadowops-runtime` legitimately targets 4014 (preview), which is contract-compliant.

## BLOCKER 2 — Verified Product Gate step failure (CI_GREEN=NOT_PROVEN)
`verified-app-product.yml` step sequence on the head SHA:
1. Checkout exact candidate
2. Candidate identity (echo only)
3. Setup Python
4. **Verified App tests** → `python3 -m unittest discover -s verified_app/tests`
5. **Inventory gate** (inline python asserting 16 wf / 9 L0 / 5 L1 / 2 L2 / 12 accepted / 2 runtime_blocked / 2 approval_gated)
6. Setup Elixir
7. `mix deps.get`
8. `git diff --exit-code -- mix.lock`
9. `mix format --check-formatted`
10. `mix compile --warnings-as-errors`
11. Capture 4013 before (`ss`)
12. `mix test --seed 12345`
13. Verify no new 4013 listener
14. `python3 scripts/freeze_gate.py` (FREEZE_EXCEPTION=RELEASE_BLOCKER)
15. `git diff --check`
16. Final status (echo only)

**Independently reproduced on the head content (local, second instance):**
- `verified_app/data/workflows.json` satisfies the inventory gate assertions exactly → INVENTORY_GATE=PASS.
- `python3 -m unittest discover -s verified_app/tests` → 16/16 PASS, no 4013/4014 binding.

**Conclusion:** Steps 4–5 (verified_app tests + inventory gate) PASS on the head. Therefore the failing step, IF the run actually executed for this SHA, must be in the later Elixir/static portion: most likely **`mix format --check-formatted`** (unformatted file), **`mix compile --warnings-as-errors`** (warnings from newly added deps in mix.lock: credo, dialyxir, hammer, bunt, erlex, file_system), **`mix test`**, or **`freeze_gate.py`**. The exact failing step could NOT be confirmed here because the run log (33193759820) was not retrievable from the linkage available to this instance.

**Not caused by:** the 4013 port (gate only inspects, never starts it) and not by the whatsapp workflow data (already verified).

## Recommendation for Worker 1 (targeted fix, only after confirmation)
1. Resolve `opencode.jsonc` add/add by merging both MCP servers (no key collision).
2. Re-run `verified-app-product.yml` on the branch after conflict resolution and read the first failing step line; fix that specific Elixir/static step (format/compile warning/freeze).
3. Do NOT touch port 4013 (production) or 4014 (preview) bindings; 4014 preview binding in opencode.jsonc is contract-compliant.

## Integrity
- No files on `feature/shadowops-verified-app` were modified.
- No merge, no rebase, no deploy, no 4013/4014 mutation.
- This document is audit evidence only; it contains no fix/commit to product code.
