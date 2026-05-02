# OpenClaw Live Wrapper Preflight Skeleton

This harness creates bounded repo-local wrapper preflight evidence from a green wrapper-intake run.

It validates the wrapper-intake bundle, records preflight boundary flags, and emits a preflight-only execution plan stub under `operations/harness-openclaw-live-wrapper/runs/<RUN_ID>/`.

This is wrapper preflight only.
It does not mutate live targets, load raw secrets, grant approval, execute rollback, become live runtime apply, create a live-runtime execution owner, or approve Crab invocation.

## Usage

```bash
bash operations/harness-openclaw-live-wrapper/bin/run_live_wrapper_preflight.sh \
  --wrapper-intake-run-dir operations/harness-openclaw-live-wrapper-intake/runs/<RUN_ID> \
  --run-id <RUN_ID>
```

## Evidence

Each successful run writes:

- `wrapper_meta.json`
- `wrapper_report.json`
- `wrapper_input_refs.json`
- `execution_plan_stub.json`
- `checks/wrapper_intake_validation.json`
- `checks/preflight_boundary_validation.json`
- `exit_code`

Failed runs still emit parent-level report and check evidence under their run directory, unless the run id itself is invalid.

## CI

```bash
make live-wrapper-preflight-ci
```
