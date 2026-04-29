# harness-openclaw-disposable-apply

## Purpose

`operations/harness-openclaw-disposable-apply/` contains the first local-only controlled disposable apply surface.

It may consume schema-valid dry-run placement plans and apply them only to explicitly disposable local OpenClaw targets.

It must not touch live runtime targets.
It must not read local overlay in this initial skeleton.
It must not approve Crab invocation.

## Status

Initial skeleton only.

Local-only.
Disposable-only.
Not live runtime.
Not deploy.
Not migration.

## Entrypoint

```bash
bash operations/harness-openclaw-disposable-apply/bin/run_controlled_disposable_apply.sh \
  --dry-run-run-dir operations/harness-openclaw-dryrun/runs/<RUN_ID> \
  --workspace-target <ABSOLUTE_PATH> \
  --workspace-approved-root <ABSOLUTE_PATH> \
  --state-target <ABSOLUTE_PATH> \
  --state-approved-root <ABSOLUTE_PATH> \
  --approval-label <NONEMPTY_TEXT> \
  --run-id <RUN_ID>
```

## Output surface

```text
operations/harness-openclaw-disposable-apply/runs/<RUN_ID>/
```

## Boundary

This surface is local-only and disposable-only.

It does not authorize live runtime apply.
