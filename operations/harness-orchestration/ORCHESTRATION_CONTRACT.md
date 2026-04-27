# ORCHESTRATION_CONTRACT

## Purpose

This contract defines the only approved agent-callable harness invocation surface for Crab at the current repo-native stage.

## Scope

The wrapper may run the existing repo-native smoke path only.
It may not select arbitrary phases, profiles, targets, or commands.

## Approved entrypoint

```bash
bash operations/harness-orchestration/bin/run_repo_native_smoke.sh
```

## Allowed behavior

- verify repository-relative paths exist
- verify canonical run-dir containment before writing wrapper evidence
- run the existing repo-native smoke path
- prefer `make smoke-e2e` when `make` is available
- fall back to `bash operations/harness-e2e/tests/test_smoke_e2e.sh` when `make` is unavailable
- write wrapper-only evidence under `operations/harness-orchestration/runs/<RUN_ID>/`
- emit `run_dir_invariants.json` for successful wrapper runs
- preserve the underlying smoke exit status
- print a concise success/failure summary

## Forbidden behavior

- no arbitrary shell command execution
- no arbitrary phase selection
- no arbitrary Phase 2 profile selection
- no bypassing Phase 3
- no direct mutation of Phase 2, Phase 3, or Phase 4 run directories except through the approved smoke path
- no live OpenClaw runtime writes
- no deploy
- no migration
- no runtime adapter behavior
- no real external source ingestion
- no real KB write-back
- no secrets, token, auth, model, gateway, plugin, channel, or config changes

## Inputs

The first implementation accepts no required positional arguments.

It may accept this optional input:

```text
--run-id <SAFE_RUN_ID>
```

Safe run ids must match:

```regex
^[A-Za-z0-9._-]+$
```

The wrapper rejects:

- empty
- absolute paths
- `../` traversal
- path separators
- leading/trailing whitespace
- `.`
- `..`

## Outputs

Allowed wrapper outputs:

```text
operations/harness-orchestration/runs/<RUN_ID>/orchestration_meta.json
operations/harness-orchestration/runs/<RUN_ID>/orchestration_summary.md
operations/harness-orchestration/runs/<RUN_ID>/run_dir_invariants.json
operations/harness-orchestration/runs/<RUN_ID>/underlying_command.txt
operations/harness-orchestration/runs/<RUN_ID>/underlying_exit_code
```

The wrapper does not create files named:

```text
report.json
report.md
exit_code
execution_result.json
```

Those names could be confused with Phase 3 canonical outputs.

## Write surface

Allowed write surface:

```text
operations/harness-orchestration/runs/<RUN_ID>/
```

Generated run artifacts are ignored by git except `.gitkeep`.

## Invocation rules for Crab

Crab may call only the approved wrapper entrypoint.
Crab must not supply arbitrary commands, phase names, profiles, targets, runtime adapter settings, deploy instructions, migration instructions, or live runtime write requests.
After invocation, Crab may read `orchestration_summary.md` and `underlying_exit_code`.

## Relationship to Phase 2

The wrapper does not select Phase 2 profiles.
It reaches Phase 2 only through the existing repo-native smoke path, which uses the `repo-native-scaffold` package/handoff profile.

## Relationship to Phase 3

The wrapper does not bypass Phase 3.
Phase 3 remains the repo-native canonical execution owner.

## Relationship to Phase 4

The wrapper delegates to the existing smoke path, where Phase 4 remains a thin wrapper over Phase 3.
The orchestration wrapper does not own Phase 4 behavior.

## Fail-closed rules

| Condition | Required behavior |
| --- | --- |
| missing repo root | fail non-zero |
| missing e2e smoke script | fail non-zero |
| no `make` and no fallback script | fail non-zero |
| invalid run id | fail before writing outside approved surface |
| underlying smoke fails | wrapper exits non-zero |
| attempt to write outside orchestration run surface | fail non-zero |

## Non-goals

- no new phase
- no Phase 5
- no deploy layer
- no runtime adapter
- no live OpenClaw integration
- no arbitrary command runner for Crab
- no real external source ingestion
- no real KB write-back

## Closed hardening items

- Orchestration wrapper containment proof hardening is closed by explicit canonical run-dir containment verification and `run_dir_invariants.json`.

## Acceptance criteria

- one approved Crab-safe entrypoint exists
- the entrypoint runs only the existing repo-native smoke path
- wrapper evidence is written only under `operations/harness-orchestration/runs/<RUN_ID>/`
- forbidden canonical output names are not created by the wrapper
- invalid run ids fail closed
- underlying smoke failures are not masked
