# harness-openclaw-safety-validation

## Purpose

`operations/harness-openclaw-safety-validation/` contains validation-only utilities for future OpenClaw-facing safety checks.

The first validator is no-secret-leakage validation for repo-local dry-run evidence.

It does not perform apply.
It does not mutate OpenClaw.
It does not read local overlay.
It does not approve Crab invocation.

## Current entrypoint

```bash
bash operations/harness-openclaw-safety-validation/bin/validate_no_secret_leakage.sh \
  --evidence-dir operations/harness-openclaw-dryrun/runs/<RUN_ID>
```

## Current approved surface

```text
operations/harness-openclaw-dryrun/runs/<RUN_ID>/
```

## Status

Validation only.
Not apply.
Not deploy.
Not migration.
Not live runtime.
