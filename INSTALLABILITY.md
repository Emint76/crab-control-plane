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
- secrets/config management
- live runtime adapter

Future OpenClaw integration requirements are defined in `docs/OPENCLAW_INTEGRATION_BOUNDARY.md`.

The OpenClaw dry-run adapter skeleton is implemented for repo-local dry-run evidence only. Its boundary is defined in `operations/harness-openclaw-dryrun/OPENCLAW_DRY_RUN_ADAPTER_CONTRACT.md`.

## Generated artifacts

Ignored generated surfaces:

- `operations/harness-phase2/runs/`
- `operations/harness-phase2/reports/`
- `operations/harness-phase3/runs/`
- `operations/harness-phase4/runs/`
- `operations/harness-orchestration/runs/`
- `operations/harness-openclaw-dryrun/runs/`

## Safe cleanup

```bash
rm -rf operations/harness-phase2/runs/smoke-e2e-phase2 \
       operations/harness-phase3/runs/smoke-e2e-phase3 \
       operations/harness-phase4/runs/smoke-e2e-wrapper \
       operations/harness-phase4/runs/smoke-e2e-target
```

## Next installability work

- tooling hardening: ruff/shellcheck/pytest
- artifact validation
- OpenClaw dry-run adapter validation
- local overlay contract
- disposable workspace contract
