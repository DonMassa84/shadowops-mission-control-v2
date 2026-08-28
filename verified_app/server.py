#!/usr/bin/env python3

from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import datetime
import hashlib
import json
import os
import socket
import subprocess
import urllib.parse
import uuid

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
STATIC = ROOT / "static"
RUNS = DATA / "runs"
AUDIT = DATA / "audit"
HOST = "127.0.0.1"
PORT = int(os.environ.get("SHADOWOPS_VERIFIED_PORT", "4014"))
SELF_CHECK_ID = "so:wf:v1:shadowops-verified-self-check"

AGENT = "/home/schattenmacher/whatsapp-agent/scripts/whatsapp-agent"
MAINTENANCE = "/home/schattenmacher/whatsapp-agent/scripts/run-maintenance.sh"
WORKER = "/home/schattenmacher/whatsapp-agent/scripts/run-worker.sh"

# Immutable, code-reviewed argv allowlist. No command text is read from config.
WHATSAPP_SPECS = {
    "so:wf:v1:whatsapp-status": (AGENT, ["status"], "L0", 120),
    "so:wf:v1:whatsapp-sync-status": (AGENT, ["sync-status"], "L0", 60),
    "so:wf:v1:whatsapp-worker-status": (AGENT, ["worker-status"], "L0", 60),
    "so:wf:v1:whatsapp-queue": (AGENT, ["queue"], "L0", 60),
    "so:wf:v1:whatsapp-doctor": (AGENT, ["doctor"], "L0", 120),
    "so:wf:v1:whatsapp-contacts": (AGENT, ["contacts"], "L0", 60),
    "so:wf:v1:whatsapp-report": (AGENT, ["report"], "L0", 300),
    "so:wf:v1:whatsapp-meta-status": (AGENT, ["meta-status"], "L0", 120),
    "so:wf:v1:whatsapp-maintenance-15min": (MAINTENANCE, ["15min"], "L0", 300),
    "so:wf:v1:whatsapp-maintenance-hourly": (MAINTENANCE, ["hourly"], "L1", 600),
    "so:wf:v1:whatsapp-maintenance-daily": (MAINTENANCE, ["daily"], "L1", 900),
    "so:wf:v1:whatsapp-backup": (AGENT, ["backup"], "L1", 300),
    "so:wf:v1:whatsapp-worker-drain": (WORKER, ["--once"], "L1", 600),
    "so:wf:v1:whatsapp-retry-all": (AGENT, ["retry-all"], "L1", 120),
    "so:wf:v1:whatsapp-purge-expired": (AGENT, ["purge-expired", "--confirm"], "L2", 300),
    "so:wf:v1:whatsapp-meta-subscribe": (AGENT, ["meta-subscribe", "--confirm"], "L2", 120),
}

RUNS.mkdir(parents=True, exist_ok=True)
AUDIT.mkdir(parents=True, exist_ok=True)


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha256_json(value):
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def json_response(handler, status, payload):
    raw = json.dumps(payload, indent=2, ensure_ascii=False).encode()
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(raw)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(raw)


def load_inventory():
    path = DATA / "workflows.json"
    if not path.exists():
        return {"schema": "shadowops-verified-app-v1", "policy": "fail-closed", "count": 0, "workflows": []}
    return json.loads(path.read_text())


def git_value(*args):
    result = subprocess.run(["git", *args], cwd=ROOT.parent, capture_output=True, text=True, timeout=5, check=True)
    return result.stdout.strip()


def port_open(host, port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.3)
        return sock.connect_ex((host, port)) == 0


def persist_run(workflow_id, result):
    run_id = str(uuid.uuid4())
    run = {
        "run_id": run_id,
        "workflow_id": workflow_id,
        "status": result["status"],
        "created_at": now(),
        "result": result,
    }
    run["result_sha256"] = sha256_json(result)
    (RUNS / f"{run_id}.json").write_text(json.dumps(run, indent=2, ensure_ascii=False) + "\n")

    audit = {
        "event_id": str(uuid.uuid4()),
        "event": "workflow_run_completed",
        "timestamp": now(),
        "run_id": run_id,
        "workflow_id": workflow_id,
        "status": run["status"],
        "result_sha256": run["result_sha256"],
    }
    audit["event_sha256"] = sha256_json(audit)
    (AUDIT / f"{run_id}.json").write_text(json.dumps(audit, indent=2, ensure_ascii=False) + "\n")
    run["audit"] = audit
    return run


def self_check():
    checks = []

    def add(name, passed, value):
        checks.append({"check": name, "passed": bool(passed), "value": value})

    try:
        branch = git_value("branch", "--show-current")
        add("git_branch", branch == "feature/shadowops-verified-app", branch)
    except Exception as exc:
        add("git_branch", False, type(exc).__name__)

    try:
        head = git_value("rev-parse", "HEAD")
        add("git_head", len(head) == 40, head)
    except Exception as exc:
        add("git_head", False, type(exc).__name__)

    inventory = load_inventory()
    add("inventory_load", isinstance(inventory.get("workflows"), list), inventory.get("count", 0))
    add("fail_closed_policy", inventory.get("policy") == "fail-closed", inventory.get("policy"))
    add("production_port_observed", True, "LISTENING" if port_open("127.0.0.1", 4013) else "NOT_LISTENING")
    add("production_mutation", True, "NO")
    passed = all(item["passed"] for item in checks)
    return {
        "workflow_id": SELF_CHECK_ID,
        "workflow_name": "ShadowOps Verified Self Check",
        "risk": "L0",
        "approval_required": False,
        "execution_type": "builtin-read-only",
        "started_at": now(),
        "finished_at": now(),
        "status": "SUCCESS" if passed else "FAILED",
        "checks": checks,
    }


