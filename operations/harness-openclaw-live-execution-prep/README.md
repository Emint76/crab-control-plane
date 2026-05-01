# OpenClaw Live Execution-Prep Bundle

This harness creates a bounded repo-local execution-prep bundle from reviewed outside-Git records:

- live target selector
- operator approval record
- rollback handoff record

It first revalidates those records through the existing live pre-execution gate, then emits normalized repo-local execution-prep records under `operations/harness-openclaw-live-execution-prep/runs/<RUN_ID>/`.

This is execution-prep only.
It does not mutate live targets, grant approval, execute rollback, load secrets, create a live-runtime adapter/wrapper, authorize live runtime apply, or approve Crab invocation.

## Usage

```bash
bash operations/harness-openclaw-live-execution-prep/bin/run_live_execution_prep.sh \
  --selector-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --approval-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --rollback-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

## Evidence

Each successful run writes:

- `execution_prep_meta.json`
- `execution_prep_report.json`
- `selector_execution_record.json`
- `approval_execution_record.json`
- `rollback_execution_record.json`
- `execution_prep_bundle.json`
- `input_refs.json`
- `checks/preexecution_gate_validation.json`
- `checks/approval_record_validation.json`
- `checks/rollback_record_validation.json`
- `exit_code`

Failed runs still emit parent-level report and check evidence under their run directory, unless the run id itself is invalid.

## CI

```bash
make live-execution-prep-ci
```
