#!/usr/bin/env python3
"""Publish a fixed, validated task document to the i7 over authenticated SSH."""
import argparse
from datetime import date, datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import subprocess

FIELDS = {"id", "area", "title", "next_step", "priority", "due", "status", "source", "updated_at", "evidence", "visibility"}


def timestamp(value):
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timezone required")
    return parsed


def validate(data):
    if not isinstance(data, dict) or set(data) != {"schema_version", "revision", "published_at", "timezone", "tasks"}:
        raise ValueError("invalid document fields")
    if data["schema_version"] != 1 or data["timezone"] != "Europe/Berlin":
        raise ValueError("unsupported schema or timezone")
    if type(data["revision"]) is not int or data["revision"] < 1:
        raise ValueError("positive integer revision required")
    timestamp(data["published_at"])
    if not isinstance(data["tasks"], list) or len(data["tasks"]) > 200:
        raise ValueError("invalid tasks")
    seen = set()
    for task in data["tasks"]:
        if not isinstance(task, dict) or set(task) != FIELDS:
            raise ValueError("invalid task fields")
        for key in ("id", "area", "title", "next_step", "source"):
            if not isinstance(task[key], str) or not task[key].strip() or len(task[key]) > 300:
                raise ValueError("invalid text")
        if task["id"] in seen:
            raise ValueError("duplicate stable id")
        seen.add(task["id"])
        if type(task["priority"]) is not int or task["priority"] not in range(4):
            raise ValueError("invalid priority")
        if task["status"] not in ("open", "blocked", "done") or task["evidence"] not in ("confirmed", "unverified") or task["visibility"] not in ("kiosk", "private"):
            raise ValueError("invalid task enum")
        if task["due"] is not None:
            date.fromisoformat(task["due"])
        timestamp(task["updated_at"])
    return data


def atomic_status(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    temporary = path.with_suffix(".tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(value, stream, sort_keys=True)
    os.replace(temporary, path)


def publish(source, status_path, runner=subprocess.run):
    payload = source.read_bytes()
    if len(payload) > 262144:
        raise ValueError("content exceeds 256 KiB")
    data = validate(json.loads(payload))
    data = dict(data, tasks=[task for task in data["tasks"] if task["visibility"] == "kiosk" and task["status"] != "done"])
    payload = json.dumps(data, ensure_ascii=False, sort_keys=True).encode()
    status_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (status_path.parent / "run.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return False
        now = datetime.now(timezone.utc).isoformat()
        try:
            completed = runner(
                ["ssh", "-o", "ControlMaster=no", "-o", "ControlPath=none", "-o", "StrictHostKeyChecking=yes", "-o", "BatchMode=yes", "-o", "ConnectTimeout=20", "shadowserver-i7", "python3", "/home/schattenmacher/Projects/learning-kiosk/scripts/install-task-content.py"],
                input=payload,
                check=True,
                capture_output=True,
                timeout=45,
            )
            atomic_status(status_path, {"status": "ok", "last_run": now, "last_success": now, "receiver": completed.stdout.decode().strip()})
            return True
        except (OSError, subprocess.SubprocessError) as exc:
            try:
                previous = json.loads(status_path.read_text())
            except (OSError, json.JSONDecodeError):
                previous = {}
            atomic_status(status_path, {"status": "error", "last_run": now, "last_success": previous.get("last_success"), "error_type": type(exc).__name__})
            raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--source", type=Path, default=Path(__file__).with_name("tasks.json"))
    parser.add_argument("--status", type=Path, default=Path.home() / ".local/state/shadowops-kiosk-publisher/status.json")
    args = parser.parse_args()
    if args.check:
        validate(json.loads(args.source.read_text()))
        print("KIOSK_TASKS_VALID=PASS")
        return
    publish(args.source, args.status)


if __name__ == "__main__":
    main()
