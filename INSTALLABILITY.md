# INSTALLABILITY

## Current installability status

This repository is runnable as a repo-native harness/control-plane test surface.
It is not a production OpenClaw deployment package.

## What can be run now

- `make smoke-e2e`
- `bash operations/harness-e2e/tests/test_smoke_e2e.sh`
- `make phase2-ci`
- `make phase3-ci`
- `make phase4-ci`
- `make orchestration-ci`
- `make openclaw-dryrun-ci`
- `make disposable-target-validation-ci`
- `make no-secret-leakage-ci`
- `make controlled-disposable-apply-ci`
- `make local-target-selector-ci`
- `make openclaw-local-proof-ci`
- `make live-preexecution-ci`
- `make live-secret-retention-ci`
- `make live-execution-prep-ci`
- `make live-wrapper-intake-ci`
- `make live-wrapper-preflight-ci`
- `make live-material-resolution-ci`
- `make live-secret-session-ci`
- `make live-wrapper-execution-owner-ci`
- `make live-runtime-apply-ci`
- `make first-real-rollout-ci`
- `make openclaw-local-ci`

Agent-safe wrapper:

```bash
bash operations/harness-orchestration/bin/run_repo_native_smoke.sh
```

This is the approved wrapper for Crab to invoke the repo-native smoke path.

OpenClaw dry-run adapter skeleton:

```bash
bash operations/harness-openclaw-dryrun/bin/run_openclaw_dry_run.sh \
  --phase3-run-dir operations/harness-phase3/runs/<RUN_ID> \
  --run-id <DRY_RUN_ID>
```

This requires existing Phase 3 repo-native evidence and performs dry-run evidence generation only.
The generated `proposed_openclaw_placement_plan.json` is validated against the dry-run placement plan schema.
Reserved staging prefixes are classified as `workspace/<path>` -> workspace-target write and `state/<path>` -> state-target write.
Unprefixed staged files remain workspace-target writes for backward compatibility.

Disposable target path validator:

```bash
bash operations/harness-openclaw-target-validation/bin/validate_disposable_target_path.sh \
  --target-type workspace \
  --target-path <ABSOLUTE_PATH> \
  --approved-root <ABSOLUTE_PATH>
```

No-secret-leakage validator:

```bash
bash operations/harness-openclaw-safety-validation/bin/validate_no_secret_leakage.sh \
  --evidence-dir operations/harness-openclaw-dryrun/runs/<RUN_ID>
```

Bounded controlled disposable apply surface:

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

The placement plan supports workspace-target and state-target semantics.
The current controlled disposable apply contour can apply both, but only inside explicitly disposable local targets.
The current normal dry-run path remains workspace-only unless reserved staging prefixes appear.
Controlled disposable apply can consume classified dry-run plans inside explicitly disposable local targets only.
`make controlled-disposable-apply-ci` also validates controlled apply evidence schemas through the existing test surface.

Bounded local target selector wrapper:

```bash
bash operations/harness-openclaw-local-selector/bin/run_controlled_disposable_apply_from_selector.sh \
  --selector-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --dry-run-run-dir operations/harness-openclaw-dryrun/runs/<RUN_ID> \
  --run-id <RUN_ID>
```

This is not a full local overlay implementation.
The selector file must stay outside Git and may contain only disposable target paths plus approval label.
It must not contain secrets, provider/model/auth/token config, identity, channel IDs, or live-runtime targets.
The selector contract is defined in `docs/LOCAL_DISPOSABLE_TARGET_SELECTOR_CONTRACT.md`.

Full local disposable cycle proof:

```bash
bash operations/harness-openclaw-local-proof/bin/run_full_local_disposable_cycle.sh --run-id <RUN_ID>
```

`make openclaw-local-proof-ci` validates this proof surface.
It runs the current bounded local-only disposable contour in fixed order and emits proof-level evidence under `operations/harness-openclaw-local-proof/runs/<RUN_ID>/`.
This closes the "full local disposable cycle proof exists" prerequisite at the contract level.
It does not change runnable live-runtime status, authorize live runtime apply, create a live-runtime wrapper, or approve Crab invocation.

Validation-only live pre-execution gate:

