# ShadowOps 4014 immutable preview evidence — 2026-08-27

## Scope

This evidence records the successful recovery of the ShadowOps preview runtime after the source worktree was kept under `/tmp` while systemd hardening used `PrivateTmp=true`.

## Proven application gates

Before the runtime repair, the exact candidate already passed:

```text
Result: 117 passed
PASS_COUNT=43
FAIL_COUNT=0
FINAL_STATUS=PRODUCTION_ACCEPTANCE_PASS
PASS production_release
```

The application test failures observed earlier were caused by inherited preview/runtime environment and were separately fixed with hermetic `env -i` test boundaries.

## First runtime failure

The initial preview unit attempted to execute the release directly from the `/tmp` worktree and failed with:

```text
status=203/EXEC
FAIL_REASON=PREVIEW_NOT_HEALTHY
```

The service combined:

```text
WorkingDirectory=/tmp/shadowops-webmcp-test
ExecStart=/tmp/shadowops-webmcp-test/_build/prod/rel/shadowops/bin/shadowops start
PrivateTmp=true
```

## First repair and second failure

Copying only the already-built release outside `/tmp` removed the `203/EXEC` failure and allowed the BEAM runtime to start, but `/health` returned HTTP 503.

The reason was a compile-time absolute registry path. `WorkflowEngine.Registry` obtains its configured registry path from application configuration, and `config/config.exs` resolves `workflow_registry_v2.yaml` with `Path.expand(..., __DIR__)`. A release built under `/tmp` therefore retained an absolute registry path into the original `/tmp` source tree even after the release directory itself was copied elsewhere.

## Final runtime model

The exact Git commit was checked out as an immutable detached worktree outside `/tmp` and the production release was rebuilt there:

```text
~/.local/lib/shadowops-preview/<GIT_HEAD>/source
```

The preview systemd override then used that immutable source/release:

```text
WorkingDirectory=~/.local/lib/shadowops-preview/<GIT_HEAD>/source
ExecStart=~/.local/lib/shadowops-preview/<GIT_HEAD>/source/_build/prod/rel/shadowops/bin/shadowops start
```

Systemd hardening remained enabled. The repair did not require disabling `PrivateTmp=true`.

## Runtime evidence

For candidate commit:

```text
aefa88eaa33042de7c1601cae9cef97ab7467455
```

the immutable preview produced:

```text
IMMUTABLE_RELEASE_BUILD=PASS
REGISTRY_FILE=PASS
WORKFLOW_IDS_FILE=PASS
SYSTEMD_IMMUTABLE_IDENTITY=PASS
4014_HEALTH=PASS
4014_READY=PASS
4014_ROOT=PASS
PRIVATE_PATH_LEAK=NO
4013_MUTATED=NO
FINAL_STATUS=4014_IMMUTABLE_PREVIEW_PASS
```

The first health request immediately after `systemctl start` returned connection failure while the service was still starting; the second attempt returned HTTP 200. This is normal startup race behavior and is handled by bounded retry logic.

## Durable lessons

1. A successful `mix release` does not prove that the target service manager can execute the artifact.
2. A copied release can still contain absolute compile-time paths into its original build tree.
3. For a hardened systemd preview, build the release from the same immutable source location that will remain visible to the service.
4. Keep `PrivateTmp=true`; do not weaken systemd hardening to accommodate a temporary source path.
5. Health must remain fail-closed: missing registry truth correctly produced HTTP 503 rather than a false green state.
6. Preview runtime identity must be tied to an exact Git HEAD.
7. Port 4013 remains outside preview repair and certification unless explicit promotion is authorized.

## Lifecycle invariant

```text
source candidate
  -> hermetic tests
  -> production acceptance
  -> immutable source outside /tmp
  -> production release built there
  -> 4014 preview health/readiness
  -> 4015 isolated certification
  -> explicit-only 4013 promotion
```
