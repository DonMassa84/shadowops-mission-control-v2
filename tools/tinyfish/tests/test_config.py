#!/usr/bin/env python3
"""Tests for TinyFish ShadowOps integration."""

import json
import os
import sys
import subprocess
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent.parent.parent
TINYFISH_DIR = PROJECT_ROOT / "tools" / "tinyfish"

def test_config_exists():
    config_file = TINYFISH_DIR / "config" / "config.json"
    assert config_file.exists(), "config.json not found"
    with open(config_file) as f:
        config = json.load(f)
    assert config.get("schema_version") == 1
    assert "tinyfish" in config
    assert "runtime" in config
    assert "security" in config
    print("✓ config.json exists and valid")

def test_schemas_exist():
    schemas_dir = TINYFISH_DIR / "schemas"
    for schema_name in ["workflow.json", "event.json", "monitor.json"]:
        schema_file = schemas_dir / schema_name
        assert schema_file.exists(), f"{schema_name} not found"
        with open(schema_file) as f:
            schema = json.load(f)
        assert "$schema" in schema
    print("✓ All schema files exist and valid")

def test_workflow_definitions():
    workflows_dir = TINYFISH_DIR / "workflows"
    assert workflows_dir.exists(), "workflows directory not found"
    
    for wf_file in workflows_dir.glob("*.json"):
        with open(wf_file) as f:
            wf = json.load(f)
        assert "id" in wf
        assert "type" in wf
        assert wf["type"] in ["FETCH", "MONITOR", "WEB_AUTOMATION", "PERSISTENT_WORKFLOW"]
    print("✓ Workflow definitions valid")

def test_monitor_definitions():
    monitors_dir = TINYFISH_DIR / "monitors"
    assert monitors_dir.exists(), "monitors directory not found"
    
    for mon_file in monitors_dir.glob("*.json"):
        with open(mon_file) as f:
            mon = json.load(f)
        assert "id" in mon
        assert "type" in mon
        assert mon["type"] in ["FETCH", "SEARCH"]
        assert "schedule_cron" in mon
    print("✓ Monitor definitions valid")

def test_scripts_executable():
    scripts_dir = TINYFISH_DIR / "scripts"
    for script in scripts_dir.glob("*.sh"):
        assert os.access(script, os.X_OK), f"{script.name} not executable"
    print("✓ All scripts executable")

def test_tinyfish_cli():
    try:
        result = subprocess.run(["tinyfish", "--version"], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"tinyfish CLI failed: {result.stderr}"
        print(f"✓ tinyfish CLI available: {result.stdout.strip()}")
    except FileNotFoundError:
        print("⚠ tinyfish CLI not in PATH (may need npm install -g @tiny-fish/cli)")
    except subprocess.TimeoutExpired:
        print("⚠ tinyfish CLI timed out")

def test_runtime_dirs():
    runtime_dirs = [
        Path.home() / ".local" / "state" / "shadowops" / "tinyfish" / "logs",
        Path.home() / ".local" / "state" / "shadowops" / "tinyfish" / "profiles",
        Path.home() / ".local" / "state" / "shadowops" / "tinyfish" / "monitors",
        Path.home() / ".local" / "state" / "shadowops" / "tinyfish" / "workflows",
        Path.home() / ".cache" / "shadowops" / "tinyfish",
        Path.home() / ".config" / "shadowops" / "tinyfish",
    ]
    for d in runtime_dirs:
        assert d.exists(), f"Runtime directory missing: {d}"
    print("✓ All runtime directories exist")

def main():
    tests = [
        test_config_exists,
        test_schemas_exist,
        test_workflow_definitions,
        test_monitor_definitions,
        test_scripts_executable,
        test_tinyfish_cli,
        test_runtime_dirs,
    ]
    
    passed = 0
    failed = 0
    
    for test in tests:
        try:
            test()
            passed += 1
        except Exception as e:
            print(f"✗ {test.__name__} FAILED: {e}")
            failed += 1
    
    print(f"\nResults: {passed} passed, {failed} failed")
    return failed == 0

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
