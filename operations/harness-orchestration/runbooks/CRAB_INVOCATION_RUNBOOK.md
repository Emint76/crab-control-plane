# CRAB_INVOCATION_RUNBOOK

## Purpose

This runbook tells Crab how to invoke the repo-native harness safely.

## Approved command

```bash
bash operations/harness-orchestration/bin/run_repo_native_smoke.sh
```

Optional:

```bash
bash operations/harness-orchestration/bin/run_repo_native_smoke.sh --run-id <SAFE_RUN_ID>
```

## Rules for Crab

Crab must:

* call only the approved wrapper;
* not call Phase 2, Phase 3, or Phase 4 runners directly;
* not choose Phase 2 profiles directly;
* not execute arbitrary shell commands;
* not edit runtime state;
* not deploy;
* not migrate;
* not run runtime adapters;
* not write real KB;
* read `orchestration_summary.md` and `underlying_exit_code` after invocation.

## Expected success evidence

* `operations/harness-orchestration/runs/<RUN_ID>/orchestration_meta.json`
* `operations/harness-orchestration/runs/<RUN_ID>/orchestration_summary.md`
* `operations/harness-orchestration/runs/<RUN_ID>/underlying_exit_code`

## Failure handling

If `underlying_exit_code` is non-zero, Crab must report failure and must not attempt repair by running arbitrary shell commands.

Repair must go through a separate PR/maintainer workflow.
