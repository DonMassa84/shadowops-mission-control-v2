# Local transfer runbook — Ryzen and i7

This runbook resumes the 2026-10-01 integration without rediscovery or duplicate installation. Run read-only checks first. Port 4013 is out of scope.

## 1. Preflight

```bash
cd /home/shadowmaker/local-transfer-worktrees/shadowops
git status --short --branch
git diff --check
git log -1 --oneline

ssh -o BatchMode=yes -o ConnectTimeout=5 shadowserver-i7 \
  'hostname; git -C ~/Projects/learning-kiosk status --short --branch; git -C ~/Projects/learning-kiosk log -1 --oneline'
```

Expected branches are `integration/local-transfer-20261001` on Ryzen and `local/task-feed-20261001` on i7. Stop if either worktree has unexpected changes.

## 2. Read-only runtime checks

```bash
systemctl --user is-active \
  shadowops-recovery.timer \
  mail-priority-agent.timer \
  mietabschluss.timer \
  shadowops-kiosk-content.timer

systemctl --user list-timers --all --no-pager | \
  grep -E 'shadowops-recovery|mail-priority|mietabschluss|shadowops-kiosk-content'

ssh shadowserver-i7 \
  'systemctl --user is-active learning-kiosk.service learning-kiosk-browser.service; curl -fsS http://127.0.0.1:8765/health; curl -fsS http://127.0.0.1:8765/api/tasks'
```

On 2026-10-01 all four Ryzen timers and both i7 services were active. The i7 task response reported revision 1 and `offline=false`.

## 3. Test the bounded integrations

```bash
cd /home/shadowmaker/Projects/suite-local-transfer-20261001
PYTHONDONTWRITEBYTECODE=1 \
  /home/shadowmaker/.local/share/mail-priority-agent/venv/bin/python \
  -m unittest discover -s integrations/mail-priority-agent/tests -v
PYTHONDONTWRITEBYTECODE=1 python3 \
  -m unittest discover -s integrations/shadowops-recovery/tests -v

cd /home/shadowmaker/local-transfer-worktrees/shadowops
PYTHONDONTWRITEBYTECODE=1 python3 \
  -m unittest discover -s ops/local_transfer/kiosk/tests -v
python3 ops/local_transfer/kiosk/publish_tasks.py --check

ssh shadowserver-i7 \
  'cd ~/Projects/learning-kiosk && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_task_feed.py -v'
```

Recorded result: Gmail 10/10, recovery 7/7, publisher 5/5, receiver 4/4.

## 4. Publish task content safely

Edit only `ops/local_transfer/kiosk/tasks.json`. Preserve the schema, stable IDs, `Europe/Berlin`, evidence labels, and visibility rules. Validate before publishing:

```bash
python3 ops/local_transfer/kiosk/publish_tasks.py --check
python3 ops/local_transfer/kiosk/publish_tasks.py
cat /home/shadowmaker/.local/state/shadowops-kiosk-publisher/status.json
```

The publisher uses a fixed SSH destination and receiver, removes `private` and `done` tasks, uses a non-blocking lock, and preserves `last_success` after transport failure. A repeated unchanged publish must report `UNCHANGED`.

## 5. Gmail OAuth blocker

The current token refresh fails with `invalid_grant`. Do not delete or replace OAuth files automatically. The operator must complete a new read-only Gmail consent flow locally:

```bash
/home/shadowmaker/.local/share/mail-priority-agent/venv/bin/python \
  /home/shadowmaker/.local/share/mail-priority-agent/src/mail_priority.py \
  --interactive-auth
```

After successful authorization:

```bash
systemctl --user start mail-priority-agent.service
systemctl --user status mail-priority-agent.service --no-pager
cat /home/shadowmaker/.local/share/mail-priority-agent/status.json
```

Success requires exit 0 and a non-null `last_success`. The timer is already present; do not install a second timer.

## 6. ShadowOps gate blocker

The only installed toolchain is Elixir 1.20.3 / OTP 28.4. Two compile attempts on head `0f67ed6` ended with BEAM exit 139, including a reduced-scheduler retry. The reference PR toolchain is Elixir 1.17.3 / OTP 27.3.

Do not claim compile or certification success. Install/select the reference toolchain, then run the repository gate order from `AGENTS.md`. Do not promote or touch port 4013.

## 7. Rollback

- i7 original startup files: `/home/shadowmaker/reports/local-transfer-20261001/kiosk-private/startup-original-files.tar.gz`
- Mail/recovery pre-finish backup: `/home/shadowmaker/reports/local-transfer-20261001/mail-monitor-private/before-finish.tar.gz`
- Rental pre-transfer and pre-resume archives: `/home/shadowmaker/reports/local-transfer-20261001/rental-private/`
- i7 software history: branch `local/task-feed-20261001`, commit `c2f875c`, parent `fd042bc`
- Suite history: commit `583c358`, previous integration commit `52e6e24`

Restoration is a deliberate operator action. Inspect archive contents and stop the corresponding timer before applying files. Never use `git reset --hard` or `git clean` as rollback.

## 8. Known truthful states

- Gmail: `BLOCKED_AUTH`, not operational.
- Crash monitor: operational local read-only scan; no automatic repair or external report.
- WhatsApp: UI/database evidence exists; worker/session/send readiness remains unproven.
- Kiosk task feed: operational and last-good capable; published topic entries are unverified status prompts.
- Mietabschluss: integrity tooling operational; legal authenticity not established.
- ShadowOps release: `BLOCKED_TOOLCHAIN`; port 4013 unchanged.
