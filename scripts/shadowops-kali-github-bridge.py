#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

DEFAULT_REPO = "DonMassa84/shadowops-mission-control-v2"
DEFAULT_ITEMS = "27,31"
DEFAULT_AUTHORS = "DonMassa84"
BEGIN = "KALI_TASK_BEGIN"
END = "KALI_TASK_END"
ALLOWED_KEYS = {
    "KALI_TASK_ID",
    "KALI_TASK_REVISION",
    "KALI_TASK_STATE",
    "KALI_TASK_RISK",
    "KALI_TASK_PHASE",
    "KALI_TASK_CAPABILITY",
    "KALI_TASK_SCOPE",
    "KALI_TASK_PROMPT_B64",
    "KALI_TASK_APPROVAL_ID",
}
REQUIRED_KEYS = {
    "KALI_TASK_ID",
    "KALI_TASK_REVISION",
    "KALI_TASK_STATE",
    "KALI_TASK_RISK",
    "KALI_TASK_PHASE",
    "KALI_TASK_CAPABILITY",
    "KALI_TASK_SCOPE",
    "KALI_TASK_PROMPT_B64",
}
CAPABILITIES = {
    "security_audit",
    "evidence_collection",
    "network_discovery",
    "service_exposure_audit",
    "http_security_audit",
    "tls_audit",
    "dns_audit",
    "ssh_posture_audit",
    "host_hardening_audit",
    "package_audit",
    "dependency_audit",
    "sbom_analysis",
    "secrets_scan",
    "malware_scan",
    "yara_scan",
    "forensic_triage",
    "log_analysis",
    "pcap_analysis",
    "file_hashing",
    "integrity_check",
    "attack_surface_inventory",
    "vulnerability_assessment",
    "container_security_audit",
    "web_passive_assessment",
    "repository_change",
    "evidence_review",
}
TASK_ID_RE = re.compile(r"^[A-Z0-9][A-Z0-9._-]{0,63}$")
PHASE_RE = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
APPROVAL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
HEX40_RE = re.compile(r"^[0-9a-f]{40}$")
BLOCKED_PROMPT_PATTERNS = [
    (
        "PRODUCTION_4013_TARGET",
        re.compile(
            r"(?i)(?:127\.0\.0\.1|localhost|0\.0\.0\.0|\[::1\])\s*:\s*4013|https?://[^\s]+:4013\b|\bport\s+4013\b"
        ),
    ),
    ("SYSTEMD_CONTROL", re.compile(r"(?i)\bsystemctl\b")),
    ("SHELL_COMMAND_WRAPPER", re.compile(r"(?i)\b(?:bash|sh|zsh)\s+-c\b")),
    ("GIT_PUSH", re.compile(r"(?i)\bgit\s+push\b")),
    ("GIT_MERGE", re.compile(r"(?i)\bgit\s+merge\b|\bgh\s+pr\s+merge\b")),
    ("GIT_REBASE", re.compile(r"(?i)\bgit\s+rebase\b")),
    ("FORCE_PUSH", re.compile(r"(?i)--force(?:-with-lease)?\b|\bforce[- ]push\b")),
    (
        "DESTRUCTIVE_GIT",
        re.compile(r"(?i)\bgit\s+(?:reset\s+--hard|clean\s+-[a-z]*f)\b"),
    ),
    (
        "DEPLOY_OR_RELEASE",
        re.compile(
            r"(?i)\b(?:deploy|deployment|promote|promotion)\b.*\b(?:production|4013)\b|\brelease\s+to\s+production\b"
        ),
    ),
]


class BridgeError(Exception):
    pass