```bash
bash operations/harness-openclaw-live-precheck/bin/run_live_preexecution_gate.sh \
  --selector-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --approval-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --rollback-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

`make live-preexecution-ci` validates this surface.
It checks reviewed outside-Git selector, approval, and rollback records for location, schema shape, cross-binding, and obvious non-secret boundaries.
This is a validation-only live-adjacent surface and does not create runnable live mutation, approval execution, rollback execution, a live-runtime wrapper, or Crab approval.

Bounded live secret/material declaration and redacted retention surface:

```bash
bash operations/harness-openclaw-live-retention/bin/run_secret_retention_surface.sh \
  --source-declaration-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --candidate-evidence-dir <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

`make live-secret-retention-ci` validates this surface.
It checks a reviewed outside-Git source declaration, validates an outside-Git candidate evidence directory, and retains only redacted copies under `operations/harness-openclaw-live-retention/runs/<RUN_ID>/`.
This is not runnable live mutation, not real secret loading, not broader local overlay reading, not full live evidence storage, not a live-runtime wrapper, and not Crab approval.

Bounded live execution-prep bundle:

```bash
bash operations/harness-openclaw-live-execution-prep/bin/run_live_execution_prep.sh \
  --selector-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --approval-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --rollback-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

`make live-execution-prep-ci` validates this surface.
It reruns the validation-only pre-execution gate and writes repo-local normalized selector, approval, and rollback execution-prep records under `operations/harness-openclaw-live-execution-prep/runs/<RUN_ID>/`.
This is execution-prep only and does not grant approval, execute rollback, load secrets, create a live-runtime wrapper, authorize live runtime apply, or approve Crab invocation.

Bounded live wrapper-intake bundle:

```bash
bash operations/harness-openclaw-live-wrapper-intake/bin/run_live_wrapper_intake.sh \
  --execution-prep-run-dir operations/harness-openclaw-live-execution-prep/runs/<RUN_ID> \
  --retention-run-dir operations/harness-openclaw-live-retention/runs/<RUN_ID> \
  --run-id <RUN_ID>
```

`make live-wrapper-intake-ci` validates this surface.
It checks green execution-prep and retention run directories and writes a repo-local refs-and-metadata intake bundle under `operations/harness-openclaw-live-wrapper-intake/runs/<RUN_ID>/`.
This is wrapper-intake only and does not load secrets, grant approval, execute rollback, create a live-runtime wrapper, authorize live runtime apply, or approve Crab invocation.

Bounded live wrapper preflight skeleton:

```bash
bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_preflight.sh \
  --wrapper-intake-run-dir operations/harness-openclaw-live-wrapper-intake/runs/<RUN_ID> \
  --run-id <RUN_ID>
```

`make live-wrapper-preflight-ci` validates this surface.
It checks a green wrapper-intake run directory and writes repo-local preflight evidence plus a stub execution plan under `operations/harness-openclaw-live-wrapper/runs/<RUN_ID>/`.
This is preflight only and does not load secrets, grant approval, execute rollback, create a live-runtime execution owner, authorize live runtime apply, or approve Crab invocation.

Bounded live material-resolution bundle:

```bash
bash operations/harness-openclaw-live-material-resolution/bin/run_live_material_resolution.sh \
  --wrapper-preflight-run-dir operations/harness-openclaw-live-wrapper/runs/<RUN_ID> \
  --source-declaration-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

`make live-material-resolution-ci` validates this surface.
It checks a green wrapper preflight run directory, validates a reviewed outside-Git source declaration, validates declared material paths, and writes repo-local refs-only material-resolution evidence under `operations/harness-openclaw-live-material-resolution/runs/<RUN_ID>/`.
This is material-resolution only and does not load raw secrets, grant approval, execute rollback, create a live-runtime execution owner, authorize live runtime apply, or approve Crab invocation.

Bounded live secret-session bundle:

```bash
bash operations/harness-openclaw-live-secret-session/bin/run_live_secret_session.sh \
  --material-resolution-run-dir operations/harness-openclaw-live-material-resolution/runs/<RUN_ID> \
  --run-id <RUN_ID>
```

`make live-secret-session-ci` validates this surface.
It checks a green material-resolution run directory, loads only already-resolved outside-Git material sources in-process, and writes repo-local metadata plus redacted observations under `operations/harness-openclaw-live-secret-session/runs/<RUN_ID>/`.
This is secret-session only and does not persist raw secret material, grant approval, execute rollback, create a live-runtime execution owner, authorize live runtime apply, or approve Crab invocation.

Bounded live wrapper execution-owner skeleton:

```bash
bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_execution_owner.sh \
  --secret-session-run-dir operations/harness-openclaw-live-secret-session/runs/<RUN_ID> \
  --run-id <RUN_ID>
```

