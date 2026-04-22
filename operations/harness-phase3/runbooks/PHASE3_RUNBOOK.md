# Phase 3 Runbook

## Required Inputs

- a completed Phase 2 run directory with a ready handoff
- an external raw `execution_target.json`
- optional explicit `--run-id`

The bundle expects the Phase 2 run to already contain:

- `validation_report.json`
- `admission_decision.json`
- `placement_decision.json`
- `apply_plan.json`
- `handoff_ready.json`
- `checks/smoke_validation.json`
- `checks/conformance_validation.json`
- `output/runtime-ready/`

## Basic Invocation

```bash
bash operations/harness-phase3/bin/run_phase3_bundle.sh \
  --phase2-run-dir operations/harness-phase2/runs/pr2d-pass \
  --execution-target-json /tmp/execution_target.json \
  --run-id phase3-example
```

If `python` is not available on `PATH`, export `PHASE3_PYTHON_BIN` before invocation.

## Expected Outputs

Always expected for every run:

- `run_meta.json`
- `report.json`
- `report.md`
- `timestamps.json`
- `exit_code`

If the run reaches later steps, it may also emit:

- frozen Phase 2 intake under `input/`
- validation artifacts under `checks/`
- `staging/runtime-ready-applied/`
- `logs/apply.log`
- `execution_result.json`

## Staged-Only Semantics

- Phase 3 materializes only the canonical run-scoped staging target.
- The scaffold apply operates against the staging surface only.
- No live runtime writes, remote targets, or deploy semantics are introduced here.

## Common Failure Points

- Phase 2 handoff is not ready or upstream validation artifacts are not in a passing state.
- External `execution_target.json` is invalid or points outside the canonical Phase 3 staging target.
- The upstream Phase 2 `runtime-ready/` package changed after freeze, causing reverify hash drift.
- The scaffold apply log is missing or unreadable, causing post-apply validation to fail.
