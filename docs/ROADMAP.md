# ROADMAP

## Current completed surface

### Phase 1 — control-plane skeleton
Status: complete.

### Phase 2 — repo-native check/render/handoff preparation
Status: hardened.

Includes:
- strict external check-layer profile
- repo-native scaffold profile
- wrong-root preflight
- contract validation
- policy validation
- fixture smoke
- standalone schema / placement / admission tools
- strict evidence pack
- sample observability JSONL emitter
- CI coverage for Phase 2

### Phase 3 — repo-native canonical execution owner
Status: hardened.

Includes:
- canonical run-dir invariants
- input freeze and provenance
- execution target schema and semantic validation
- fail-closed evidence behavior
- canonical reporting
- dedicated Phase 3 CI

### Phase 4 — thin wrapper over Phase 3
Status: implemented as wrapper-only.

Includes:
- wrapper preflight
- Phase 3 invocation
- wrapper-only metadata surface
- Phase 3 exit status propagation
- dedicated Phase 4 CI

## Current next work

- Keep Phase 2, Phase 3, and Phase 4 CI green.
- Continue to keep live runtime state, secrets, and instance-specific config out of this repo.
- Treat deploy and live OpenClaw integration as separate explicitly contracted work.
