# crab-control-plane

Versioned control plane for the “Краб” agent harness.

This repository is **not** the live runtime instance of Гоша and is **not** a dump of the existing OpenClaw installation.
It is the governing layer above the system: architecture docs, policies, contracts, schemas, templates, and storage discipline.

## Purpose

This repo defines how the system should be structured across six layers:

1. **runtime** — machine-readable configuration templates
2. **policy** — normative markdown documents
3. **contracts** — structured packet specs and schemas
4. **operations** — Notion workflow model
5. **knowledge** — Obsidian semantic plane and KB layout
6. **observability** — logs, evals, reports, future evolution baseline

## Source of truth by data class

| Data class | Source of truth |
|---|---|
| Runtime templates | `control-plane/runtime/` |
| Policy docs | `control-plane/policy/` |
| Contracts and schemas | `control-plane/contracts/` |
| Operational workflow model | `operations/notion/` |
| Semantic note conventions | `knowledge/obsidian/` |
| KB layout and admission discipline | `knowledge/kb/` + policy docs |
| Observability model | `observability/` |

## Current executable surfaces

| Surface | Entrypoint | Status |
|---|---|---|
| Phase 2 strict check layer | `operations/harness-phase2/bin/run_phase2_check_layer.sh` | external check layer; no render, no runtime-ready, no handoff |
| Phase 2 repo-native scaffold | `operations/harness-phase2/bin/run_phase2_bundle.sh` | validates, renders scaffold decisions, runtime-ready package, conformance, report, handoff readiness |
| Phase 3 execution surface | `operations/harness-phase3/bin/run_phase3_bundle.sh` | canonical execution owner surface; hardened with run-dir invariants, fail-closed behavior, execution target validation, canonical reporting, and CI |
| Phase 4 wrapper | `operations/harness-phase4/bin/run_phase4_wrapper.sh` | thin wrapper over Phase 3; does not own canonical execution outputs; contract: `operations/harness-phase4/PHASE4_WRAPPER_CONTRACT.md` |
| Crab-safe wrapper | `operations/harness-orchestration/bin/run_repo_native_smoke.sh` | approved wrapper for repo-native smoke only; no OpenClaw writes |
| OpenClaw dry-run adapter | `operations/harness-openclaw-dryrun/bin/run_openclaw_dry_run.sh` | local-only dry-run evidence; no live writes |
| Disposable target path validation | `operations/harness-openclaw-target-validation/bin/validate_disposable_target_path.sh` | validation only |
| No-secret-leakage validation | `operations/harness-openclaw-safety-validation/bin/validate_no_secret_leakage.sh` | validation only |
| Controlled disposable apply | `operations/harness-openclaw-disposable-apply/bin/run_controlled_disposable_apply.sh` | bounded local-only disposable apply contour with workspace/state support; no live writes |
| Local target selector wrapper | `operations/harness-openclaw-local-selector/bin/run_controlled_disposable_apply_from_selector.sh` | local-only wrapper over disposable apply; selector file must stay outside Git; no live writes |
| Full local disposable cycle proof | `operations/harness-openclaw-local-proof/bin/run_full_local_disposable_cycle.sh` | proof wrapper for the current bounded local-only disposable contour; no live apply, no live wrapper, no Crab approval |
| Live execution-prep bundle | `operations/harness-openclaw-live-execution-prep/bin/run_live_execution_prep.sh` | repo-local bundle for reviewed selector, approval, and rollback records; no live apply, no live wrapper, no approval grant, no rollback execution |
| Live wrapper-intake bundle | `operations/harness-openclaw-live-wrapper-intake/bin/run_live_wrapper_intake.sh` | repo-local intake bundle from green execution-prep and retention inputs; no live apply, no live wrapper, no secret loading |
| Live wrapper preflight skeleton | `operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_preflight.sh` | repo-local preflight evidence from green wrapper-intake input; no live apply, no live wrapper, no secret loading |

Phase 2 has two profiles, not two separate phases:
- `check-layer-strict` is the audit-only profile.
- `repo-native-scaffold` is the package/handoff profile for Phase 3 intake.

`handoff_ready.json` means ready for Phase 3 intake only, not live-runtime-ready, deploy-ready, or launch-ready.

Phase 2 is upstream check/render/handoff preparation. It does not perform live runtime execution.

Phase 3 is the repo-native canonical execution owner surface. It owns canonical run evidence, fail-closed execution behavior, canonical reports, final exit status, and dedicated CI within the repo-native harness boundary.

The detailed Phase 3 target contract is defined in `operations/harness-phase3/PHASE3_EXECUTION_CONTRACT.md`.

Phase 4 must not own canonical execution outputs. It remains a thin wrapper over Phase 3.

The detailed Phase 4 wrapper contract is defined in `operations/harness-phase4/PHASE4_WRAPPER_CONTRACT.md`.

## One-command repo-native smoke

Run:

```bash
make smoke-e2e
```

This proves the repo-native path:

