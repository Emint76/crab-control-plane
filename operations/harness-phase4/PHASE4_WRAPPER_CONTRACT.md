# PHASE4_WRAPPER_CONTRACT

## Purpose

Phase 4 is a thin operator wrapper over Phase 3.

Phase 4 is not:
- a canonical execution owner
- a second runner
- a deployment engine
- a runtime mutation layer

The purpose of Phase 4 is to package and coordinate operator-facing invocation while preserving Phase 3 as the only canonical execution owner.

## Scope

Phase 4 may coordinate operator-facing invocation only.

Phase 4 may:
- prepare wrapper metadata
- run wrapper preflight
- call Phase 3 with explicit arguments
- surface Phase 3 run location
- surface Phase 3 report status

Phase 4 must not:
- perform apply/staging itself
- write Phase 3 canonical outputs
- rewrite Phase 3 report
- own `exit_code` for the underlying execution
- mutate Phase 2 outputs
- mutate Phase 3 run directories
- write live OpenClaw runtime state

## Phase 4 role

Phase 4 = operator wrapper only.

Phase 3 = canonical execution owner.

Phase 4 must call Phase 3 rather than bypass it.

## Allowed responsibilities

- validate operator-supplied arguments before invocation
- verify Phase 3 entrypoint exists
- verify Phase 2 run dir and execution target path are provided
- choose or pass through a Phase 3 run id
- invoke `operations/harness-phase3/bin/run_phase3_bundle.sh`
- preserve Phase 3 exit status as wrapper result
- print or record the Phase 3 canonical run directory
- print or record links/paths to Phase 3 `report.json`, `report.md`, `exit_code`

## Forbidden responsibilities

- no independent apply
- no independent staging
- no independent `execution_result.json`
- no independent `report.json` or `report.md` for the same execution
- no independent `exit_code` claiming to be canonical execution result
- no mutation of `operations/harness-phase3/runs/<RUN_ID>/` except by invoking Phase 3
- no writes into Phase 2 run directories
- no writes into `control-plane/`, `knowledge/`, `docs/`, `observability/`
- no live OpenClaw runtime mutation
- no plugin/gateway/channel/model/auth/token/config changes

## Relationship to Phase 3

Phase 3 owns canonical execution evidence.

Phase 4 may only wrap Phase 3 invocation.

Phase 4 outputs are wrapper metadata only.

If Phase 4 and Phase 3 disagree, Phase 3 canonical report and `exit_code` win.

## Inputs

Minimum future Phase 4 inputs are:

```text
--phase2-run-dir operations/harness-phase2/runs/<PHASE2_RUN_ID>
--execution-target-json <repo-contained-target-json>
--phase3-run-id <RUN_ID>
--operator <OPERATOR_ID>
```

`--phase3-run-id` is passed to Phase 3. It must not be used to create a separate Phase 4 execution surface.

Operator identity is wrapper metadata, not execution ownership.

## Outputs

Allowed Phase 4 outputs are wrapper-only.

Preferred wrapper run surface:

```text
operations/harness-phase4/runs/<WRAPPER_RUN_ID>/
```

Allowed files:

```text
wrapper_meta.json
preflight.json
phase3_invocation.json
wrapper_summary.md
wrapper_exit_code
```

These files must only point to Phase 3 canonical outputs, not duplicate them.

Forbidden Phase 4 files:

```text
report.json
report.md
exit_code
execution_result.json
```

Those names must not be used unless they are explicitly named as wrapper-only, for example:

```text
wrapper_exit_code
wrapper_report.md
```

The preferred contract is to avoid names that compete with Phase 3.

## Write-surface rules

Allowed Phase 4 write surface:

```text
operations/harness-phase4/runs/<WRAPPER_RUN_ID>/
```

Forbidden:

```text
operations/harness-phase3/runs/<RUN_ID>/
operations/harness-phase2/runs/<RUN_ID>/
control-plane/
knowledge/
docs/
observability/
OpenClaw runtime state
secrets/config locations
```

Phase 4 may read Phase 3 outputs after invocation.

Phase 4 may not edit Phase 3 outputs.

## Invocation rules

Phase 4 must invoke Phase 3 through `operations/harness-phase3/bin/run_phase3_bundle.sh`.

Phase 4 must pass through Phase 3 exit status as the wrapper result.

Phase 4 must record the Phase 3 run directory and report paths.

Phase 4 must not mask Phase 3 failure as wrapper success.

## Fail-closed rules

| Condition | Required behavior |
|---|---|
| missing Phase 3 entrypoint | fail closed |
| missing Phase 2 run dir argument | fail closed |
| missing execution target argument | fail closed |
| invalid wrapper operator metadata | fail closed |
| Phase 3 exits non-zero | wrapper exits non-zero |
| Phase 3 canonical report missing after invocation | fail closed |
| attempt to write outside Phase 4 wrapper run surface | fail closed |

## Non-goals

- No Phase 3 behavior changes.
- No Phase 2 behavior changes.
- No live runtime writes.
- No deployment or migration.
- No plugin/gateway/channel/model/auth/token/config changes.

## Acceptance criteria

- Phase 4 wrapper invokes Phase 3 and does not bypass it.
- Phase 4 wrapper has its own wrapper metadata surface only.
- Phase 4 wrapper never creates competing canonical execution outputs.
- Phase 4 wrapper preserves Phase 3 exit status.
- Phase 4 wrapper records Phase 3 canonical run directory and report paths.
- Phase 4 wrapper fails closed on missing Phase 3 report or invalid inputs.
- Phase 4 has dedicated tests proving it does not write Phase 3 canonical outputs directly.
- Phase 4 has dedicated CI for the wrapper test.