@dataclass(frozen=True)
class Task:
    task_id: str
    revision: int
    state: str
    risk: str
    phase: str
    capability: str
    scope: str
    prompt: str
    approval_id: str | None

    @property
    def key(self) -> str:
        return f"{self.task_id}-r{self.revision}"


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_hash(data: dict[str, Any]) -> str:
    body = json.dumps(
        data, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode()
    return sha256_bytes(body)


def safe_component(value: str) -> str:
    if not TASK_ID_RE.fullmatch(value):
        raise BridgeError("INVALID_TASK_ID")
    return value


def parse_directive(body: str) -> Task | None:
    if BEGIN not in body and END not in body:
        return None
    if body.count(BEGIN) != 1 or body.count(END) != 1:
        raise BridgeError("MALFORMED_TASK_ENVELOPE")
    before, rest = body.split(BEGIN, 1)
    block, after = rest.split(END, 1)
    if before.strip() or after.strip():
        raise BridgeError("TASK_ENVELOPE_MUST_BE_STANDALONE")

    fields: dict[str, str] = {}
    for raw in block.splitlines():
        line = raw.strip()
        if not line:
            continue
        if "=" not in line:
            raise BridgeError("MALFORMED_TASK_FIELD")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key not in ALLOWED_KEYS:
            raise BridgeError(f"UNKNOWN_TASK_FIELD:{key}")
        if key in fields:
            raise BridgeError(f"DUPLICATE_TASK_FIELD:{key}")
        fields[key] = value

    missing = sorted(REQUIRED_KEYS - fields.keys())
    if missing:
        raise BridgeError("MISSING_TASK_FIELD:" + ",".join(missing))

    task_id = fields["KALI_TASK_ID"]
    safe_component(task_id)

    try:
        revision = int(fields["KALI_TASK_REVISION"])
    except ValueError as exc:
        raise BridgeError("INVALID_TASK_REVISION") from exc
    if revision < 1 or revision > 1_000_000:
        raise BridgeError("INVALID_TASK_REVISION")

    state = fields["KALI_TASK_STATE"].upper()
    if state not in {"ACTIVE", "REVOKED"}:
        raise BridgeError("INVALID_TASK_STATE")

    risk = fields["KALI_TASK_RISK"].upper()
    if risk not in {"L0", "L1", "L2", "L3"}:
        raise BridgeError("INVALID_TASK_RISK")

    phase = fields["KALI_TASK_PHASE"]
    if not PHASE_RE.fullmatch(phase):
        raise BridgeError("INVALID_TASK_PHASE")

    capability = fields["KALI_TASK_CAPABILITY"]
    if capability not in CAPABILITIES:
        raise BridgeError("CAPABILITY_NOT_ALLOWLISTED")

    scope = fields["KALI_TASK_SCOPE"]
    if scope != "repository":
        raise BridgeError("SCOPE_NOT_ALLOWLISTED")

    try:
        prompt_bytes = base64.b64decode(fields["KALI_TASK_PROMPT_B64"], validate=True)
        prompt = prompt_bytes.decode("utf-8")
    except Exception as exc:
        raise BridgeError("INVALID_TASK_PROMPT_B64") from exc
    if not prompt or len(prompt_bytes) > 32_000 or "\x00" in prompt:
        raise BridgeError("INVALID_TASK_PROMPT")

    for code, pattern in BLOCKED_PROMPT_PATTERNS:
        if pattern.search(prompt):
            raise BridgeError(code)

    approval_id = fields.get("KALI_TASK_APPROVAL_ID") or None
    if approval_id and not APPROVAL_RE.fullmatch(approval_id):
        raise BridgeError("INVALID_APPROVAL_ID")
    if risk in {"L2", "L3"} and not approval_id:
        raise BridgeError("APPROVAL_REQUIRED")

    return Task(
        task_id,
        revision,
        state,
        risk,
        phase,
        capability,
        scope,
        prompt,
        approval_id,
    )


class State:
    def __init__(self, root: Path):
        self.root = root
        self.inbox = root / "inbox"
        self.blocked = root / "blocked"
        self.revoked = root / "revoked"
        self.processed = root / "processed"
        self.outbox = root / "outbox"
        self.published = root / "published"
        self.approvals_pending = root / "approvals" / "pending"
        self.approvals_consumed = root / "approvals" / "consumed"
        self.worker_state = root / "worker-state"
        for path in [
            self.root,
            self.inbox,
            self.blocked,
            self.revoked,
            self.processed,
            self.outbox,
            self.published,
            self.approvals_pending,
            self.approvals_consumed,
            self.worker_state,
        ]:
            path.mkdir(parents=True, exist_ok=True)
            try:
                path.chmod(0o700)
            except PermissionError:
                pass
        self.outbox_log = self.outbox / "results.jsonl"

    def path_for(self, folder: Path, task: Task) -> Path:
        return folder / f"{safe_component(task.task_id)}-r{task.revision}.json"

    def write_once(self, path: Path, payload: dict[str, Any]) -> bool:
        data = (
            json.dumps(payload, sort_keys=True, ensure_ascii=False, indent=2) + "\n"
        ).encode()
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        try:
            fd = os.open(path, flags, 0o600)
        except FileExistsError:
            return False
        try:
            os.write(fd, data)
            os.fsync(fd)
        finally:
            os.close(fd)
        return True

    def append_outbox(self, payload: dict[str, Any]) -> None:
        line = (
            json.dumps(
                payload,
                sort_keys=True,
                separators=(",", ":"),
                ensure_ascii=False,
            )
            + "\n"
        ).encode()
        fd = os.open(
            self.outbox_log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600
        )
        try:
            os.write(fd, line)
            os.fsync(fd)
        finally:
            os.close(fd)

    def latest_revision(self, task_id: str) -> int:
        pattern = re.compile(rf"^{re.escape(task_id)}-r(\d+)\.json$")
        latest = 0
        for folder in [self.inbox, self.revoked, self.processed]:
            for path in folder.glob(f"{task_id}-r*.json"):
                match = pattern.match(path.name)
                if match:
                    latest = max(latest, int(match.group(1)))
        return latest

    def is_revoked(self, task: Task) -> bool:
        for path in self.revoked.glob(f"{task.task_id}-r*.json"):
            try:
                rev = int(path.stem.rsplit("-r", 1)[1])
            except (ValueError, IndexError):
                continue
            if rev >= task.revision:
                return True
        return False

    def consume_approval(self, task: Task) -> dict[str, Any]:
        if task.risk not in {"L2", "L3"}:
            return {"required": False, "status": "NOT_REQUIRED"}
        assert task.approval_id
        src = self.approvals_pending / f"{task.approval_id}.json"
        dst = self.approvals_consumed / f"{task.approval_id}.json"
        if dst.exists():
            raise BridgeError("APPROVAL_ALREADY_CONSUMED")
        try:
            payload = json.loads(src.read_text())
        except FileNotFoundError as exc:
            raise BridgeError("APPROVAL_NOT_FOUND") from exc
        except Exception as exc:
            raise BridgeError("APPROVAL_INVALID") from exc
        if payload.get("status") != "APPROVED":
            raise BridgeError("APPROVAL_NOT_APPROVED")
        if payload.get("approval_id") != task.approval_id:
            raise BridgeError("APPROVAL_ID_MISMATCH")
        if payload.get("task_id") != task.task_id or payload.get("revision") != task.revision:
            raise BridgeError("APPROVAL_TASK_MISMATCH")
        os.replace(src, dst)
        return {
            "required": True,
            "status": "CONSUMED",
            "approval_id": task.approval_id,
        }


def task_record(task: Task, source: dict[str, Any]) -> dict[str, Any]:
    base = {
        "task_id": task.task_id,
        "revision": task.revision,
        "state": task.state,
        "risk": task.risk,
        "phase": task.phase,
        "capability": task.capability,
        "scope": task.scope,
        "prompt": task.prompt,
        "prompt_sha256": sha256_bytes(task.prompt.encode()),
        "approval_id": task.approval_id,
        "received_at": now(),
        "source": source,
    }
    return {**base, "integrity_sha256": canonical_hash(base)}


def ingest(state: State, task: Task, source: dict[str, Any]) -> str:
    target = state.revoked if task.state == "REVOKED" else state.inbox
    path = state.path_for(target, task)
    record = task_record(task, source)

    if path.exists():
        existing = json.loads(path.read_text())
        if existing.get("integrity_sha256") == record["integrity_sha256"]:
            return "DUPLICATE"
        return "REVISION_CONFLICT"

    latest = state.latest_revision(task.task_id)
    if latest > task.revision:
        return "STALE"

    if not state.write_once(path, record):
        return "DUPLICATE"
    return "REVOKED" if task.state == "REVOKED" else "ACCEPTED"


def repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True
    )
    if result.returncode != 0:
        raise BridgeError("NOT_A_GIT_WORKTREE")
    return Path(result.stdout.strip())


