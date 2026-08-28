#!/usr/bin/env python3
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

ALLOWED = {
    "REPRODUCIBLE_PRODUCT_BUG",
    "SECURITY_DEFECT",
    "RELEASE_BLOCKER",
}

FROZEN = (
    ".github/workflows/",
    "config/runtime.exs",
)

def changed():
    result = subprocess.run(
        ["git", "diff", "--name-only", "HEAD"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return [
        line.strip()
        for line in result.stdout.splitlines()
        if line.strip()
    ]

files = changed()

foundation = [
    f for f in files
    if any(
        f == x or f.startswith(x)
        for x in FROZEN
    )
]

exception = os.environ.get("FREEZE_EXCEPTION", "")

print("FREEZE_STATUS=FROZEN")
print("FOUNDATION_FILES_CHANGED=" + str(len(foundation)))

if foundation and exception not in ALLOWED:
    print("FOUNDATION_CHANGE=BLOCKED")
    print("FREEZE_GATE=FAIL")
    sys.exit(20)

if foundation:
    print("FREEZE_EXCEPTION=" + exception)
else:
    print("FOUNDATION_CHANGE=NO")

print("PRODUCT_WORK=ALLOWED")
print("FREEZE_GATE=PASS")