```text
Phase 2 repo-native-scaffold -> Phase 3 canonical execution owner -> Phase 4 thin wrapper
```

It does not perform live OpenClaw runtime mutation, deploy, migration, or production install.

The same smoke path is covered in CI by the `smoke-e2e` workflow.

Direct fallback command for environments where `make` is unavailable:

```bash
bash operations/harness-e2e/tests/test_smoke_e2e.sh
```

For setup and current runnable status, see `INSTALLABILITY.md`.

## Crab-safe invocation

Crab should not call Phase 2, Phase 3, or Phase 4 runners directly.

The approved agent-safe entrypoint is:

```bash
bash operations/harness-orchestration/bin/run_repo_native_smoke.sh
```

This wrapper runs the existing repo-native smoke path and does not perform live OpenClaw runtime mutation, deploy, migration, runtime adapter behavior, real source ingestion, or real KB write-back.

## OpenClaw integration boundary

Future OpenClaw integration is governed by `docs/OPENCLAW_INTEGRATION_BOUNDARY.md`.

The OpenClaw dry-run adapter contract is defined in `operations/harness-openclaw-dryrun/OPENCLAW_DRY_RUN_ADAPTER_CONTRACT.md`.
The OpenClaw dry-run adapter skeleton is implemented as a local-only dry-run evidence surface.

The OpenClaw dry-run adapter skeleton is available at:

```bash
bash operations/harness-openclaw-dryrun/bin/run_openclaw_dry_run.sh \
  --phase3-run-dir operations/harness-phase3/runs/<RUN_ID> \
  --run-id <DRY_RUN_ID>
```

The dry-run proposed placement plan is validated against:

`operations/harness-openclaw-dryrun/schemas/proposed_openclaw_placement_plan.schema.json`

The placement plan distinguishes workspace-target and state-target semantics. The controlled disposable apply contour now supports both workspace-target and state-target writes inside explicitly disposable local targets.

The dry-run adapter now classifies reserved staging prefixes:

- `workspace/<path>` -> workspace-target write
- `state/<path>` -> state-target write

Unprefixed staged files remain workspace-target writes for backward compatibility.

Local-only secrets, identity, credentials, endpoint config, and instance-specific runtime config are governed by `docs/LOCAL_OVERLAY_CONTRACT.md`.

The local overlay must stay outside Git.

Disposable local OpenClaw workspace/state rules are governed by `docs/DISPOSABLE_OPENCLAW_WORKSPACE_CONTRACT.md`.

Disposable workspace/state remains local-only and explicitly disposable. The repository still does not implement live runtime apply, deploy, migration, or writes to real OpenClaw workspace/state.

Controlled disposable apply rules are governed by `docs/CONTROLLED_DISPOSABLE_APPLY_CONTRACT.md`.

Controlled disposable apply is available at:

```bash
bash operations/harness-openclaw-disposable-apply/bin/run_controlled_disposable_apply.sh \
  --dry-run-run-dir operations/harness-openclaw-dryrun/runs/<RUN_ID> \
  --workspace-target <ABSOLUTE_PATH> \
  --workspace-approved-root <ABSOLUTE_PATH> \
  --state-target <ABSOLUTE_PATH> \
  --state-approved-root <ABSOLUTE_PATH> \
  --approval-label <NONEMPTY_TEXT> \
  --run-id <RUN_ID>
```

This is a bounded local-only disposable apply contour with workspace/state target support.
It does not authorize live runtime apply or Crab invocation.
The controlled disposable apply surface validates its primary repo-local evidence against JSON Schemas.

A bounded local target selector wrapper is available for disposable apply.
It accepts only a non-secret selector file outside Git and forwards validated target paths into controlled disposable apply.
Its contract is defined in `docs/LOCAL_DISPOSABLE_TARGET_SELECTOR_CONTRACT.md`.

A dedicated full local disposable cycle proof surface is available at:

```bash
bash operations/harness-openclaw-local-proof/bin/run_full_local_disposable_cycle.sh --run-id <RUN_ID>
```

This proof surface proves the current bounded local disposable contour through the already-approved local-only surfaces.
It does not authorize live runtime apply, does not create a live-runtime wrapper, and does not approve Crab invocation.

A validation-only live pre-execution gate is available for reviewed selector, approval, and rollback records:

```bash
bash operations/harness-openclaw-live-precheck/bin/run_live_preexecution_gate.sh \
  --selector-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --approval-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --rollback-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

This gate validates outside-Git record location, schema shape, cross-binding, and obvious non-secret boundaries.
It is validation-only: no live runtime apply, no live wrapper, and no Crab approval.

A bounded live secret/material declaration and redacted retention surface is available for candidate evidence:

```bash
bash operations/harness-openclaw-live-retention/bin/run_secret_retention_surface.sh \
  --source-declaration-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --candidate-evidence-dir <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

