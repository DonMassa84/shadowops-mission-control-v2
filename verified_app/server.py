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

RUNS.mkdir(parents=True, exist_ok=True)
AUDIT.mkdir(parents=True, exist_ok=True)


def now():
    return datetime.datetime.now(
        datetime.timezone.utc
    ).isoformat()


def sha256_json(value):
    raw = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":")
    ).encode()

    return hashlib.sha256(raw).hexdigest()


def json_response(handler, status, payload):
    raw = json.dumps(
        payload,
        indent=2,
        ensure_ascii=False
    ).encode()

    handler.send_response(status)
    handler.send_header(
        "Content-Type",
        "application/json; charset=utf-8"
    )
    handler.send_header(
        "Content-Length",
        str(len(raw))
    )
    handler.send_header(
        "Cache-Control",
        "no-store"
    )
    handler.end_headers()
    handler.wfile.write(raw)


def load_inventory():
    path = DATA / "workflows.json"

    if not path.exists():
        return {
            "schema": "shadowops-verified-app-v1",
            "policy": "fail-closed",
            "count": 0,
            "workflows": []
        }

    return json.loads(path.read_text())


def repo_root():
    return ROOT.parent


def git_value(*args):
    result = subprocess.run(
        ["git", *args],
        cwd=repo_root(),
        capture_output=True,
        text=True,
        timeout=5,
        check=True
    )

    return result.stdout.strip()


def port_open(host, port):
    with socket.socket(
        socket.AF_INET,
        socket.SOCK_STREAM
    ) as sock:

        sock.settimeout(0.3)

        return sock.connect_ex(
            (host, port)
        ) == 0


def self_check():
    started = now()

    checks = []

    def add(name, passed, value):
        checks.append({
            "check": name,
            "passed": bool(passed),
            "value": value
        })

    try:
        branch = git_value(
            "branch",
            "--show-current"
        )
        add(
            "git_branch",
            branch == "feature/shadowops-verified-app",
            branch
        )
    except Exception as exc:
        add(
            "git_branch",
            False,
            type(exc).__name__
        )

    try:
        head = git_value(
            "rev-parse",
            "HEAD"
        )

        add(
            "git_head",
            len(head) == 40,
            head
        )
    except Exception as exc:
        add(
            "git_head",
            False,
            type(exc).__name__
        )

    try:
        inventory = load_inventory()

        add(
            "inventory_load",
            isinstance(
                inventory.get("workflows"),
                list
            ),
            inventory.get("count", 0)
        )

        add(
            "fail_closed_policy",
            inventory.get("policy") == "fail-closed",
            inventory.get("policy")
        )

    except Exception as exc:
        add(
            "inventory_load",
            False,
            type(exc).__name__
        )

    # :4013 wird ausschließlich beobachtet.
    # Kein HTTP Request, kein Restart, kein Stop, keine Mutation.
    p4013 = port_open(
        "127.0.0.1",
        4013
    )

    add(
        "production_port_observed",
        True,
        "LISTENING" if p4013 else "NOT_LISTENING"
    )

    add(
        "production_mutation",
        True,
        "NO"
    )

    passed = all(
        x["passed"]
        for x in checks
    )

    result = {
        "workflow_id": SELF_CHECK_ID,
        "workflow_name": "ShadowOps Verified Self Check",
        "risk": "L0",
        "approval_required": False,
        "execution_type": "builtin-read-only",
        "started_at": started,
        "finished_at": now(),
        "status": "SUCCESS" if passed else "FAILED",
        "checks": checks
    }

    return result


def create_run():
    run_id = str(uuid.uuid4())

    result = self_check()

    run = {
        "run_id": run_id,
        "workflow_id": SELF_CHECK_ID,
        "status": result["status"],
        "created_at": now(),
        "result": result
    }

    run["result_sha256"] = sha256_json(
        result
    )

    run_path = RUNS / f"{run_id}.json"

    run_path.write_text(
        json.dumps(
            run,
            indent=2,
            ensure_ascii=False
        ) + "\n"
    )

    audit_event = {
        "event_id": str(uuid.uuid4()),
        "event": "workflow_run_completed",
        "timestamp": now(),
        "run_id": run_id,
        "workflow_id": SELF_CHECK_ID,
        "status": run["status"],
        "result_sha256": run["result_sha256"]
    }

    audit_event["event_sha256"] = sha256_json(
        audit_event
    )

    audit_path = AUDIT / (
        f"{run_id}.json"
    )

    audit_path.write_text(
        json.dumps(
            audit_event,
            indent=2,
            ensure_ascii=False
        ) + "\n"
    )

    run["audit"] = audit_event

    return run


def list_runs():
    items = []

    for path in sorted(
        RUNS.glob("*.json"),
        reverse=True
    ):
        try:
            items.append(
                json.loads(
                    path.read_text()
                )
            )
        except Exception:
            pass

    return items


def workflows():
    inventory = load_inventory()

    external = inventory.get(
        "workflows",
        []
    )

    self_workflow = {
        "id": SELF_CHECK_ID,
        "name": "ShadowOps Verified Self Check",
        "source": "verified_app/server.py",
        "definition_verified": True,
        "execution_verified": True,
        "status": "VERIFIED",
        "risk": "L0",
        "approval_required": False,
        "start_enabled": True
    }

    return {
        "schema": "shadowops-verified-app-v2",
        "policy": "fail-closed",
        "count": len(external) + 1,
        "execution_verified_count": 1,
        "workflows": [
            self_workflow,
            *external
        ]
    }


