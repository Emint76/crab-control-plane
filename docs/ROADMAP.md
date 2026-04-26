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

## Current next work

### Phase 3 — canonical execution owner
Status: next hardening target.

Goal:
- own canonical execution run directory
- freeze Phase 2 handoff input
- validate execution target
- own apply/staging boundary
- emit canonical execution evidence
- own final report and exit status
- add dedicated Phase 3 CI

### Phase 4 — thin wrapper over Phase 3
Status: future.

Goal:
- package operator invocation
- perform wrapper preflight
- invoke Phase 3
- never own canonical execution outputs
