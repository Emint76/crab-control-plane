# harness-orchestration

## Purpose

`operations/harness-orchestration/` defines an agent-safe invocation surface for Crab.

It is not a new phase.
It is not Phase 5.
It is not a deploy layer.
It is not a runtime adapter.
It is not a live OpenClaw integration layer.

## Current approved entrypoint

```bash
bash operations/harness-orchestration/bin/run_repo_native_smoke.sh
```

This entrypoint runs the existing repo-native smoke path:

Phase 2 `repo-native-scaffold` -> Phase 3 canonical execution owner -> Phase 4 thin wrapper.

## Boundary

Crab may call the approved wrapper.

Crab must not call arbitrary shell commands.
Crab must not choose arbitrary Phase 2 profiles.
Crab must not bypass Phase 3.
Crab must not write to live OpenClaw runtime state.
Crab must not perform deploy, migration, runtime adapter behavior, or real KB write-back.

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
