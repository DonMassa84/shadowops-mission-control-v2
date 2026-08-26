# Security Contract

Required invariants:

- `PRIVACY_GATE=PASS`
- `WRITE_BYPASS=BLOCKED`
- no secret values or private raw records in Git
- missing evidence remains non-positive (`UNKNOWN`, `NOT_CONFIGURED`, `SOURCE_MISSING`, `DEGRADED`, or equivalent)
- mutations use governed command paths only
- production endpoint remains loopback-only
- production boot requires `SHADOWOPS_SECRET_KEY_BASE` (minimum 64 bytes)
- production read APIs require `SHADOWOPS_READ_TOKEN` (minimum 32 bytes)
- write routes remain disabled when `SHADOWOPS_WRITE_TOKEN` is absent
- when configured, `SHADOWOPS_WRITE_TOKEN` must be at least 32 bytes and write requests must identify `x-shadowops-actor`
- production persistence requires an explicit database password; default development credentials are never accepted as the production password
- connector positive states require genuine, reachable, non-synthetic evidence

Remote access must terminate through a separately authenticated tunnel or hardened reverse proxy. The Phoenix listener itself is not an internet-facing boundary.

See `PRODUCTION.md` for the deploy and acceptance contract.
