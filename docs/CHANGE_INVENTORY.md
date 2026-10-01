# Local transfer inventory — 2026-10-01

This inventory records the evidence-backed Ryzen/i7 transfer state. It does not certify port 4013 or turn discovered components into operational capabilities.

| Component | Source / commit | Installed state | Verification | Remaining issue |
|---|---|---|---|---|
| ShadowOps WhatsApp operations | PR #64, last verified head `5eee64d0527b0032a908fa37feb0eeb06533da62`; incorporated and extended in local head `0f67ed628f54b5fb1b08b37ee6d912839ccb39b1` | Isolated worktree `integration/local-transfer-20261001`; port 4013 unchanged | PR content and local history inspected; compile attempt on current head blocked by BEAM exit 139 | Re-run all gates with the reference Elixir 1.17.3 / OTP 27.3 toolchain before release certification |
| WhatsApp runtime truth | Same ShadowOps worktree | UI distinguishes stored database evidence from worker liveness | Source/tests inspected | No live WhatsApp worker/session/send was asserted or triggered |
| i7 task feed | ShadowOps `ops/local_transfer/kiosk`; i7 commit `c2f875c` on `local/task-feed-20261001` | Publisher timer active on Ryzen; receiver and UI installed on i7 | Publisher 5/5 tests; receiver 4/4 tests; live `/api/tasks` revision 1, `offline=false`; repeat publish returned `UNCHANGED` | Full browser suite stalled in the pre-existing Bital Firefox test; focused feed tests pass |
| i7 kiosk | i7 `local/task-feed-20261001` commit `c2f875c` | `learning-kiosk.service` and `learning-kiosk-browser.service` active; `/health` returned `ok` | Fresh 1920x1080 physical screenshot and live HTTP probe | Screenshot proves trainer display, not the task route; API is the task-content evidence |
| Gmail priority agent | suite commit `583c358` on `integration/local-transfer-20261001` | One four-hour timer active; read-only implementation installed | 10/10 tests in installed venv; overlap lock and idempotent import tested | Live run is `BLOCKED`: Google returned `RefreshError` / `invalid_grant`; interactive OAuth renewal required |
| Crash monitoring | suite commit `583c358` | One four-hour timer active; local-only report, no auto-repair or external delivery | 7/7 tests; manual service run exited 0 and preserved cursor/state | Incident classifications are coarse metadata and require human diagnosis |
| Mietabschluss | private local runtime; verification evidence under `reports/local-transfer-20261001/rental-private` | One local timer active; private files mode 0600/0700 | 8 tests, hash-chain/evidence check, idempotent second import, isolated restore verification | Evidence integrity does not prove legal authenticity; zero events are currently recorded |
| Kiosk content topics | `ops/local_transfer/kiosk/tasks.json`, revision 1 | Five status-check tasks published | Stable IDs, priority/due sorting, private/done filtering, atomic last-good behavior tested | All five entries deliberately remain `unverified`; authoritative sources were not available |

## Repository state

- ShadowOps worktree: `integration/local-transfer-20261001`, head `0f67ed628f54b5fb1b08b37ee6d912839ccb39b1`, seven commits ahead of the local source branch before this documentation commit.
- Suite worktree: `integration/local-transfer-20261001`, head `583c358`.
- i7 kiosk: `local/task-feed-20261001`, head `c2f875c`.
- No push, merge, production deployment, external message, queue drain, purge, retry-all, or port-4013 mutation was performed.

## Evidence locations

- Private transfer evidence: `/home/shadowmaker/reports/local-transfer-20261001/`
- Fresh physical display image: `/home/shadowmaker/reports/local-transfer-20261001/kiosk-private/physical-current-tasks.png`
- Kiosk publisher state: `/home/shadowmaker/.local/state/shadowops-kiosk-publisher/status.json`
- Crash monitor state: `/home/shadowmaker/.local/state/shadowops-recovery/state.json`
- Gmail agent state: `/home/shadowmaker/.local/share/mail-priority-agent/status.json`

These runtime/private paths are intentionally outside Git.
