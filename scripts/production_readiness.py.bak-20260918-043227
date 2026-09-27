#!/usr/bin/env python3
"""Mandatory local production gates; evidence is generated, never inferred from old reports."""
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--candidate', action='store_true', help='validate reviewed worktree before commit; never declares production ready')
args = parser.parse_args()
os.umask(0o077)
base = ROOT / 'var/production-readiness'
base.mkdir(parents=True, exist_ok=True)
lock = (base / 'check.lock').open('w')
fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
out = base / stamp
out.mkdir()
report = {'schema': 1, 'timestamp': stamp, 'host': socket.gethostname(), 'generated': True,
          'mode': 'candidate' if args.candidate else 'release', 'gates': {}, 'risks': []}
unit = 'shadowops-readiness-' + stamp.lower() + '.service'
started = False
snapshot = out / 'source'
env = {k: v for k, v in os.environ.items() if not k.startswith(('SHADOWOPS_', 'RELEASE_', 'MIX_')) and k not in ('PORT', 'DATABASE_URL', 'ERL_AFLAGS', 'ELIXIR_ERL_OPTIONS')}
env.update(SHADOWOPS_START_PERSISTENCE='false', PYTHONDONTWRITEBYTECODE='1', ERL_FLAGS='+S 4:4')

def capture(argv, cwd=ROOT):
    return subprocess.check_output(argv, cwd=cwd, env=env, text=True, stderr=subprocess.DEVNULL).strip()

def gate(name, argv, cwd=None, extra=None, timeout=900):
    run_env = dict(env, **(extra or {}))
    with (out / (name + '.log')).open('w') as log:
        try:
            result = subprocess.run(argv, cwd=cwd or snapshot, env=run_env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=timeout)
            rc = result.returncode
        except subprocess.TimeoutExpired:
            rc = 124
    report['gates'][name] = {'result': 'PASS' if rc == 0 else 'FAIL', 'exit_code': rc, 'log': name + '.log'}
    print(name + '=' + report['gates'][name]['result'], flush=True)
    save()
    if rc:
        raise RuntimeError(name + ' failed; see ' + str(out / (name + '.log')))

def save():
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')

def check(name, condition, detail=None):
    report['gates'][name] = {'result': 'PASS' if condition else 'FAIL', 'detail': detail}
    save()
    print(name + '=' + report['gates'][name]['result'], flush=True)
    if not condition:
        raise RuntimeError(name + ' failed')

