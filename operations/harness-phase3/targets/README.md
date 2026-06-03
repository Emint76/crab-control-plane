# Phase 3 target inputs

## Purpose

`operations/harness-phase3/targets/` is a repo-contained transient input area for Phase 3 target input material prepared before a Phase 3 bundle run.

This directory is for local, generated target input files only. It is not a canonical evidence surface and it is not a runtime instance.

## Tracking policy

Tracked files in this directory are limited to:

- `.gitkeep`
- `README.md`

Generated target input directories and files under `operations/harness-phase3/targets/*` are ignored by git.

## Canonical evidence

Canonical Phase 3 evidence lives under:

```text
operations/harness-phase3/runs/<RUN_ID>/
```

Do not move run evidence, live data, secrets, environment values, or production runtime state into `operations/harness-phase3/targets/`.
