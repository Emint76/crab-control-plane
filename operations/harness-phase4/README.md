# harness-phase4

## Purpose

`operations/harness-phase4/` contains the thin operator wrapper over Phase 3.

Phase 4 is not a canonical execution owner.

## Contract

The Phase 4 wrapper contract is defined in:

```text
operations/harness-phase4/PHASE4_WRAPPER_CONTRACT.md
```

## Relationship to Phase 3

Phase 3 owns canonical execution evidence.

Phase 4 packages operator invocation and calls Phase 3, but must not create competing `report.json`, `report.md`, `exit_code`, or `execution_result.json`.

## Entrypoint

Run the Phase 4 wrapper with:

```bash
bash operations/harness-phase4/bin/run_phase4_wrapper.sh \
  --phase2-run-dir operations/harness-phase2/runs/<PHASE2_RUN_ID> \
  --execution-target-json <repo-contained-target-json> \
  --phase3-run-id <PHASE3_RUN_ID> \
  --operator <OPERATOR_ID> \
  [--wrapper-run-id <WRAPPER_RUN_ID>]
```

## Wrapper outputs

Phase 4 writes wrapper metadata only under:

```text
operations/harness-phase4/runs/<WRAPPER_RUN_ID>/
```

Allowed wrapper files are:

```text
wrapper_meta.json
preflight.json
phase3_invocation.json
wrapper_summary.md
wrapper_exit_code
```

Phase 3 remains the canonical execution owner.

## Current status

Phase 4 implementation and CI are present. The implementation remains wrapper-only.
