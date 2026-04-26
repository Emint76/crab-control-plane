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

Relevant check artifacts include:

- `checks/run_dir_invariants.json`
- `checks/freeze_intake_validation.json`
- `checks/execution_target_validation.json`
- `checks/pre_apply_validation.json`
- `checks/runtime_ready_reverify.json`
- `checks/declared_scope_evidence.json`
- `checks/post_apply_validation.json`

## Key Invariants

- Phase 2 `runtime-ready/` stays package-only and is never treated as an execution target.
- `phase3_staging` is the only allowed `target_kind` in this scaffold.
- For validated runs, the only canonical target is `operations/harness-phase3/runs/<RUN_ID>/staging/runtime-ready-applied`.
- Phase 3 validates the frozen execution target before pre-apply validation, staging, apply, or execution result emission.
- Phase 3 validates frozen `input/execution_target.json` against `operations/harness-phase3/contracts/execution_target.schema.json` before semantic target validation.
- Invalid execution target semantics fail closed and do not reach staging/apply.
- `run_phase3_bundle.sh` is the only owner of `exit_code`.
- `emit_phase3_report.py` never writes `exit_code`.
- `execution_result.json` exists only if `emit_execution_result.py` was actually reached.
- Reporting stays tolerant of early failures and still emits the final report surface.

## Canonical reporting

`report.json` and `report.md` are canonical Phase 3 execution reports.

`report.json` includes:

- identity
- input_refs
- target
- step_summary
- details
- blockers
- canonical_outputs
- runtime_statement

Open Phase 3 hardening debts are tracked in:

```text
operations/harness-phase3/UNRESOLVED.md
```

## Run directory invariants

- Phase 3 writes canonical evidence only under `operations/harness-phase3/runs/<RUN_ID>/`.
- `RUN_ID` must match `^[A-Za-z0-9._-]+$`.
- Path traversal and absolute run dirs are rejected.
- `run_meta.json.run_id` must match the basename of the canonical run directory.
- Phase 3 run metadata must not contain host-specific absolute paths; Phase 2 input and execution target references must be repo-contained before they are recorded.
- `checks/run_dir_invariants.json` records the invariant verdict.

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
