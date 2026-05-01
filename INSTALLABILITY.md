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
- live runtime apply
- live OpenClaw workspace/state writes
- live-runtime adapter

Future OpenClaw integration requirements are defined in `docs/OPENCLAW_INTEGRATION_BOUNDARY.md`.

Future live runtime mutation is gated by `docs/LIVE_RUNTIME_APPLY_CONTRACT.md` and is not part of the current runnable surfaces.
No live-runtime adapter/wrapper exists yet.
Any future live execution surface is governed by `docs/LIVE_RUNTIME_ADAPTER_WRAPPER_CONTRACT.md` and is not part of the current runnable surfaces.
No live target selector executable surface exists.
Any future live target selector is contract-governed only by `docs/LIVE_TARGET_SELECTOR_CONTRACT.md`.

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

## Safe cleanup

```bash
rm -rf operations/harness-phase2/runs/smoke-e2e-phase2 \
       operations/harness-phase3/runs/smoke-e2e-phase3 \
       operations/harness-phase4/runs/smoke-e2e-wrapper \
       operations/harness-phase4/runs/smoke-e2e-target \
       operations/harness-orchestration/runs/orchestration-wrapper-valid \
       operations/harness-openclaw-dryrun/runs/openclaw-dryrun-valid \
       operations/harness-openclaw-disposable-apply/runs/controlled-disposable-apply-valid
```

Disposable local workspace/state targets live outside Git and must only be cleaned under explicitly approved disposable roots.
This document does not provide a generic cleanup command for arbitrary absolute local targets.

## Next installability work

- tooling hardening: ruff/shellcheck/pytest
- artifact validation
- OpenClaw dry-run adapter expansion beyond skeleton
- controlled disposable apply expansion beyond the current bounded local-only contour
