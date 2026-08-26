# Production deployment contract

ShadowOps Mission Control is a local control plane. A production deployment is considered valid only when the code gates, runtime security contract and local runtime probes all pass.

## 1. Build gates

Run from the umbrella root:

```bash
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test --seed 12345
mix shadowops.registry validate
mix hex.audit
SHADOWOPS_RUNTIME_REQUIRED=0 bash scripts/production_acceptance.sh
MIX_ENV=prod mix release shadowops --overwrite
```

The GitHub Actions workflow runs the same static quality contract on every hardening/main pull request.

## 2. Required production environment

Generate secrets outside the repository:

```bash
export SHADOWOPS_SECRET_KEY_BASE="$(openssl rand -base64 64)"
export SHADOWOPS_READ_TOKEN="$(openssl rand -hex 32)"
export SHADOWOPS_STATE_DIR="$HOME/.local/state/shadowops"
export PORT=4013
mkdir -p "$SHADOWOPS_STATE_DIR"
chmod 700 "$SHADOWOPS_STATE_DIR"
```

`SHADOWOPS_SECRET_KEY_BASE` must be at least 64 bytes and `SHADOWOPS_READ_TOKEN` at least 32 bytes. Production boot fails when either requirement is missing.

## 3. Write capability

Writes are disabled by default. To enable governed write endpoints, configure a separate token:

```bash
export SHADOWOPS_WRITE_TOKEN="$(openssl rand -hex 32)"
```

A write request must also carry `x-shadowops-actor`. The HTTP boundary does not bypass the governance/privacy/policy/approval/audit path.

Never reuse the read token as the write token.

## 4. Persistent PostgreSQL/Oban mode

Persistence is opt-in:

```bash
export SHADOWOPS_START_PERSISTENCE=true
export SHADOWOPS_DB_HOST=127.0.0.1
export SHADOWOPS_DB_USER=shadowops
export SHADOWOPS_DB_NAME=shadowops
export SHADOWOPS_DB_PASSWORD='<strong generated password>'
export SHADOWOPS_DB_POOL_SIZE=10
```

In production, enabling persistence without a database password of at least 16 bytes fails closed.

## 5. Network boundary

The production endpoint binds to `127.0.0.1` only. Do not modify this to `0.0.0.0` merely to obtain remote access. Use an authenticated SSH/WireGuard tunnel or a hardened reverse proxy instead.

Health endpoints are:

```text
/health
/ready
```

The application API lives under `/api` and read access uses `Authorization: Bearer <SHADOWOPS_READ_TOKEN>`.

## 6. Release boot

Build:

```bash
MIX_ENV=prod mix release shadowops --overwrite
```

Boot:

```bash
_build/prod/rel/shadowops/bin/shadowops start
```

Foreground validation:

```bash
_build/prod/rel/shadowops/bin/shadowops start_iex
```

## 7. Runtime acceptance

After the release is running:

```bash
SHADOWOPS_RUNTIME_REQUIRED=1 \
SHADOWOPS_BASE_URL=http://127.0.0.1:4013 \
SHADOWOPS_READ_TOKEN="$SHADOWOPS_READ_TOKEN" \
bash scripts/production_acceptance.sh
```

A production claim requires `FINAL_STATUS=PRODUCTION_ACCEPTANCE_PASS` with runtime required. A static CI pass alone proves build/release readiness, not the state of local external sources.

## 8. Reproducible local production handoff

The supported local handoff entrypoint is:

```bash
bash scripts/local_production_handoff.sh
```

It intentionally uses port `4014` by default so it does not disturb an existing ShadowOps service on `4013`.

The handoff gate is stricter than a normal development test run. It:

- fetches the configured remote branch and requires local `HEAD` to equal that remote commit;
- rejects tracked, staged, or untracked source/config/test files that could shadow the proven Git tree;
- requires the CI toolchain contract (`Elixir 1.17.3`, OTP major `27`);
- cleans generated test/prod build state before compiling, which prevents stale BEAM files from an older checkout affecting results;
- verifies the dependency lock, formatter, warnings-as-errors compilation, full umbrella test suite, workflow registry, workflow IDs, Hex audit and whitespace;
- runs the static production acceptance gate;
- builds a production release;
- refuses to use the handoff port when another listener already owns it;
- launches the release only on the isolated handoff port, runs the production runtime smoke, and shuts that temporary release down again;
- verifies that no source changes were created during the handoff.

A successful run ends with:

```text
FINAL_STATUS=LOCAL_PRODUCTION_HANDOFF_PASS
```

A failure is fail-closed and reports a machine-readable `FAIL_REASON`. The full log is stored below:

```text
~/.local/state/shadowops/handoff/
```

The gate never resets, cleans Git files, merges branches, pushes commits, restarts an existing systemd service, or kills a process that owns another port. Repository reconciliation must be completed before this gate is run.

Useful overrides:

```bash
SHADOWOPS_HANDOFF_PORT=4015 bash scripts/local_production_handoff.sh
SHADOWOPS_HANDOFF_BRANCH=hardening/production-ready-2026-08-25 bash scripts/local_production_handoff.sh
```

Do not use an override to bypass a failed source-parity check. Fix the local worktree or move local-only source files to a verified backup first.

## 9. Truthfulness rules

- Missing evidence must remain `UNKNOWN`, `NOT_CONFIGURED`, `SOURCE_MISSING`, `DEGRADED`, or the equivalent non-positive state.
- A connector may report `READY`, `ONLINE`, or `CONNECTED` only when real data is present, the source is reachable and `synthetic=false`.
- Optional i7 unavailability must not by itself fabricate a global critical state.
- No raw private source payload, token, password, private key, legal record or private message belongs in Git.
