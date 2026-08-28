# WhatsApp Runtime Bindings — Truthfulness Evidence

Generated: {
  "generated_at": "2026-08-28T22:05:24.591223+00:00",
  "count": 16,
  "bindings": [
    {
      "

BASE_SHA: fda310acff54106c988801d5b36f67bc0791f6e7
WORKTREE: /home/schattenmacher/Projects/shadowops-whatsapp-bindings
BRANCH: workflow/whatsapp-runtime-bindings

| WORKFLOW_ID | RUNTIME | EXECUTOR | CAPABILITY | RISK | APPROVAL | STATE | EVIDENCE |
|---|---|---|---|---|---|---|---|
| so:wf:v1:whatsapp-status | TCC | /home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent ['status'] | WHATSAPP_MONITORING | L0 | False | RUNNABLE | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-sync-status | TCC | /home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent ['sync-status'] | WHATSAPP_MONITORING | L0 | False | RUNNABLE | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-worker-status | TCC | /home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent ['worker-status'] | WHATSAPP_MONITORING | L0 | False | RUNNABLE | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-queue | TCC | /home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent ['queue'] | WHATSAPP_MONITORING | L0 | False | RUNNABLE | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-doctor | TCC | /home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent ['doctor'] | WHATSAPP_MONITORING | L0 | False | BLOCKED | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-contacts | TCC | /home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent ['contacts'] | WHATSAPP_MONITORING | L0 | False | RUNNABLE | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-report | TCC | /home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent ['report'] | WHATSAPP_MONITORING | L0 | False | RUNNABLE | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-meta-status | TCC | /home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent ['meta-status'] | WHATSAPP_MONITORING | L0 | False | BLOCKED | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-maintenance-15min | TCC | /home/schattenmacher/whatsapp-agent/scripts/run-maintenance.sh ['15min'] | WHATSAPP_MONITORING | L0 | False | RUNNABLE | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-maintenance-hourly | TCC | /home/schattenmacher/whatsapp-agent/scripts/run-maintenance.sh ['hourly'] | WHATSAPP_MAINTENANCE | L1 | False | RUNNABLE | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-maintenance-daily | TCC | /home/schattenmacher/whatsapp-agent/scripts/run-maintenance.sh ['daily'] | WHATSAPP_MAINTENANCE | L1 | False | RUNNABLE | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-backup | TCC | /home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent ['backup'] | WHATSAPP_MAINTENANCE | L1 | False | RUNNABLE | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-worker-drain | TCC | /home/schattenmacher/whatsapp-agent/scripts/run-worker.sh ['--once'] | WHATSAPP_MAINTENANCE | L1 | False | RUNNABLE | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-retry-all | TCC | /home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent ['retry-all'] | WHATSAPP_MAINTENANCE | L1 | False | RUNNABLE | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-purge-expired | TCC | /home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent ['purge-expired', '--confirm'] | WHATSAPP_ACTION | L2 | True | BLOCKED | executor_exists=True, tcc=True |
| so:wf:v1:whatsapp-meta-subscribe | TCC | /home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent ['meta-subscribe', '--confirm'] | WHATSAPP_ACTION | L2 | True | BLOCKED | executor_exists=True, tcc=True |
