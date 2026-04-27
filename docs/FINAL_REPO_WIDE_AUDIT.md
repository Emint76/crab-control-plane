# FINAL_REPO_WIDE_AUDIT

## Current phase state

| Phase | Current role | Executable surface | CI |
|---|---|---|---|
| Phase 2 | upstream check/render/handoff preparation | `operations/harness-phase2/bin/run_phase2_check_layer.sh`, `operations/harness-phase2/bin/run_phase2_bundle.sh` | `phase2-validate` |
| Phase 3 | repo-native canonical execution owner | `operations/harness-phase3/bin/run_phase3_bundle.sh` | `phase3-validate` |
| Phase 4 | thin wrapper over Phase 3 | `operations/harness-phase4/bin/run_phase4_wrapper.sh` | `phase4-validate` |

## Confirmed boundaries

- Phase 2 does not perform live runtime execution.
- Phase 2 has two profiles, not two separate phases.
- `check-layer-strict` is audit-only and does not render `runtime-ready/`.
- `repo-native-scaffold` prepares package/handoff outputs for Phase 3 intake.
- `handoff_ready.json` means ready for Phase 3 intake only, not live-runtime-ready, deploy-ready, or launch-ready.
- Phase 3 owns canonical repo-native execution evidence under `operations/harness-phase3/runs/<RUN_ID>/`.
- Phase 4 does not own canonical execution outputs.
- Phase 4 writes wrapper-only metadata under `operations/harness-phase4/runs/<WRAPPER_RUN_ID>/`.
- No OpenClaw runtime mutation is implemented.
- No deploy/migration implementation is present.
- No plugin/gateway/channel/model/auth/token/config changes are implemented.

## Closed hardening items

- Phase 2 profile split and external check-layer hardening.
- Phase 2 run-id and run-dir containment invariants.
- Phase 2 fixture smoke and standalone schema/policy/admission checks.
- Phase 2 sample observability emitter under approved Phase 2 reports surface.
- Phase 3 execution contract.
- Phase 3 canonical run-dir invariants.
- Phase 3 fail-closed/evidence behavior.
- Phase 3 canonical reporting.
- Phase 3 execution target schema contract.
- Phase 4 wrapper contract.
- Phase 4 wrapper implementation.
- repo-native smoke-e2e path for Phase 2 -> Phase 3 -> Phase 4.

## Remaining known non-blocking debt

- Phase 4 wrapper implementation embeds Python inside a shell script; this may later be split into a small Python module for readability.
- Runtime/deploy/live OpenClaw integration remains intentionally out of scope.
- Installability/deploy packaging remains a separate future workstream.
- live-runtime integration boundary and runtime adapter remain future work.
