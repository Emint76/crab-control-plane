# harness-phase3

## Purpose

`operations/harness-phase3/` is the repo-native Phase 3 execution surface. Its target role is canonical execution owner.

It consumes a completed Phase 2 handoff, freezes an externally supplied execution target contract, reverifies the upstream runtime-ready package, materializes one canonical Phase 3-owned staging target, performs a deterministic scaffold apply, and emits one canonical Phase 3 evidence surface.

The current implementation is not yet fully hardened as canonical execution owner. The contract defines the target semantics for the next hardening PRs.

## Contract

The Phase 3 target execution contract is defined in:

```text
operations/harness-phase3/PHASE3_EXECUTION_CONTRACT.md
```

## Scope

- repo-native execution surface targeting canonical execution ownership
- canonical repo-native staging target only
- external `execution_target.json` is frozen as provided
- Phase 2 `runtime-ready/` remains an upstream package only

## Non-goals

- no wrapper behavior
- no live deploy logic
- no migration logic
- no remote execution
- no broad approval system
- no multi-target model

## Canonical Run Layout

Each run writes to:

```text
operations/harness-phase3/runs/<RUN_ID>/
```

Required always-on outputs:

- `run_meta.json`
- `report.json`
- `report.md`
- `timestamps.json`
- `exit_code`

Step-specific artifacts are emitted only if the bundle reaches the corresponding step.

## Key Invariants

- Phase 2 `runtime-ready/` stays package-only and is never treated as an execution target.
- `phase3_staging` is the only allowed `target_kind` in this scaffold.
- For validated runs, the only canonical target is `operations/harness-phase3/runs/<RUN_ID>/staging/runtime-ready-applied`.
- `run_phase3_bundle.sh` is the only owner of `exit_code`.
- `emit_phase3_report.py` never writes `exit_code`.
- `execution_result.json` exists only if `emit_execution_result.py` was actually reached.
- Reporting stays tolerant of early failures and still emits the final report surface.

## Entrypoint

Run the Phase 3 bundle with:

```bash
bash operations/harness-phase3/bin/run_phase3_bundle.sh \
  --phase2-run-dir operations/harness-phase2/runs/<PHASE2_RUN_ID> \
  --execution-target-json /path/to/execution_target.json \
  --run-id <RUN_ID>
```

`--run-id` is optional. When omitted, the bundle generates a UTC timestamp-based id.

If `python` is not on `PATH`, point the bundle at a specific interpreter with `PHASE3_PYTHON_BIN=/path/to/python`.
