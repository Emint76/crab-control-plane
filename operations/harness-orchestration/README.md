# harness-orchestration

## Purpose

`operations/harness-orchestration/` defines an agent-safe invocation surface for Crab.

It is not a new phase.
It is not Phase 5.
It is not a deploy layer.
It is not a runtime adapter.
It is not a live OpenClaw integration layer.

## Current approved entrypoints

```bash
bash operations/harness-orchestration/bin/run_repo_native_smoke.sh
```

This entrypoint runs the existing repo-native smoke path:

Phase 2 `repo-native-scaffold` -> Phase 3 canonical execution owner -> Phase 4 thin wrapper.

```bash
bash operations/harness-orchestration/bin/run_crab_approved_live_rollout.sh \
  --apply-run-dir operations/harness-openclaw-live-wrapper/runs/<RUN_ID> \
  --rollout-declaration-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

This is the only Crab-approved live surface.
It validates a green bounded live runtime apply run plus one reviewed outside-Git rollout declaration and delegates only to first real rollout.

## Boundary

Crab may call the approved wrappers.

Crab must not call arbitrary shell commands.
Crab must not choose arbitrary Phase 2 profiles.
Crab must not bypass Phase 3.
Crab must not invoke bounded live runtime apply directly.
Crab must not invoke execution-owner, secret-session, material-resolution, or upstream live-adjacent surfaces directly.
Crab must not perform deploy, migration, runtime adapter expansion, rollout orchestration, supervision, scheduling, retries, approval granting, rollback execution, or real KB write-back.

## Relationship to existing smoke

The wrapper delegates to the already-existing repo-native smoke command.

Preferred target environment:

```bash
make smoke-e2e
```

Fallback:

```bash
bash operations/harness-e2e/tests/test_smoke_e2e.sh
```

## What this proves

* Crab can invoke one bounded repo-native harness workflow.
* The repo-native Phase 2 -> Phase 3 -> Phase 4 path remains valid.
* The wrapper does not introduce live runtime mutation.

## What this does not prove

* production OpenClaw deployment
* live runtime integration
* runtime adapter behavior
* real source ingestion
* real KB write-back

## Crab-approved live rollout wrapper

`run_crab_approved_live_rollout.sh` consumes:

- a repo-local direct child under `operations/harness-openclaw-live-wrapper/runs/`
- an absolute reviewed rollout declaration outside Git
- a safe run id

It emits repo-local orchestration evidence under `operations/harness-orchestration/runs/<RUN_ID>/`.
Its required evidence includes `crab_live_rollout_meta.json`, `crab_live_rollout_report.json`, `invocation_record.json`, `delegate_rollout_ref.json`, and validation files under `checks/`.

The wrapper delegates only to:

```bash
bash operations/harness-openclaw-live-wrapper/bin/run_first_real_rollout.sh \
  --apply-run-dir <REPO_LOCAL_APPLY_RUN_DIR> \
  --rollout-declaration-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>-delegate
```

It does not approve direct bounded live runtime apply.
It does not approve execution-owner, secret-session, material-resolution, or any upstream live-adjacent surface.
It is not a rollout orchestration framework, scheduler, retry loop, supervisor, deploy/migration framework, approval-granting surface, or rollback executor.
