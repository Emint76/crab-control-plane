# OpenClaw Live Pre-Execution Gate

This harness is a validation-only live-adjacent pre-execution gate for three reviewed outside-Git records:

- live target selector
- operator approval record
- rollback handoff record

It validates location, schema, cross-binding consistency, and obvious non-secret boundary rules.
It emits repo-local gate evidence under `operations/harness-openclaw-live-precheck/runs/<RUN_ID>/`.

This surface is only a gate.
It does not implement live runtime apply, does not create a live-runtime adapter/wrapper, does not grant approval, does not execute rollback, does not read broader local overlay material, and does not approve Crab invocation.

## Usage

```bash
bash operations/harness-openclaw-live-precheck/bin/run_live_preexecution_gate.sh \
  --selector-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --approval-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --rollback-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

The three input files must be outside the repository.
They are reviewed records, not secret carriers.

## Evidence

Each run writes:

- `gate_meta.json`
- `gate_report.json`
- `checks/input_file_validation.json`
- `checks/schema_validation.json`
- `checks/cross_binding_validation.json`
- `checks/non_secret_input_validation.json`
- `exit_code`

## CI

```bash
make live-preexecution-ci
```