This surface validates an outside-Git declaration, validates an outside-Git candidate evidence directory, and writes redacted retained copies under its own run directory.
It is not live runtime apply, not a live wrapper, not real secret loading, and not Crab approval.

A bounded live execution-prep bundle surface is available for reviewed selector, approval, and rollback records:

```bash
bash operations/harness-openclaw-live-execution-prep/bin/run_live_execution_prep.sh \
  --selector-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --approval-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --rollback-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

This surface depends on a green validation-only live pre-execution gate and emits repo-local normalized execution-prep records.
It does not grant approval, execute rollback, create a live wrapper, authorize live runtime apply, or approve Crab invocation.

A bounded live wrapper-intake bundle surface is available for green execution-prep and retention runs:

```bash
bash operations/harness-openclaw-live-wrapper-intake/bin/run_live_wrapper_intake.sh \
  --execution-prep-run-dir operations/harness-openclaw-live-execution-prep/runs/<RUN_ID> \
  --retention-run-dir operations/harness-openclaw-live-retention/runs/<RUN_ID> \
  --run-id <RUN_ID>
```

This surface emits a repo-local refs-and-metadata wrapper-intake bundle after validating both upstream run directories.
It depends on green execution-prep and retention inputs, is not the live wrapper, does not load secrets, and does not authorize live runtime apply.

A bounded live wrapper preflight skeleton is available for green wrapper-intake runs:

```bash
bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_preflight.sh \
  --wrapper-intake-run-dir operations/harness-openclaw-live-wrapper-intake/runs/<RUN_ID> \
  --run-id <RUN_ID>
```

This surface emits repo-local wrapper preflight evidence and a preflight-only execution plan stub.
It depends on a green wrapper-intake bundle, is not the live wrapper, does not load secrets, and does not authorize live runtime apply.

Disposable target path validation is available at:

```bash
bash operations/harness-openclaw-target-validation/bin/validate_disposable_target_path.sh \
  --target-type workspace \
  --target-path <ABSOLUTE_PATH> \
  --approved-root <ABSOLUTE_PATH>
```

This is validation only. It does not implement apply or OpenClaw writes.

No-secret-leakage validation is available at:

```bash
bash operations/harness-openclaw-safety-validation/bin/validate_no_secret_leakage.sh \
  --evidence-dir operations/harness-openclaw-dryrun/runs/<RUN_ID>
```

This is validation only. It does not implement apply or OpenClaw writes.

The current repository remains local-only and disposable-only for apply-like OpenClaw integration. It does not perform live OpenClaw mutation, deploy, migration, live runtime adapter behavior, real source ingestion, or real KB write-back.

It is not approved for Crab invocation yet.

The current repo supports dry-run evidence generation, safety validation, and a bounded local-only disposable apply contour only.
Live runtime apply remains unimplemented and separately governed by `docs/LIVE_RUNTIME_APPLY_CONTRACT.md`.
A future live-runtime adapter/wrapper is separately governed by `docs/LIVE_RUNTIME_ADAPTER_WRAPPER_CONTRACT.md`.
A future live target selector is separately governed by `docs/LIVE_TARGET_SELECTOR_CONTRACT.md`.
No selector-driven live mutation surface exists.
A validation-only pre-execution gate exists for reviewed selector, approval, and rollback records, but it is not live runtime apply and not a live-runtime wrapper.
A bounded secret/material declaration validation and redacted retention surface exists, but real secret loading, full live evidence storage, and wrapper-integrated redaction remain future work.
A bounded live execution-prep bundle exists for reviewed selector, approval, and rollback records, but it is not approval granting, not rollback execution, not live runtime apply, and not a live-runtime wrapper.
A bounded live wrapper-intake bundle exists for green execution-prep and retention inputs, but it is not the live wrapper, not secret loading, not live runtime apply, and not Crab approval.
A bounded live wrapper preflight skeleton exists for green wrapper-intake inputs, but it is preflight-only, not the live wrapper, not secret loading, not live runtime apply, and not Crab approval.
The remaining live-runtime pre-execution contract stack is documented by `docs/LIVE_TARGET_IDENTITY_MODEL.md`, `docs/OPERATOR_APPROVAL_MODEL.md`, `docs/ROLLBACK_MODEL.md`, `docs/FAILURE_AND_ABORT_MODEL.md`, `docs/SECRET_HANDLING_CONTRACT.md`, `docs/EVIDENCE_RETENTION_POLICY.md`, and `docs/NO_SECRET_REDACTION_POLICY.md`.
These documents are contract/model/policy only and add no live-runtime executable surface and no Crab approval.
The current repo still proves only local-only disposable contours.

## What belongs elsewhere

- Live runtime state does **not** belong here
- Secrets and tokens do **not** belong here
- Notion board contents do **not** belong here
- Full knowledge corpus does **not** belong here unless explicitly curated as examples

## Recommended next steps

1. Keep Phase 2, Phase 3, and Phase 4 CI green.
2. Continue to keep live runtime state, secrets, and instance-specific config out of this repo.
