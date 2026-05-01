# FINAL_REPO_WIDE_AUDIT

## Current phase state

| Phase | Current role | Executable surface | CI |
|---|---|---|---|
| Phase 2 | upstream check/render/handoff preparation | `operations/harness-phase2/bin/run_phase2_check_layer.sh`, `operations/harness-phase2/bin/run_phase2_bundle.sh` | `phase2-validate` |
| Phase 3 | repo-native canonical execution owner | `operations/harness-phase3/bin/run_phase3_bundle.sh` | `phase3-validate` |
| Phase 4 | thin wrapper over Phase 3 | `operations/harness-phase4/bin/run_phase4_wrapper.sh` | `phase4-validate` |

## Current runnable, OpenClaw-facing, and approval-bound surfaces

| Surface | Current role | Executable? | Status / boundary |
|---|---|---|---|
| Phase 2 strict check layer | audit-only external check profile | yes | no render, no `runtime-ready/`, no handoff |
| Phase 2 repo-native scaffold | package and handoff preparation for Phase 3 intake | yes | repo-native scaffold only; not live runtime |
| Phase 3 execution surface | canonical repo-native execution owner | yes | repo-local evidence only; not live runtime |
| Phase 4 wrapper | thin wrapper over Phase 3 | yes | wrapper-only metadata; not canonical owner |
| Crab-safe orchestration wrapper | approved Crab entrypoint for repo-native smoke | yes | repo-native smoke only; no OpenClaw writes |
| OpenClaw dry-run adapter | local-only dry-run evidence and placement plan classification | yes | no live writes; not approved for Crab invocation |
| Disposable target path validation | disposable target path and marker validator | yes | validation-only |
| No-secret-leakage validation | scanner for repo-local OpenClaw-facing evidence | yes | validation-only |
| Controlled disposable apply | bounded local-only disposable apply contour | yes | workspace/state writes inside explicitly disposable local targets only; no live runtime; not approved for Crab invocation |
| Bounded local target selector wrapper | forwards a non-secret external selector into disposable apply | yes | disposable selector only; outside Git; not a live target selector |
| Full local disposable cycle proof | proof wrapper over the current local-only disposable contour | yes | proof-level evidence only; no live runtime apply, no live wrapper, no Crab approval |
| Live runtime apply contract | safety gates for possible future live mutation | no | contract-only; no implementation |
| Live-runtime adapter/wrapper contract | future live execution-owner contract | no | contract-only; no implementation and no Crab approval |
| Live target selector contract | future live target selector boundary | no | contract-only; no implementation, no approval, no execution ownership |
| Live-runtime pre-execution contract stack | target identity, approval, rollback, failure/abort, secret handling, evidence retention, and no-secret redaction | no | contract/model/policy only; no implementation and no executable surface |

## Confirmed boundaries

- Phase 2 does not perform live runtime execution.
- Phase 2 has two profiles, not two separate phases.
- `check-layer-strict` is audit-only and does not render `runtime-ready/`.
- `repo-native-scaffold` prepares package/handoff outputs for Phase 3 intake.
- `handoff_ready.json` means ready for Phase 3 intake only, not live-runtime-ready, deploy-ready, or launch-ready.
- Phase 3 owns canonical repo-native execution evidence under `operations/harness-phase3/runs/<RUN_ID>/`.
- Phase 4 does not own canonical execution outputs.
- Phase 4 writes wrapper-only metadata under `operations/harness-phase4/runs/<WRAPPER_RUN_ID>/`.
- The orchestration wrapper is not a new phase, not a deploy layer, and not a runtime adapter.
- OpenClaw integration is currently local-only and disposable-only for apply-like behavior; live runtime mutation, deploy, migration, live runtime adapter behavior, real source ingestion, and real KB write-back are not implemented.
- The OpenClaw dry-run adapter skeleton produces repo-local dry-run evidence only and is not approved for Crab invocation yet.
- The controlled disposable apply surface is a bounded local-only disposable apply contour and is not approved for Crab invocation yet.
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
- repo-native smoke-e2e CI workflow.
- Crab-safe harness invocation wrapper.
- Orchestration wrapper canonical run-dir containment proof.
- OpenClaw integration boundary document.
- OpenClaw dry-run adapter contract.
- OpenClaw dry-run adapter skeleton.
- OpenClaw dry-run placement plan schema validation.
- Local overlay contract.
- Disposable OpenClaw workspace contract.
- Controlled disposable apply contract.
- Disposable target path validation.
- No-secret-leakage validation.
- Controlled disposable apply bounded local-only contour.
- Controlled disposable apply evidence schema validation.
- Placement plan workspace/state target semantics.
- Controlled disposable apply state-target write support inside disposable targets.
- Dry-run adapter reserved-prefix workspace/state classification.
- Bounded local disposable target selector layer.
- Live runtime apply contract and safety gates.
- Live-runtime adapter/wrapper contract.
- Full local disposable cycle proof surface.
- Live target selector contract.
- Live-runtime pre-execution contract stack:
  - live target identity model.
  - operator approval model.
  - rollback model.
  - failure and abort model.
  - secret handling contract.
  - evidence retention policy.
  - no-secret redaction policy.
- Failure and abort model.

## Remaining known non-blocking debt

- Phase 4 wrapper implementation embeds Python inside a shell script; this may later be split into a small Python module for readability.
- Runtime/deploy/live OpenClaw integration remains intentionally out of scope.
- Installability/deploy packaging remains a separate future workstream.
- Future OpenClaw dry-run adapter expansion beyond skeleton.
- Future expansion of Phase 3 staging conventions if needed.
- Controlled disposable apply expansion beyond the current bounded local-only contour.
- Broad local overlay implementation remains future work.
- Secret handling implementation remains future work.
- Approval execution surface remains future work.
- Rollback execution surface remains future work.
- Evidence storage implementation remains future work.
- No-secret redaction implementation remains future work.
- Live-runtime adapter implementation remains future work.
- Live target selector implementation remains future work.
- Live runtime apply implementation remains future work.
- Crab approval remains future work.
- Rollout/real deployment remains future work.
