# ShadowOps Mission Control Desktop

Thin Tauri 2 desktop shell for the canonical ShadowOps Phoenix control plane.

## Architecture

- Canonical control plane: `http://127.0.0.1:4013`
- Desktop app does **not** execute shell/systemd commands.
- All workflow, node, service, approval and audit actions remain behind the Phoenix API, GovernanceGate, RiskPolicy, Approval and Audit boundaries.
- Missing backend/runtime capabilities remain unavailable; the desktop client must not synthesize READY/ONLINE state.

## Runtime

The desktop shell opens the local Mission Control URL. Override only for controlled local testing:

```bash
SHADOWOPS_MISSION_CONTROL_URL=http://127.0.0.1:4013 cargo run --manifest-path src-tauri/Cargo.toml
```

The URL is restricted to loopback HTTP (`127.0.0.1` or `localhost`) by the Rust launcher.

## Build

```bash
cd shadowops/clients/desktop/src-tauri
cargo check --locked
cargo build --release --locked
```

`Cargo.lock` is generated and committed by the client build pipeline before this client is promoted to a release artifact.