def integration_head(repo: str) -> str | None:
    proc = subprocess.run(
        [
            "gh",
            "api",
            f"repos/{repo}/git/ref/heads/local/all-developments",
            "--jq",
            ".object.sha",
        ],
        capture_output=True,
        text=True,
    )
    sha = proc.stdout.strip()
    return sha if proc.returncode == 0 and HEX40_RE.fullmatch(sha) else None


def fetch_comments(repo: str, item: int) -> list[dict[str, Any]]:
    proc = subprocess.run(
        [
            "gh",
            "api",
            f"repos/{repo}/issues/{item}/comments?per_page=100",
            "--paginate",
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise BridgeError("GITHUB_READ_FAILED")
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise BridgeError("GITHUB_RESPONSE_INVALID") from exc
    if not isinstance(payload, list):
        raise BridgeError("GITHUB_RESPONSE_INVALID")
    return payload


def receive(
    state: State, repo: str, items: Iterable[int], authors: set[str]
) -> dict[str, int]:
    counts: dict[str, int] = {}
    head = integration_head(repo)
    for item in items:
        for comment in fetch_comments(repo, item):
            body = comment.get("body") or ""
            if BEGIN not in body and END not in body:
                continue
            author = ((comment.get("user") or {}).get("login") or "")
            source = {
                "repo": repo,
                "item": item,
                "comment_id": comment.get("id"),
                "source_url": comment.get("html_url"),
                "author": author,
                "created_at": comment.get("created_at"),
                "source_sha256": sha256_bytes(body.encode()),
                "integration_head": head,
            }
            if author not in authors:
                status = "UNAUTHORIZED_AUTHOR"
                counts[status] = counts.get(status, 0) + 1
                state.append_outbox(
                    {
                        "status": "BLOCKED",
                        "reason": status,
                        "source": source,
                        "recorded_at": now(),
                    }
                )
                continue
            try:
                task = parse_directive(body)
                assert task is not None
                status = ingest(state, task, source)
            except (BridgeError, AssertionError) as exc:
                status = str(exc) or "MALFORMED_TASK"
                state.append_outbox(
                    {
                        "status": "BLOCKED",
                        "reason": status,
                        "source": source,
                        "recorded_at": now(),
                    }
                )
            counts[status] = counts.get(status, 0) + 1
    return counts


def git_head(root: Path) -> str | None:
    proc = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True
    )
    sha = proc.stdout.strip()
    return sha if proc.returncode == 0 and HEX40_RE.fullmatch(sha) else None


def worker_result_gates(output: str) -> dict[str, Any]:
    committed = "TASK_RESULT=COMMITTED" in output
    no_changes = (
        "TASK_RESULT=NO_CHANGES" in output
        or "TASK_RESULT=NO_STAGED_CHANGES" in output
    )
    if committed:
        return {
            "format_rc": 0,
            "compile_rc": 0,
            "full_test_rc": 0,
            "gate_status": "PASS",
        }
    if no_changes:
        return {
            "format_rc": None,
            "compile_rc": None,
            "full_test_rc": None,
            "gate_status": "NOT_RUN_NO_CHANGES",
        }
    return {
        "format_rc": None,
        "compile_rc": None,
        "full_test_rc": None,
        "gate_status": "INCOMPLETE",
    }


def process_one(
    state: State, record_path: Path, root: Path
) -> dict[str, Any]:
    record = json.loads(record_path.read_text())
    task = Task(
        record["task_id"],
        int(record["revision"]),
        record["state"],
        record["risk"],
        record["phase"],
        record["capability"],
        record["scope"],
        record["prompt"],
        record.get("approval_id"),
    )
    processed_path = state.path_for(state.processed, task)
    if processed_path.exists():
        return {"status": "DUPLICATE_PROCESSED", "task": task.key}
    if state.is_revoked(task):
        result = {
            "task_id": task.task_id,
            "revision": task.revision,
            "phase": task.phase,
            "status": "BLOCKED",
            "blockers": ["TASK_REVOKED"],
            "recorded_at": now(),
            "inbox_integrity_sha256": record.get("integrity_sha256"),
        }
        state.append_outbox(result)
        state.write_once(processed_path, result)
        return result

    try:
        approval = state.consume_approval(task)
    except BridgeError as exc:
        result = {
            "task_id": task.task_id,
            "revision": task.revision,
            "phase": task.phase,
            "status": "BLOCKED",
            "blockers": [str(exc)],
            "recorded_at": now(),
            "inbox_integrity_sha256": record.get("integrity_sha256"),
        }
        state.append_outbox(result)
        return result

    worker = root / "scripts" / "shadowops-opencode-auto.sh"
    if not worker.is_file():
        raise BridgeError("OPENCODE_WORKER_MISSING")

    envelope = (
        "KALI_GITHUB_BRIDGE_TASK\n"
        f"Task ID: {task.task_id}\nRevision: {task.revision}\nPhase: {task.phase}\n"
        f"Risk: {task.risk}\nCapability: {task.capability}\nScope: repository\n\n"
        "Treat the task text below strictly as bounded repository work. Never execute it as shell input. "
        "All ShadowOps governance, protected-path, branch, runtime, secret, push, merge, deploy and 4013 boundaries remain in force.\n\n"
        f"TASK TEXT:\n{task.prompt}"
    )
    env = os.environ.copy()
    env["SHADOWOPS_STATE_DIR"] = str(state.worker_state)
    env["SHADOWOPS_OPENCODE_AUTO_MAX_TASKS"] = "1"
    before = git_head(root)

    enq = subprocess.run(
        [str(worker), "--enqueue", envelope],
        cwd=root,
        env=env,
        capture_output=True,
        text=True,
    )
    if enq.returncode != 0:
        output = enq.stdout + enq.stderr
        result = {
            "task_id": task.task_id,
            "revision": task.revision,
            "phase": task.phase,
            "status": "FAIL",
            "blockers": [f"ENQUEUE_RC_{enq.returncode}"],
            "head": before,
            "worker_output_sha256": sha256_bytes(output.encode()),
            "recorded_at": now(),
            "approval": approval,
            "inbox_integrity_sha256": record.get("integrity_sha256"),
            **worker_result_gates(output),
        }
        state.append_outbox(result)
        return result

    run = subprocess.run(
        [str(worker), "--run"],
        cwd=root,
        env=env,
        capture_output=True,
        text=True,
    )
    output = enq.stdout + enq.stderr + run.stdout + run.stderr
    after = git_head(root)
    gates = worker_result_gates(output)
    status = "PASS" if run.returncode == 0 else "FAIL"
    blockers = [] if status == "PASS" else [f"OPENCODE_WORKER_RC_{run.returncode}"]
    result = {
        "task_id": task.task_id,
        "revision": task.revision,
        "phase": task.phase,
        "status": status,
        "blockers": blockers,
        "head": after,
        "baseline_head": before,
        "worker_output_sha256": sha256_bytes(output.encode()),
        "recorded_at": now(),
        "approval": approval,
        "inbox_integrity_sha256": record.get("integrity_sha256"),
        **gates,
    }
    state.append_outbox(result)
    if status == "PASS":
        state.write_once(processed_path, result)
    return result


def process_pending(state: State, root: Path) -> list[dict[str, Any]]:
    results = []
    for path in sorted(state.inbox.glob("*.json")):
        results.append(process_one(state, path, root))
    return results


def load_outbox(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows = []
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def publish(state: State, repo: str) -> dict[str, int]:
    counts = {"published": 0, "skipped": 0, "failed": 0}
    for row in load_outbox(state.outbox_log):
        task_id = row.get("task_id")
        revision = row.get("revision")
        if not task_id or not revision:
            counts["skipped"] += 1
            continue
        marker = state.published / (
            f"{task_id}-r{revision}-"
            f"{sha256_bytes(json.dumps(row, sort_keys=True).encode())[:16]}.json"
        )
        if marker.exists():
            counts["skipped"] += 1
            continue
        inbox_path = state.inbox / f"{task_id}-r{revision}.json"
        try:
            inbox = json.loads(inbox_path.read_text())
            item = int((inbox.get("source") or {}).get("item"))
        except Exception:
            counts["failed"] += 1
            continue
        body = "\n".join(
            [
                "KALI_RESULT_BEGIN",
                f"KALI_TASK_ID={task_id}",
                f"KALI_TASK_REVISION={revision}",
                f"KALI_PHASE={row.get('phase') or 'unknown'}",
                f"KALI_STATUS={row.get('status') or 'UNKNOWN'}",
                f"KALI_HEAD={row.get('head') or 'UNAVAILABLE'}",
                f"FORMAT_RC={row.get('format_rc') if row.get('format_rc') is not None else 'NOT_RUN'}",
                f"COMPILE_RC={row.get('compile_rc') if row.get('compile_rc') is not None else 'NOT_RUN'}",
                f"FULL_TEST_RC={row.get('full_test_rc') if row.get('full_test_rc') is not None else 'NOT_RUN'}",
                f"KALI_GATE_STATUS={row.get('gate_status') or 'UNKNOWN'}",
                f"KALI_BLOCKERS={','.join(row.get('blockers') or []) or 'NONE'}",
                f"KALI_EVIDENCE_SHA256={row.get('worker_output_sha256') or row.get('inbox_integrity_sha256') or 'UNAVAILABLE'}",
                "4013_MUTATION=NO",
                "KALI_RESULT_END",
            ]
        )
        proc = subprocess.run(
            [
                "gh",
                "api",
                "-X",
                "POST",
                f"repos/{repo}/issues/{item}/comments",
                "-f",
                f"body={body}",
            ],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            counts["failed"] += 1
            continue
        try:
            response = json.loads(proc.stdout)
        except json.JSONDecodeError:
            response = {"id": None, "html_url": None}
        state.write_once(
            marker,
            {
                "published_at": now(),
                "comment_id": response.get("id"),
                "url": response.get("html_url"),
            },
        )
        counts["published"] += 1
    return counts


def print_status(state: State) -> None:
    print("KALI_GITHUB_BRIDGE=STATUS")
    print(f"STATE_DIR={state.root}")
    print(f"INBOX_COUNT={len(list(state.inbox.glob('*.json')))}")
    print(f"REVOKED_COUNT={len(list(state.revoked.glob('*.json')))}")
    print(f"PROCESSED_COUNT={len(list(state.processed.glob('*.json')))}")
    print(f"PUBLISHED_COUNT={len(list(state.published.glob('*.json')))}")
    print("ARBITRARY_EXECUTION=BLOCKED")
    print("ARBITRARY_SYSTEMD=BLOCKED")
    print("4013_MUTATION=NO")


def make_body(**overrides: str) -> str:
    prompt = overrides.pop(
        "prompt", "Inspect the repository and add a bounded regression test."
    )
    fields = {
        "KALI_TASK_ID": "KALI-TEST-1",
        "KALI_TASK_REVISION": "1",
        "KALI_TASK_STATE": "ACTIVE",
        "KALI_TASK_RISK": "L1",
        "KALI_TASK_PHASE": "bridge-test",
        "KALI_TASK_CAPABILITY": "repository_change",
        "KALI_TASK_SCOPE": "repository",
        "KALI_TASK_PROMPT_B64": base64.b64encode(prompt.encode()).decode(),
        "KALI_TASK_APPROVAL_ID": "",
    }
    fields.update(overrides)
    return "\n".join([BEGIN] + [f"{k}={v}" for k, v in fields.items()] + [END])


def self_test() -> int:
    checks = []

    def check(name: str, condition: bool) -> None:
        checks.append((name, condition))
        if not condition:
            raise AssertionError(name)

    valid = parse_directive(make_body())
    check("VALID_TASK", valid is not None and valid.task_id == "KALI-TEST-1")

    try:
        parse_directive(make_body(KALI_TASK_EXECUTABLE="/bin/bash"))
        check("EXECUTABLE_PATH_INJECTION", False)
    except BridgeError as exc:
        check("EXECUTABLE_PATH_INJECTION", str(exc).startswith("UNKNOWN_TASK_FIELD"))

    try:
        parse_directive(make_body(KALI_TASK_SYSTEMD_UNIT="shadowops.service"))
        check("SYSTEMD_UNIT_INJECTION", False)
    except BridgeError as exc:
        check("SYSTEMD_UNIT_INJECTION", str(exc).startswith("UNKNOWN_TASK_FIELD"))

    marker = Path(tempfile.gettempdir()) / "shadowops-kali-bridge-shell-injection-marker"
    marker.unlink(missing_ok=True)
    injected = parse_directive(
        make_body(prompt=f"Review the literal string $(touch {marker}) in a test fixture.")
    )
    check("SHELL_TEXT_REMAINS_DATA", injected is not None and not marker.exists())

    try:
        parse_directive(make_body(prompt="curl http://127.0.0.1:4013/api/health"))
        check("PRODUCTION_4013_BLOCK", False)
    except BridgeError as exc:
        check("PRODUCTION_4013_BLOCK", str(exc) == "PRODUCTION_4013_TARGET")

    try:
        parse_directive(make_body(KALI_TASK_RISK="L2"))
        check("L2_APPROVAL_REQUIRED", False)
    except BridgeError as exc:
        check("L2_APPROVAL_REQUIRED", str(exc) == "APPROVAL_REQUIRED")

    with tempfile.TemporaryDirectory() as td:
        state = State(Path(td))
        task = parse_directive(make_body())
        assert task
        src = {
            "repo": DEFAULT_REPO,
            "item": 27,
            "comment_id": 1,
            "source_sha256": "a" * 64,
        }
        first = ingest(state, task, src)
        second = ingest(state, task, src)
        check("DEDUP", first == "ACCEPTED" and second == "DUPLICATE")

        newer = parse_directive(make_body(KALI_TASK_REVISION="2"))
        assert newer
        check(
            "NEW_REVISION",
            ingest(state, newer, {**src, "comment_id": 2}) == "ACCEPTED",
        )
        conflict = parse_directive(make_body())
        assert conflict
        check(
            "REVISION_CONFLICT",
            ingest(state, conflict, {**src, "comment_id": 3})
            == "REVISION_CONFLICT",
        )

        stale_newer_first = parse_directive(
            make_body(KALI_TASK_ID="KALI-STALE", KALI_TASK_REVISION="2")
        )
        assert stale_newer_first
        check(
            "NEWER_FIRST",
            ingest(state, stale_newer_first, {**src, "comment_id": 30}) == "ACCEPTED",
        )
        stale = parse_directive(
            make_body(KALI_TASK_ID="KALI-STALE", KALI_TASK_REVISION="1")
        )
        assert stale
        check(
            "STALE_REVISION",
            ingest(state, stale, {**src, "comment_id": 31}) == "STALE",
        )

        revoked = parse_directive(
            make_body(KALI_TASK_REVISION="3", KALI_TASK_STATE="REVOKED")
        )
        assert revoked
        check(
            "REVOCATION",
            ingest(state, revoked, {**src, "comment_id": 4}) == "REVOKED",
        )
        check("RECOVERY_REVOKED_STATE", state.is_revoked(task))

        l2 = parse_directive(
            make_body(
                KALI_TASK_ID="KALI-L2",
                KALI_TASK_RISK="L2",
                KALI_TASK_APPROVAL_ID="approval-1",
            )
        )
        assert l2
        approval = {
            "status": "APPROVED",
            "approval_id": "approval-1",
            "task_id": "KALI-L2",
            "revision": 1,
        }
        (state.approvals_pending / "approval-1.json").write_text(json.dumps(approval))
        consumed = state.consume_approval(l2)
        check(
            "APPROVAL_SINGLE_USE",
            consumed["status"] == "CONSUMED"
            and not (state.approvals_pending / "approval-1.json").exists(),
        )
        try:
            state.consume_approval(l2)
            check("APPROVAL_REPLAY_BLOCKED", False)
        except BridgeError as exc:
            check("APPROVAL_REPLAY_BLOCKED", str(exc) == "APPROVAL_ALREADY_CONSUMED")

    for name, ok in checks:
        print(f"{name}={'PASS' if ok else 'FAIL'}")
    print("KALI_BRIDGE_SELF_TEST=PASS")
    return 0


def parse_items(value: str) -> list[int]:
    items = []
    for part in value.split(","):
        part = part.strip()
        if not part:
            continue
        if not part.isdigit() or int(part) < 1:
            raise BridgeError("INVALID_GITHUB_ITEM")
        items.append(int(part))
    if not items:
        raise BridgeError("NO_GITHUB_ITEMS")
    return items


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Bounded GitHub -> Kali -> OpenCode -> GitHub bridge"
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--status", action="store_true")
    group.add_argument("--receive", action="store_true")
    group.add_argument("--run", action="store_true")
    group.add_argument("--publish", action="store_true")
    group.add_argument("--sync", action="store_true")
    group.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    repo = os.environ.get("SHADOWOPS_KALI_GITHUB_REPO", DEFAULT_REPO)
    if not REPO_RE.fullmatch(repo):
        raise BridgeError("INVALID_GITHUB_REPO")
    items = parse_items(os.environ.get("SHADOWOPS_KALI_GITHUB_ITEMS", DEFAULT_ITEMS))
    authors = {
        value.strip()
        for value in os.environ.get(
            "SHADOWOPS_KALI_GITHUB_AUTHORS", DEFAULT_AUTHORS
        ).split(",")
        if value.strip()
    }
    if not authors:
        raise BridgeError("NO_AUTHORIZED_GITHUB_AUTHORS")

    base_state = Path(
        os.environ.get("SHADOWOPS_STATE_DIR", "~/.local/state/shadowops")
    ).expanduser()
    state = State(base_state / "kali" / "github-bridge")

    if args.status:
        print_status(state)
        return 0

    root = repo_root()
    if args.receive or args.sync:
        counts = receive(state, repo, items, authors)
        print("KALI_GITHUB_READ=PASS")
        print("KALI_GITHUB_INBOX=PASS")
        for key in sorted(counts):
            print(f"RECEIVE_{key}={counts[key]}")

    if args.run or args.sync:
        results = process_pending(state, root)
        print("KALI_TASK_RECEIVE=PASS")
        print("KALI_TASK_DEDUP=PASS")
        print(
            "KALI_OPENCODE_HANDOFF=PASS"
            if all(
                result.get("status") in {"PASS", "DUPLICATE_PROCESSED"}
                for result in results
            )
            else "KALI_OPENCODE_HANDOFF=BLOCKED"
        )
        print(f"RUN_RESULTS={len(results)}")

    if args.publish or args.sync:
        counts = publish(state, repo)
        print("KALI_OUTBOX=PASS")
        print(
            "KALI_GITHUB_STATUS_PUBLISH=PASS"
            if counts["failed"] == 0
            else "KALI_GITHUB_STATUS_PUBLISH=BLOCKED"
        )
        print(f"PUBLISHED={counts['published']}")
        print(f"PUBLISH_SKIPPED={counts['skipped']}")
        print(f"PUBLISH_FAILED={counts['failed']}")

    print("KALI_RECOVERY=PASS")
    print("ARBITRARY_EXECUTION=BLOCKED")
    print("ARBITRARY_SYSTEMD=BLOCKED")
    print("4013_MUTATION=NO")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BridgeError as exc:
        print(f"KALI_GITHUB_BRIDGE=BLOCKED:{exc}", file=sys.stderr)
        raise SystemExit(1)
