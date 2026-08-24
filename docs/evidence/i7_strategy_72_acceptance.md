# I7 canonical 72-slide strategy acceptance

- Date: 2026-08-23
- Branch: `shadowops-hardening-1.0.1`
- Production `main`: unchanged
- Canonical YAML SHA-256: `6b0d2a1cd631078a9f6e511d88706dce494b7aadaae655eb51daf241b8e129b1`

## Verified contract

```text
STRATEGY_SLIDES=72
CORE=12
SELF_CONTROL=18
SOCIAL_STRATEGY=18
CAREER_IHK=16
TECHNICAL=6
REVIEW=2
SYSTEM_SLIDES=6
TOTAL_AVAILABLE_SCREENS=78
SCHEMA_VALIDATION=VALID_CANONICAL_72
```

The canonical user-supplied text is stored only in `config/strategy_slides.yaml`. The six existing system slides remain separate and are not strategy records. Missing strategy content leaves the i7 route available with those six slides; invalid records are skipped and reported without a LiveView exception or fabricated replacement.

The browser selector was tested with a seeded RNG for deterministic category weighting, cooldown enforcement, no consecutive duplicate, all explicit context multipliers and Europe/Berlin night weighting. Runtime cadence is five strategy slides followed by the next system slide. Existing manual navigation, pause/resume, ticker, 60-second refresh and burn-in movement are preserved.

## Local acceptance

```text
FORMAT=PASS
COMPILE_WARNINGS_AS_ERRORS=PASS
TESTS=PASS_60
DIFF_CHECK=PASS
HTTP_I7=200
HEALTH=200
READINESS=200
BROWSER_RENDER=PASS_ISOLATED_PORT_4015
PHYSICAL_I7=NOT_DEPLOYED_FROM_UNMERGED_HARDENING_BRANCH
PHYSICAL_EXISTING_SYSTEM_ROTATION=PASS_READ_ONLY_OBSERVATION
```

Headless Chrome rendered the canonical strategy layout at 1920×1080 without an error overlay or blank page. A read-only X11 check on the physical i7 captured different existing system slides 15 seconds apart, confirming that its Firefox kiosk process and ticker still rotate from `http://127.0.0.1:4013/display/i7`. Physical deployment of the new 72-slide pool is intentionally deferred: the production systemd service, port 4013, tunnel, kiosk and `main` worktree were not modified by this branch. Canonical strategy validation on the physical display must follow the normal review/merge/deploy boundary.
