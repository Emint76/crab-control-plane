# PHASE3_EXECUTION_CONTRACT

## Purpose

Phase 3 is the canonical execution owner for repo-native execution runs.

As canonical execution owner, Phase 3 must own:
- the canonical run directory
- frozen inputs
- input hashes
- checks
- logs
- the staging/apply boundary
- reports
- timestamps
- final exit status
- the execution result surface, when execution reaches that step

## Scope

Phase 3 is responsible for execution ownership inside the repo-native harness boundary.

This contract does not claim:
- live production deployment
- remote execution
- OpenClaw runtime mutation
- plugin changes
- gateway/channel changes
- model/auth/token/config changes

Those actions remain forbidden unless a later explicit contract allows them.

## Phase 3 role

The repo-native harness roles are:
- Phase 2 = upstream check/render/handoff preparation.
- Phase 3 = canonical execution owner.
- Phase 4 = thin wrapper over Phase 3.

Phase 3 must not be bypassed by Phase 4.

Phase 4 must not create competing canonical execution outputs.

## Inputs

Minimum Phase 3 inputs are:

```text
--phase2-run-dir operations/harness-phase2/runs/<PHASE2_RUN_ID>
--execution-target-json <PATH>
--run-id <RUN_ID>
```

Phase 2 `runtime-ready/` is upstream package input only.

`execution_target.json` is an external target contract. Phase 3 must freeze it before relying on it.

`run_id` must identify the canonical Phase 3 run directory.

## Canonical run directory

The only canonical Phase 3 run surface is:

```text
operations/harness-phase3/runs/<RUN_ID>/
```

All canonical execution evidence must live under this directory.

Required subdirectories are:

```text
input/
checks/
logs/
staging/
```

Optional or step-dependent directories may exist, but they must remain under the canonical run directory.

## Required canonical outputs

For successful or accepted Phase 3 runs, required canonical outputs are:

```text
run_meta.json
input/
input/input.sha256
checks/
logs/
report.json
report.md
timestamps.json
exit_code
```

Step-dependent outputs are:

```text
input/execution_target.json
input/runtime_ready_manifest.json
input/runtime_ready.sha256
checks/freeze_intake_validation.json
checks/execution_target_validation.json
checks/pre_apply_validation.json
checks/runtime_ready_reverify.json
staging/runtime-ready-applied/
logs/apply.log
checks/declared_scope_evidence.json
checks/post_apply_validation.json
execution_result.json
```

Step-dependent artifacts are required only if the corresponding step is reached or succeeds according to the future code contract.

### Early fail-closed output semantics

For early fail-closed runs where Phase 3 cannot freeze upstream input, some input-derived artifacts may be unavailable.

Even in early failure, the runner must still emit, whenever technically possible:
- `run_meta.json`
- `report.json`
- `report.md`
- `timestamps.json`
- `exit_code`

Input-derived artifacts such as `input/input.sha256`, `input/runtime_ready_manifest.json`, and `input/runtime_ready.sha256` become mandatory only after the corresponding input-freeze step succeeds or is reached according to the future code contract.

`exit_code` must be owned by the Phase 3 bundle runner only.

Reports must not own or overwrite `exit_code`.

`report.json` and `report.md` are canonical Phase 3 execution reports.

`report.json` must include canonical identity, input refs, target, step summary, details, blockers, canonical outputs, and runtime statement.

## Input freeze requirements

Phase 3 must freeze:
- Phase 2 handoff/runtime-ready input
- execution target JSON
- runtime-ready manifest
- hashes proving what was consumed

After freeze, Phase 3 must not rely on mutable upstream files.

## Hash and provenance requirements

Phase 3 should preserve:

```text
input.sha256
runtime_ready.sha256
runtime_ready_manifest.json
phase2_run_ref
phase2_runtime_ready_ref
execution_target_ref or frozen execution_target.json
```

The goal is repeatable audit of what Phase 3 consumed and executed.

## Execution ownership rules

Only Phase 3 owns canonical execution evidence.

Phase 2 does not execute.

Phase 4 does not own canonical execution outputs.

Phase 3 report and exit code are canonical for a Phase 3 run.

Phase 3 staging/apply boundary must be explicit and auditable.

## Fail-closed rules

| Step class | Required behavior |
|---|---|
| Missing Phase 2 input | fail closed |
| Invalid execution target | fail closed |
| Runtime-ready hash mismatch | fail closed |
| Pre-apply validation failure | fail closed |
| Apply failure | fail closed |
| Post-apply validation failure | fail closed |
| Missing required reached-step artifact | fail closed |
| Attempted write outside allowed run directory | fail closed |

Failure must still produce `exit_code` and final report whenever technically possible.

Phase 3 validates the frozen execution target before pre-apply validation, staging, apply, or execution result emission.

Invalid execution target semantics must fail closed and must not reach staging/apply.

## Write-surface rules

Allowed canonical write surface:

```text
operations/harness-phase3/runs/<RUN_ID>/
```

Forbidden unless later explicitly contracted:

```text
operations/harness-phase2/
control-plane/
knowledge/
docs/
observability/
OpenClaw runtime state
secrets/config locations
```

Phase 3 may read Phase 2 run outputs.

Phase 3 may write only its own run directory.

Phase 3 must not mutate Phase 2 run directories.

Phase 3 run metadata must not contain host-specific absolute paths; Phase 2 input and execution target references must be repo-contained before they are recorded.

## Relationship to Phase 2

Phase 2 produces eligibility and package surfaces.

Phase 2 `handoff_ready.json` is a readiness verdict, not execution.

Phase 2 `runtime-ready/` is a package, not a canonical execution target.

Phase 3 consumes Phase 2 outputs as frozen upstream input.

## Relationship to Phase 4

Phase 4 is future thin wrapper only.

Phase 4 may package operator invocation, run wrapper preflight, and call Phase 3.

Phase 4 must not own canonical outputs.

Phase 4 must not write competing `report.json`, `report.md`, `exit_code`, or `execution_result.json` for the same execution.

## Non-goals

- No live OpenClaw runtime mutation.
- No deploy/migration implementation.
- No remote execution.
- No Phase 4 wrapper implementation.
- No model/auth/token/config changes.
- No plugin/gateway/channel changes.
- No replacement of Phase 2.

## Unresolved hardening debt

Open Phase 3 hardening debts are tracked in:

```text
operations/harness-phase3/UNRESOLVED.md
```

## Acceptance criteria for future hardening

- Phase 3 runner enforces canonical run-dir containment.
- Phase 3 runner rejects invalid `RUN_ID` values before creating run artifacts.
- Phase 3 runner proves run-dir containment through `checks/run_dir_invariants.json`.
- `run_meta.json` records canonical run-dir identity without host-specific absolute paths.
- Phase 3 runner freezes all upstream input.
- Phase 3 runner writes all canonical evidence under `runs/<RUN_ID>/`.
- Phase 3 runner owns `exit_code`.
- Phase 3 runner emits `report.json` and `report.md`.
- Phase 3 report includes canonical identity, input refs, target, step summary, blockers, canonical outputs, and runtime statement.
- Phase 3 runner fails closed on invalid input, hash mismatch, invalid target, write-surface violation, or missing reached-step artifacts.
- Phase 3 has dedicated CI.
- Phase 4, when added, invokes Phase 3 and does not create canonical outputs.