def manifest():
    names = capture(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z']).split('\0')
    result = {}
    for name in sorted(set(names)):
        if not name or name.startswith('docs/evidence/production-readiness/'):
            continue
        p = ROOT / name
        if p.is_file():
            result[name] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result

def http(path, token=True):
    headers = {'Authorization': 'Bearer ' + read_token} if token else {}
    try:
        with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:4015' + path, headers=headers), timeout=5) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, {}

def wait_ready():
    for _ in range(45):
        try:
            if http('/health')[0] == 200 and http('/ready')[0] == 200:
                return
        except (OSError, ValueError):
            pass
        time.sleep(1)
    raise RuntimeError('isolated release did not become ready')

try:
    report['commit'] = capture(['git', 'rev-parse', 'HEAD'])
    report['branch'] = capture(['git', 'branch', '--show-current'])
    report['worktree'] = capture(['git', 'status', '--short'])
    check('SOURCE_BRANCH', report['branch'] not in ('', 'main', 'master'))
    check('SOURCE_CLEAN_OR_REVIEWED_CANDIDATE', args.candidate or not report['worktree'])
    gate('SOURCE_DIFF', ['git', 'diff', '--check'], ROOT)
    files = manifest()
    report['source_sha256'] = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
    (out / 'source-manifest.json').write_text(json.dumps(files, indent=2) + '\n')
    secret_patterns = [rb'-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----\r?\n', rb'gh[pousr]_[A-Za-z0-9]{36,}', rb'github_pat_[A-Za-z0-9_]{50,}']
    findings = [name for name in files if any(re.search(p, (ROOT / name).read_bytes()) for p in secret_patterns)]
    check('SECRETS', not findings, findings)
    check('GENERATED_FILES', not any(re.search(r'(^|/)(__pycache__|node_modules|_build|deps)/|\.pyc$', n) for n in files))
    # Fresh checkout plus the exact reviewed candidate overlay. No build/cache directories copied.
    gate('CHECKOUT', ['git', 'clone', '--local', '--no-hardlinks', '--no-checkout', str(ROOT), str(snapshot)], ROOT)
    gate('CHECKOUT_HEAD', ['git', 'checkout', '--detach', report['commit']])
    for name in files:
        target = snapshot / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    report['toolchain'] = {cmd: capture(argv) for cmd, argv in {
        'elixir': ['elixir', '--version'],
        'python': ['python3', '--version'],
        'node': ['node', '--version'],
    }.items()}

    # Bun is developer tooling only (.opencode) and is not a ShadowOps
    # build/runtime dependency. Record it when available, but never fail
    # production readiness merely because it is absent from PATH.
    bun = shutil.which('bun')
    report['toolchain']['bun'] = (
        capture([bun, '--version']) if bun else 'OPTIONAL_NOT_IN_PATH'
    )
    gate('DEPENDENCIES', ['mix', 'deps.get'])
    check('LOCK_UNCHANGED', (snapshot / 'mix.lock').read_bytes() == (ROOT / 'mix.lock').read_bytes())
    gate('FORMAT', ['mix', 'format', '--check-formatted'])
    gate('COMPILE', ['mix', 'compile', '--warnings-as-errors'])
    gate('FULL_TESTS', ['mix', 'test', '--seed', '12345'], extra={'MIX_ENV': 'test'})
    gate('GOVERNANCE_TESTS', ['mix', 'test', 'apps/shadowops_core/test/approval_single_use_test.exs', 'apps/shadowops_core/test/audit_canonicalization_test.exs', '--seed', '12345'], extra={'MIX_ENV': 'test'})
    gate('REGISTRY', ['mix', 'shadowops.registry', 'validate'])
    gate('WORKFLOW_IDS', ['mix', 'shadowops.workflow_ids.validate'])
    changed = capture(['git', 'diff', '--name-only', '7e3f1355ba593588cf7f69953cba0d650ee7f5b8', '--', '*.ex', '*.exs']).splitlines()
    gate('CREDO', ['mix', 'credo', '--strict'] + changed)
    gate('DIALYZER', ['mix', 'dialyzer'], timeout=1800)
    gate('SOBELOW', ['mix', 'sobelow', '--private', '--strict', '--exit', 'high', '--threshold', 'high'], snapshot / 'apps/shadowops_web')
    gate('HEX_AUDIT', ['mix', 'hex.audit'])
    gate('MCP_TESTS', ['python3', '-m', 'unittest', 'discover', '-s', 'ops/mcp', '-p', 'test_*.py', '-v'])
    gate('CODER_CONTRACT', ['bash', 'scripts/test-shadowops-coder.sh'])
    gate('JAVASCRIPT_TESTS', ['node', '--test', 'apps/shadowops_web/test/i7_rotation_test.js'])
    gate('BUILD', ['mix', 'release', 'shadowops'], extra={'MIX_ENV': 'prod'})
    binary = snapshot / '_build/prod/rel/shadowops/bin/shadowops'
    state = out / 'state'
    state.mkdir()
    read_token = secrets.token_hex(32)
    runtime_env = dict(SHADOWOPS_SECRET_KEY_BASE=secrets.token_hex(64), SHADOWOPS_READ_TOKEN=read_token,
                       SHADOWOPS_WRITE_TOKEN=secrets.token_hex(32), SHADOWOPS_STATE_DIR=str(state),
                       SHADOWOPS_PROJECT_CATALOG=str(state / 'project_catalog.json'),
                       SHADOWOPS_START_PERSISTENCE='false', PORT='4015', RELEASE_NODE='shadowops_readiness_' + stamp.lower(),
                       ERL_AFLAGS='-kernel inet_dist_use_interface {127,0,0,1}', ERL_FLAGS='+S 4:4')
    runtime_env['PATH'] = env['PATH']
    env_file = out / 'runtime.env'
    env_file.write_text(''.join(k + '=' + json.dumps(v) + '\n' for k, v in runtime_env.items()))
    gate('CATALOG', ['mix', 'shadowops.projects.seed'], extra=dict(runtime_env, MIX_ENV='prod'))
    with socket.socket() as probe:
        check('PORT_FREE', probe.connect_ex(('127.0.0.1', 4015)) != 0)
    failed = capture(['systemctl', '--user', '--failed', '--no-legend', '--plain'])
    report['systemd_failed'] = failed
    check('SERVICES', not failed)
    gate('RUNTIME_START', ['systemd-run', '--user', '--unit=' + unit,
         '--property=Type=exec', '--property=Restart=on-failure', '--property=RestartSec=1',
         '--property=WorkingDirectory=' + str(snapshot), '--property=EnvironmentFile=' + str(env_file), str(binary), 'start'])
    started = True
    wait_ready()
    check('HEALTH', http('/health')[0] == 200, http('/health')[1])
    check('READY', http('/ready')[0] == 200, http('/ready')[1])
    check('READ_AUTH', http('/api/workflows', False)[0] == 401)
    gate('RUNTIME_SMOKE', ['bash', 'scripts/runtime_smoke.sh'], extra=dict(runtime_env, SHADOWOPS_BASE_URL='http://127.0.0.1:4015'))
    gate('REAL_DATA_E2E', [str(binary), 'rpc', 'Code.eval_file("scripts/real_data_e2e.exs")'], extra=runtime_env)
    e2e = json.loads((state / 'real-data-e2e.json').read_text())
    report['real_data_e2e'] = e2e
    gate('RUNTIME_STOP', ['systemctl', '--user', 'stop', unit])
    with socket.socket() as probe:
        check('RUNTIME_STOPPED', probe.connect_ex(('127.0.0.1', 4015)) != 0)
    gate('RUNTIME_RESTART', ['systemctl', '--user', 'start', unit])
    wait_ready()
    gate('PERSISTENCE_RESTART', [str(binary), 'rpc', 'alias ShadowOpsCore.{Audit, RunStore}; {:ok, %{valid: true}} = Audit.verify(); true = Enum.any?(RunStore.list(), &(&1.status == "SUCCESS")); IO.puts("DURABLE_STATE=PASS")'], extra=runtime_env)
    before = capture(['systemctl', '--user', 'show', unit, '-p', 'MainPID', '--value'])
    gate('CRASH_SIGNAL', ['systemctl', '--user', 'kill', '--kill-whom=main', '--signal=SIGKILL', unit])
    time.sleep(2)
    wait_ready()
    after = capture(['systemctl', '--user', 'show', unit, '-p', 'MainPID', '--value'])
    restarts = capture(['systemctl', '--user', 'show', unit, '-p', 'NRestarts', '--value'])
    check('CRASH_RECOVERY', before != after and int(restarts) >= 1, {'restarts': restarts})
    # Prove readiness goes red for a broken dependency while liveness stays up.
    gate('READY_NEGATIVE_SET', [str(binary), 'rpc', 'Application.put_env(:shadowops_core, :audit_path, System.tmp_dir!())'], extra=runtime_env)
    check('READY_FAIL_CLOSED', http('/ready')[0] == 503 and http('/health')[0] == 200)
    gate('CLEAN_RESTART', ['systemctl', '--user', 'restart', unit])
    wait_ready()
    gate('FINAL_E2E', [str(binary), 'rpc', 'Code.eval_file("scripts/real_data_e2e.exs")'], extra=runtime_env)
    gate('RUNTIME_LOGS', ['journalctl', '--user', '-u', unit, '--no-pager', '-n', '300'])
    runtime_log = (out / 'RUNTIME_LOGS.log').read_text()
    check('LOG_SECRETS', all(v not in runtime_log for k, v in runtime_env.items() if 'TOKEN' in k or 'SECRET' in k))
    check('SOURCE_UNCHANGED', manifest() == files)
    gate('RELEASE_ARTIFACT', ['tar', '-czf', str(out / 'shadowops.tar.gz'), '-C', str(snapshot / '_build/prod/rel'), 'shadowops'])
    report['artifact_sha256'] = hashlib.file_digest((out / 'shadowops.tar.gz').open('rb'), 'sha256').hexdigest()
    report['final_status'] = 'CANDIDATE_GATES_PASS' if args.candidate else 'PRODUCTION_READY'
except Exception as exc:
    report['final_status'] = 'PRODUCTION_BLOCKED'
    report['error'] = str(exc)
    print('ERROR=' + str(exc), file=sys.stderr, flush=True)
finally:
    if started:
        result = subprocess.run(['systemctl', '--user', 'stop', unit], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode:
            report['final_status'] = 'PRODUCTION_BLOCKED'
            report['cleanup_error'] = 'cannot stop own isolated runtime'
    report['finished_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
    save()
    print('EVIDENCE=' + str(out), flush=True)
    print('FINAL_STATUS=' + report['final_status'], flush=True)
sys.exit(0 if report['final_status'] in ('CANDIDATE_GATES_PASS', 'PRODUCTION_READY') else 1)