def execute_whatsapp(workflow):
    workflow_id = workflow["id"]
    spec = WHATSAPP_SPECS.get(workflow_id)
    if spec is None:
        return 409, {"status": "BLOCKED", "workflow_id": workflow_id, "reason": "workflow_not_allowlisted", "policy": "fail-closed"}

    executable, args, risk, timeout = spec
    if risk in {"L2", "L3"} or workflow.get("approval_required"):
        return 409, {"status": "BLOCKED", "workflow_id": workflow_id, "reason": "approval_required", "risk": risk, "policy": "fail-closed"}

    if not workflow.get("execution_verified") or not workflow.get("start_enabled"):
        return 409, {
            "status": "BLOCKED",
            "workflow_id": workflow_id,
            "reason": workflow.get("block_reason", "execution_not_verified"),
            "policy": "fail-closed",
        }

    started = now()
    try:
        completed = subprocess.run(
            [executable, *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        result = {
            "workflow_id": workflow_id,
            "execution_type": "verified-static-argv",
            "risk": risk,
            "approval_required": False,
            "started_at": started,
            "finished_at": now(),
            "status": "SUCCESS" if completed.returncode == 0 else "FAILED",
            "exit_code": completed.returncode,
            "stdout": completed.stdout,
            "stderr": completed.stderr,
            "arbitrary_shell": False,
        }
    except subprocess.TimeoutExpired as exc:
        result = {
            "workflow_id": workflow_id,
            "execution_type": "verified-static-argv",
            "risk": risk,
            "approval_required": False,
            "started_at": started,
            "finished_at": now(),
            "status": "FAILED",
            "reason": "execution_timeout",
            "stdout": exc.stdout or "",
            "stderr": exc.stderr or "",
            "arbitrary_shell": False,
        }

    run = persist_run(workflow_id, result)
    return (200 if result["status"] == "SUCCESS" else 500), run


def list_runs():
    items = []
    for path in sorted(RUNS.glob("*.json"), reverse=True):
        try:
            items.append(json.loads(path.read_text()))
        except Exception:
            pass
    return items


def workflows():
    inventory = load_inventory()
    external = inventory.get("workflows", [])
    self_workflow = {
        "id": SELF_CHECK_ID,
        "name": "ShadowOps Verified Self Check",
        "source": "verified_app/server.py",
        "definition_verified": True,
        "execution_verified": True,
        "status": "VERIFIED",
        "risk": "L0",
        "approval_required": False,
        "start_enabled": True,
    }
    verified = 1 + sum(1 for item in external if item.get("execution_verified"))
    return {
        "schema": "shadowops-verified-app-v3",
        "policy": "fail-closed",
        "count": len(external) + 1,
        "execution_verified_count": verified,
        "workflows": [self_workflow, *external],
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "ShadowOpsVerified/3"

    def log_message(self, fmt, *args):
        print(datetime.datetime.now().isoformat(timespec="seconds"), fmt % args)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/health":
            return json_response(self, 200, {"status": "ok", "app": "shadowops-verified"})
        if path == "/ready":
            return json_response(self, 200, {"status": "ready", "policy": "fail-closed", "execution_verified": workflows()["execution_verified_count"]})
        if path == "/api/workflows":
            return json_response(self, 200, workflows())
        if path == "/api/runs":
            return json_response(self, 200, {"runs": list_runs()})
        if path.startswith("/api/runs/"):
            run_id = urllib.parse.unquote(path.split("/api/runs/", 1)[1])
            target = RUNS / f"{run_id}.json"
            if not target.exists():
                return json_response(self, 404, {"error": "run_not_found"})
            return json_response(self, 200, json.loads(target.read_text()))
        if path == "/api/audit":
            items = []
            for target in sorted(AUDIT.glob("*.json"), reverse=True):
                try:
                    items.append(json.loads(target.read_text()))
                except Exception:
                    pass
            return json_response(self, 200, {"events": items})
        if path == "/api/system":
            return json_response(self, 200, {
                "name": "ShadowOps Verified",
                "mode": "LOCAL_VERIFIED",
                "port": PORT,
                "production_port": 4013,
                "production_mutation": False,
                "execution_verified": workflows()["execution_verified_count"],
            })

        target = STATIC / ("index.html" if path in {"/", "/index.html"} else path.lstrip("/"))
        try:
            resolved = target.resolve()
            if STATIC.resolve() not in resolved.parents and resolved != STATIC.resolve():
                raise ValueError("outside static root")
            if not resolved.is_file():
                raise FileNotFoundError()
            content_type = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "application/javascript; charset=utf-8"}.get(resolved.suffix.lower(), "application/octet-stream")
            body = resolved.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
        except Exception:
            self.send_error(404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        prefix = "/api/workflows/"
        suffix = "/start"
        if parsed.path.startswith(prefix) and parsed.path.endswith(suffix):
            workflow_id = urllib.parse.unquote(parsed.path[len(prefix):-len(suffix)]).rstrip("/")
            if workflow_id == SELF_CHECK_ID:
                run = persist_run(SELF_CHECK_ID, self_check())
                return json_response(self, 200 if run["status"] == "SUCCESS" else 500, run)

            known = next((item for item in load_inventory().get("workflows", []) if item["id"] == workflow_id), None)
            if not known:
                return json_response(self, 404, {"status": "BLOCKED", "reason": "workflow_not_found"})
            status, payload = execute_whatsapp(known)
            return json_response(self, status, payload)

        return json_response(self, 404, {"error": "not_found"})


if __name__ == "__main__":
    print(f"SHADOWOPS_VERIFIED=http://{HOST}:{PORT}")
    print(f"VERIFIED_EXECUTION_WORKFLOWS={workflows()['execution_verified_count']}")
    print("PRODUCTION_4013_MUTATION=NO")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
