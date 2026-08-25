# ShadowOps Mission Control V2

Production-oriented Phoenix/LiveView operations console for the local ShadowOps control plane.

## Security model

ShadowOps is intentionally local-first:

- the Phoenix endpoint binds to `127.0.0.1`;
- production requires a strong `SHADOWOPS_SECRET_KEY_BASE`;
- production read APIs require `SHADOWOPS_READ_TOKEN`;
- writes stay disabled unless `SHADOWOPS_WRITE_TOKEN` is explicitly configured;
- write requests additionally require an `x-shadowops-actor` identity and pass the governed command path;
- runtime state, credentials and private source data must never be committed to this repository.

Remote access should be provided only through an authenticated tunnel or reverse proxy. Do not expose the Phoenix listener directly to an untrusted network.

## Local development

```bash
git clone https://github.com/DonMassa84/shadowops-mission-control-v2.git
cd shadowops-mission-control-v2
./scripts/run-local-v2.sh
```

Default URL: `http://127.0.0.1:4013/`

Useful routes:

- `/` — Mission Control overview
- `/projects` — project domains
- `/projects/ihk` — IHK project domain
- `/career` — career module
- `/workflows` — workflow inventory
- `/runs` — durable runs
- `/security` — security status
- `/audit` — audit view
- `/display/i7` — i7 display
- `/health` — health probe
- `/ready` — readiness probe

## Production build

```bash
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test --seed 12345
mix shadowops.registry validate
MIX_ENV=prod mix release shadowops --overwrite
```

Production boot requires at minimum:

```bash
export SHADOWOPS_SECRET_KEY_BASE="$(openssl rand -base64 64)"
export SHADOWOPS_READ_TOKEN="$(openssl rand -hex 32)"
export SHADOWOPS_STATE_DIR="$HOME/.local/state/shadowops"
export PORT=4013
```

`SHADOWOPS_WRITE_TOKEN` is optional. If it is absent, mutating API routes fail closed.

For persistence through PostgreSQL/Oban, also set `SHADOWOPS_START_PERSISTENCE=true` and provide production database credentials. See `docs/PRODUCTION.md`.

## Repository data policy

This repository must not contain:

- API tokens or passwords;
- SSH/private keys;
- Gmail/Google OAuth secrets;
- financial raw data;
- legal raw case data;
- private message content;
- local runtime state.

Runtime data remains local and is consumed through approved adapters/manifests.
