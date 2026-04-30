# harness-openclaw-local-selector

## Purpose

`operations/harness-openclaw-local-selector/` contains a bounded local-only selector wrapper for controlled disposable apply.

It reads a non-secret selector file outside Git and passes validated target paths into the existing controlled disposable apply surface.

It does not implement live runtime apply.
It does not read provider/model/auth/token config.
It does not approve Crab invocation.

## Entrypoint

```bash
bash operations/harness-openclaw-local-selector/bin/run_controlled_disposable_apply_from_selector.sh \
  --selector-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --dry-run-run-dir operations/harness-openclaw-dryrun/runs/<RUN_ID> \
  --run-id <RUN_ID>
```

## Boundary

The selector file is local-only, disposable-only, non-secret, and outside Git.
This wrapper delegates to `operations/harness-openclaw-disposable-apply/bin/run_controlled_disposable_apply.sh` and must not bypass its validations.
