# OpenClaw Live Wrapper-Intake Bundle

This harness creates a bounded repo-local wrapper-intake bundle from two already-green repo-local inputs:

- live execution-prep run evidence
- live secret retention run evidence

It validates those input run directories, checks that the execution-prep records bind to the same target and execution attempt, and emits a refs-and-metadata-only bundle under `operations/harness-openclaw-live-wrapper-intake/runs/<RUN_ID>/`.

This is wrapper-intake only.
It does not mutate live targets, load raw secrets, grant approval, execute rollback, create a live-runtime adapter/wrapper, authorize live runtime apply, or approve Crab invocation.

## Usage

```bash
bash operations/harness-openclaw-live-wrapper-intake/bin/run_live_wrapper_intake.sh \
  --execution-prep-run-dir operations/harness-openclaw-live-execution-prep/runs/<RUN_ID> \
  --retention-run-dir operations/harness-openclaw-live-retention/runs/<RUN_ID> \
  --run-id <RUN_ID>
```

## Evidence

Each successful run writes:

- `wrapper_intake_meta.json`
- `wrapper_intake_report.json`
- `execution_input_bundle.json`
- `input_refs.json`
- `checks/execution_prep_validation.json`
- `checks/retention_validation.json`
- `checks/non_secret_bundle_validation.json`
- `exit_code`

Failed runs still emit parent-level report and check evidence under their run directory, unless the run id itself is invalid.

## CI

```bash
make live-wrapper-intake-ci
```