`make live-wrapper-execution-owner-ci` validates this surface.
It checks a green secret-session run directory and writes wrapper-owned canonical execution evidence plus an apply-request stub under `operations/harness-openclaw-live-wrapper/runs/<RUN_ID>/`.
This is execution-owner only and does not perform live runtime apply, mutate targets, grant approval, execute rollback, load new raw secrets, read broader local overlay material, or approve Crab invocation.

Bounded live runtime apply:

```bash
bash operations/harness-openclaw-live-wrapper/bin/run_live_runtime_apply.sh \
  --execution-owner-run-dir operations/harness-openclaw-live-wrapper/runs/<RUN_ID> \
  --run-id <RUN_ID>
```

`make live-runtime-apply-ci` validates this surface.
It consumes a green wrapper execution-owner run, re-loads already-approved outside-Git material sources, and applies them only inside the selected outside-Git `workspace`, `state`, and `runtime` live roots.
This is bounded live runtime apply, not rollout orchestration, not deploy/migration, not Crab approval, not approval granting, and not rollback execution.

First real rollout from green bounded live runtime apply:

```bash
bash operations/harness-openclaw-live-wrapper/bin/run_first_real_rollout.sh \
  --apply-run-dir operations/harness-openclaw-live-wrapper/runs/<RUN_ID> \
  --rollout-declaration-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

`make first-real-rollout-ci` validates this surface.
It consumes a green bounded live runtime apply run, validates one reviewed outside-Git rollout declaration, launches one reviewed runtime command, runs one reviewed healthcheck command, and emits canonical rollout evidence.
This is first real rollout, not an orchestration framework, not a supervisor, not deploy/migration, not Crab approval, not approval granting, and not rollback execution.

## One-command smoke

```bash
make smoke-e2e
```

This runs Phase 2 `repo-native-scaffold` into Phase 3 canonical execution through the Phase 4 thin wrapper on a controlled repo-local fixture.

The `make smoke-e2e` path is also covered by the GitHub Actions workflow `smoke-e2e`.

Direct fallback command for environments where `make` is unavailable:

```bash
bash operations/harness-e2e/tests/test_smoke_e2e.sh
```

## Required local tools

- bash
- python 3.11+
- pip
- make

Install Phase 2 Python requirements before running the harness:

```bash
pip install -r operations/harness-phase2/requirements.txt
```

## What is scaffold-only

Phase 2 repo-native-scaffold renders decisions, `apply_plan.json`, runtime-ready package, conformance, reports, and `handoff_ready.json`.
It does not perform live apply.

## What is repo-native execution only

Phase 3 owns canonical repo-native execution evidence under `operations/harness-phase3/runs/<RUN_ID>/`.
It stages into repo-local generated run directories only.

## What is not implemented

- live OpenClaw runtime integration
- production deploy
- migration
- real external source ingestion
- real KB write-back
- local overlay implementation
- secrets/config management
- disposable workspace implementation
- controlled disposable apply expansion beyond the current bounded local-only contour
- live-runtime adapter expansion
- rollout orchestration
- production deploy
- migration

Future OpenClaw integration requirements are defined in `docs/OPENCLAW_INTEGRATION_BOUNDARY.md`.

Bounded live runtime mutation is gated by `docs/LIVE_RUNTIME_APPLY_CONTRACT.md` and exists only as the current bounded wrapper apply surface.
No rollout orchestration or full live-runtime adapter expansion exists yet.
Any future live execution expansion is governed by `docs/LIVE_RUNTIME_ADAPTER_WRAPPER_CONTRACT.md` and is not part of the current runnable surfaces.
No selector-driven live target mutation surface exists.
A validation-only live pre-execution gate exists for reviewed selector, approval, and rollback records.
Any future live target selector remains governed by `docs/LIVE_TARGET_SELECTOR_CONTRACT.md`.
Bounded source declaration validation and redacted retention now exist for candidate live-adjacent evidence.
Real secret loading, full live evidence storage, and wrapper-integrated redaction remain future work.
A bounded live execution-prep bundle now exists for reviewed selector, approval, and rollback records.
It is execution-prep only and does not create runnable live mutation.
A bounded live wrapper-intake bundle now exists for green execution-prep and retention inputs.
It is wrapper-intake only and does not create runnable live mutation or a live-runtime wrapper.
A bounded live wrapper preflight skeleton now exists for green wrapper-intake inputs.
It is preflight only and does not create runnable live mutation or a live-runtime execution owner.
A bounded live material-resolution bundle now exists for green wrapper preflight inputs and reviewed outside-Git source declarations.
It is material-resolution only and does not create runnable live mutation, raw secret loading, or a live-runtime execution owner.
A bounded live secret-session bundle now exists for green material-resolution inputs.
It is secret-session only and does not create runnable live mutation, raw secret output, or a live-runtime execution owner.
A bounded live runtime apply surface now exists for green wrapper execution-owner inputs.
It performs bounded mutation only inside selected outside-Git live roots and does not create rollout orchestration, deploy/migration, Crab approval, approval granting, or rollback execution.
A first real rollout surface now exists for green bounded live runtime apply inputs.
It launches one reviewed runtime command and one reviewed healthcheck only; it does not create an orchestration framework, supervisor, deploy/migration surface, Crab approval, approval granting, or rollback execution.
The live target identity model, operator approval model, rollback model, failure/abort model, secret handling contract, evidence retention policy, and no-secret redaction policy are contract/policy/model only.
They do not create Crab approval, rollout orchestration, or deploy/migration surfaces.

The OpenClaw dry-run adapter skeleton is implemented for repo-local dry-run evidence only. Its boundary is defined in `operations/harness-openclaw-dryrun/OPENCLAW_DRY_RUN_ADAPTER_CONTRACT.md`.

Local-only overlay expectations are defined in `docs/LOCAL_OVERLAY_CONTRACT.md`.

Disposable local OpenClaw workspace/state expectations are defined in `docs/DISPOSABLE_OPENCLAW_WORKSPACE_CONTRACT.md`.

Controlled disposable apply expectations are defined in `docs/CONTROLLED_DISPOSABLE_APPLY_CONTRACT.md`.

## Generated artifacts

Ignored generated surfaces:

- `operations/harness-phase2/runs/`
- `operations/harness-phase2/reports/`
- `operations/harness-phase3/runs/`
- `operations/harness-phase4/runs/`
- `operations/harness-orchestration/runs/`
- `operations/harness-openclaw-dryrun/runs/`
- `operations/harness-openclaw-disposable-apply/runs/`
- `operations/harness-openclaw-local-proof/runs/`
- `operations/harness-openclaw-live-precheck/runs/`
- `operations/harness-openclaw-live-retention/runs/`
- `operations/harness-openclaw-live-execution-prep/runs/`
- `operations/harness-openclaw-live-wrapper-intake/runs/`
- `operations/harness-openclaw-live-wrapper/runs/`
- `operations/harness-openclaw-live-material-resolution/runs/`
- `operations/harness-openclaw-live-secret-session/runs/`

## Safe cleanup

```bash
rm -rf operations/harness-phase2/runs/smoke-e2e-phase2 \
       operations/harness-phase3/runs/smoke-e2e-phase3 \
       operations/harness-phase4/runs/smoke-e2e-wrapper \
       operations/harness-phase4/runs/smoke-e2e-target \
       operations/harness-orchestration/runs/orchestration-wrapper-valid \
       operations/harness-openclaw-dryrun/runs/openclaw-dryrun-valid \
       operations/harness-openclaw-disposable-apply/runs/controlled-disposable-apply-valid \
       operations/harness-openclaw-local-proof/runs/full-local-disposable-cycle-proof-valid \
       operations/harness-openclaw-live-precheck/runs/live-preexecution-gate-valid \
       operations/harness-openclaw-live-retention/runs/live-secret-retention-valid \
       operations/harness-openclaw-live-execution-prep/runs/live-execution-prep-valid \
       operations/harness-openclaw-live-wrapper-intake/runs/live-wrapper-intake-valid \
       operations/harness-openclaw-live-wrapper/runs/live-wrapper-preflight-valid \
       operations/harness-openclaw-live-material-resolution/runs/live-material-resolution-valid \
       operations/harness-openclaw-live-secret-session/runs/live-secret-session-valid \
       operations/harness-openclaw-live-wrapper/runs/live-wrapper-execution-owner-valid \
       operations/harness-openclaw-live-wrapper/runs/rollout-valid
```

Disposable local workspace/state targets live outside Git and must only be cleaned under explicitly approved disposable roots.
This document does not provide a generic cleanup command for arbitrary absolute local targets.

## Next installability work

- tooling hardening: ruff/shellcheck/pytest
- artifact validation
- OpenClaw dry-run adapter expansion beyond skeleton
- controlled disposable apply expansion beyond the current bounded local-only contour