class Handler(BaseHTTPRequestHandler):

    server_version = "ShadowOpsVerified/2"

    def log_message(
        self,
        fmt,
        *args
    ):
        print(
            datetime.datetime.now().isoformat(
                timespec="seconds"
            ),
            fmt % args
        )

    def do_GET(self):
        parsed = urllib.parse.urlparse(
            self.path
        )

        path = parsed.path

        if path == "/health":
            return json_response(
                self,
                200,
                {
                    "status": "ok",
                    "app": "shadowops-verified"
                }
            )

        if path == "/ready":
            return json_response(
                self,
                200,
                {
                    "status": "ready",
                    "policy": "fail-closed",
                    "execution_verified": 1
                }
            )

        if path == "/api/workflows":
            return json_response(
                self,
                200,
                workflows()
            )

        if path == "/api/runs":
            return json_response(
                self,
                200,
                {
                    "runs": list_runs()
                }
            )

        if path.startswith(
            "/api/runs/"
        ):
            run_id = urllib.parse.unquote(
                path.split(
                    "/api/runs/",
                    1
                )[1]
            )

            target = RUNS / (
                f"{run_id}.json"
            )

            if not target.exists():
                return json_response(
                    self,
                    404,
                    {
                        "error":
                        "run_not_found"
                    }
                )

            return json_response(
                self,
                200,
                json.loads(
                    target.read_text()
                )
            )

        if path == "/api/audit":
            items = []

            for target in sorted(
                AUDIT.glob("*.json"),
                reverse=True
            ):
                try:
                    items.append(
                        json.loads(
                            target.read_text()
                        )
                    )
                except Exception:
                    pass

            return json_response(
                self,
                200,
                {
                    "events": items
                }
            )

        if path == "/api/system":
            return json_response(
                self,
                200,
                {
                    "name":
                    "ShadowOps Verified",
                    "mode":
                    "LOCAL_VERIFIED",
                    "port":
                    PORT,
                    "production_port":
                    4013,
                    "production_mutation":
                    False,
                    "execution_verified":
                    1
                }
            )

        if (
            path == "/"
            or path == "/index.html"
        ):
            target = STATIC / "index.html"
        else:
            target = STATIC / path.lstrip("/")

        try:
            resolved = target.resolve()

            if (
                STATIC.resolve()
                not in resolved.parents
                and resolved
                != STATIC.resolve()
            ):
                raise ValueError(
                    "outside static root"
                )

            if not resolved.is_file():
                raise FileNotFoundError()

            suffix = resolved.suffix.lower()

            content_type = {
                ".html":
                "text/html; charset=utf-8",

                ".css":
                "text/css; charset=utf-8",

                ".js":
                "application/javascript; charset=utf-8"

            }.get(
                suffix,
                "application/octet-stream"
            )

            body = resolved.read_bytes()

            self.send_response(200)
            self.send_header(
                "Content-Type",
                content_type
            )
            self.send_header(
                "Content-Length",
                str(len(body))
            )
            self.send_header(
                "Cache-Control",
                "no-store"
            )
            self.end_headers()
            self.wfile.write(body)

        except Exception:
            self.send_error(404)

    def do_POST(self):
        parsed = urllib.parse.urlparse(
            self.path
        )

        prefix = "/api/workflows/"
        suffix = "/start"

        if (
            parsed.path.startswith(prefix)
            and parsed.path.endswith(suffix)
        ):
            wf_id = urllib.parse.unquote(
                parsed.path[
                    len(prefix):
                    -len(suffix)
                ]
            ).rstrip("/")

            if wf_id == SELF_CHECK_ID:
                run = create_run()

                status = (
                    200
                    if run["status"]
                    == "SUCCESS"
                    else 500
                )

                return json_response(
                    self,
                    status,
                    run
                )

            # Alle anderen Workflows bleiben
            # fail-closed, bis sie separat E2E
            # bewiesen wurden.

            known = next(
                (
                    x
                    for x
                    in workflows()["workflows"]
                    if x["id"] == wf_id
                ),
                None
            )

            if not known:
                return json_response(
                    self,
                    404,
                    {
                        "status":
                        "BLOCKED",
                        "reason":
                        "workflow_not_found"
                    }
                )

            return json_response(
                self,
                409,
                {
                    "status":
                    "BLOCKED",
                    "workflow_id":
                    wf_id,
                    "reason":
                    "execution_not_verified",
                    "policy":
                    "fail-closed"
                }
            )

        return json_response(
            self,
            404,
            {
                "error": "not_found"
            }
        )


if __name__ == "__main__":
    print(
        f"SHADOWOPS_VERIFIED="
        f"http://{HOST}:{PORT}"
    )

    print(
        "VERIFIED_EXECUTION_WORKFLOWS=1"
    )

    print(
        "PRODUCTION_4013_MUTATION=NO"
    )

    ThreadingHTTPServer(
        (HOST, PORT),
        Handler
    ).serve_forever()
