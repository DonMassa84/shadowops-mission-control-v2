# ShadowOps Verified App

Current WhatsApp workflow state on this branch:

- 16 concrete WhatsApp workflows are represented.
- 12 L0/L1 workflows have real local execution evidence and are start-enabled.
- `whatsapp-doctor` remains runtime-blocked until the local Admin API is healthy and Meta configuration is complete.
- `whatsapp-meta-status` remains runtime-blocked until a real `META_PHONE_NUMBER_ID` replaces the placeholder.
- 2 L2 workflows remain fail-closed behind approval and are not start-enabled.
- Execution uses an exact static argv allowlist. No config-driven arbitrary shell execution is permitted.
- Run and audit records are persisted by the Verified App.
- Port 4013 is not mutated by the Verified App or its product gate.

This is a release-candidate state, not a claim that all 16 workflows are production-executed. The two L2 workflows require explicit approval, and the two runtime-blocked workflows require their external prerequisites before acceptance can advance.
