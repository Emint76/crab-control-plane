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

Controlled disposable apply skeleton:

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

The current placement plan contract distinguishes workspace-target and state-target semantics.
The current initial skeleton applies workspace-target writes only and rejects state-target writes.
`make controlled-disposable-apply-ci` also validates controlled apply evidence schemas through the existing test surface.

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
- controlled disposable apply beyond the initial skeleton
- live runtime apply
- OpenClaw workspace/state writes
- live runtime adapter

Future OpenClaw integration requirements are defined in `docs/OPENCLAW_INTEGRATION_BOUNDARY.md`.

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
- controlled disposable apply expansion beyond initial skeleton
