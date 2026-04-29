# harness-openclaw-target-validation

## Purpose

`operations/harness-openclaw-target-validation/` contains validation-only utilities for future disposable OpenClaw target path checks.

It does not perform apply.
It does not mutate OpenClaw.
It does not read secrets.
It does not approve Crab invocation.

## Current entrypoint

```bash
bash operations/harness-openclaw-target-validation/bin/validate_disposable_target_path.sh \
  --target-type workspace \
  --target-path <ABSOLUTE_PATH> \
  --approved-root <ABSOLUTE_PATH>
```

## Marker requirement

A valid disposable target must contain:

```text
.crab-disposable-target.json
```

## Status

Validation only.
Not apply.
Not deploy.
Not migration.
Not live runtime.
