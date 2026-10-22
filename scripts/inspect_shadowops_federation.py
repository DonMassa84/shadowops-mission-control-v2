#!/usr/bin/env python3
"""Local-only, fail-closed adapter for private ShadowOps Federation report v1.

Reads a private report from an EXTERNAL path; prints only bounded aggregates.
No network, subprocess, filesystem writes, PR actions or local-agent execution.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys

ROUTES = {"human_review", "github_review", "web_qa", "opencode_or_codex_offline"}
PRIORITIES = {"P0", "P1", "P2", "P3"}


def safe_summary(payload: object, now: datetime | None = None) -> dict:
    if not isinstance(payload, dict) or payload.get("schema_version") != 1:
        raise ValueError("Unsupported private artifact schema")
    stamp = payload.get("generated_utc")
    if not isinstance(stamp, str):
        raise ValueError("Missing snapshot evidence timestamp")
    try:
        generated = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except ValueError:
        raise ValueError("Invalid snapshot evidence timestamp") from None
    if generated.tzinfo is None:
        raise ValueError("Unzoned snapshot evidence timestamp")
    current = now if now is not None else datetime.now(timezone.utc)
    if current.tzinfo is None:
        raise ValueError("Unzoned current time")
    age = current.astimezone(timezone.utc) - generated.astimezone(timezone.utc)
    if age > timedelta(hours=48) or age < -timedelta(minutes=10):
        raise ValueError("Stale or future-dated private snapshot")
    policy = payload.get("policy")
    if not isinstance(policy, dict) or policy.get("mode") != "READ_ONLY":
        raise ValueError("Missing read-only policy")
    for flag in ("local_agent_execution", "auto_merge", "auto_deploy", "auto_email",
                 "project_execution_allowed"):
        if policy.get(flag) is not False:
            raise ValueError("Unsafe or missing policy field: " + flag)
    boundary = payload.get("ihk_boundary")
    if not isinstance(boundary, dict) or boundary.get("release_allowed") is not False:
        raise ValueError("IHK release gate missing or open")
    repos = payload.get("repositories")
    websites = payload.get("websites")
    tasks = payload.get("handoff_proposals")
    if not isinstance(repos, list) or len(repos) > 12:
        raise ValueError("Invalid repository list")
    if not isinstance(websites, list) or len(websites) > 2:
        raise ValueError("Invalid website list")
    if not isinstance(tasks, list) or len(tasks) > 100:
        raise ValueError("Invalid task list")
    for item in repos:
        if not isinstance(item, dict) or item.get("access") not in ("OK", "UNKNOWN"):
            raise ValueError("Invalid repository access state")
        if item.get("access") == "OK" and not isinstance(item.get("repository"), str):
            raise ValueError("Invalid repository record")
    for item in websites:
        if not isinstance(item, dict) or not isinstance(item.get("state"), str):
            raise ValueError("Invalid website record")
    for task in tasks:
        if (not isinstance(task, dict) or task.get("status") != "PROPOSAL_ONLY"
                or task.get("requires_operator_approval") is not True
                or task.get("execution_permitted") is not False
                or task.get("route") not in ROUTES
                or task.get("priority") not in PRIORITIES):
            raise ValueError("Unsafe handoff task")
    # The output deliberately excludes repository names, PR titles/IDs,
    # private URLs, paths, dates, project evidence and original task texts.
    return {
        "schema_version": 1,
        "source": "private_shadowops_federation_artifact",
        "ihk": "EXPECTED_PRE_PROJECT" if boundary.get("state") == "EXPECTED_PRE_PROJECT" else "BLOCKED_UNVERIFIED",
        "project_execution_allowed": False,
        "agent_execution_allowed": False,
        "requires_operator_approval": True,
        "repository_total": len(repos),
        "repository_unknown": sum(item["access"] != "OK" for item in repos),
        "websites_total": len(websites),
        "websites_not_pass": sum(site["state"] != "PASS" for site in websites),
        "proposals_total": len(tasks),
        "proposals_p0": sum(task["priority"] == "P0" for task in tasks),
    }


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", required=True, help="Downloaded private snapshot.json OUTSIDE this repo")
    args = p.parse_args(argv)
    target = Path(args.input).expanduser().resolve(strict=True)
    root = Path(__file__).resolve().parents[1]
    try:
        target.relative_to(root)
    except ValueError:
        pass
    else:
        raise ValueError("Private artifact must not be stored inside public repo")
    if target.stat().st_size > 512_000:
        raise ValueError("Private report exceeds configured limit")
    report = safe_summary(json.loads(target.read_text(encoding="utf-8")))
    print(json.dumps(report, sort_keys=True, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, json.JSONDecodeError):
        # No exception text: path/PII could be present in an untrusted input.
        print("FAILED_CLOSED: invalid or unsafe private federation report", file=sys.stderr)
        sys.exit(2)
