# harness-openclaw-dryrun

## Purpose

`operations/harness-openclaw-dryrun/` contains the repo-native OpenClaw dry-run adapter surface.

It may inspect Phase 2/Phase 3 evidence and produce a proposed OpenClaw placement plan.

It must not write to OpenClaw runtime, OpenClaw workspace, OpenClaw state, real KB, memory, secrets, local overlay, or live configuration.

## Status

Dry-run only.

Not deploy.
Not migration.
Not disposable workspace apply.
Not live runtime apply.
Not approved for Crab invocation yet.

## Entrypoint

```bash
bash operations/harness-openclaw-dryrun/bin/run_openclaw_dry_run.sh \
  --phase3-run-dir operations/harness-phase3/runs/<RUN_ID> \
  --run-id <DRY_RUN_ID>
```

Optional:

```bash
--phase2-run-dir operations/harness-phase2/runs/<RUN_ID>
```

## Output surface

```text
operations/harness-openclaw-dryrun/runs/<RUN_ID>/
```

## Boundary

This adapter produces dry-run evidence only.

It does not perform OpenClaw writes.
