# harness-phase4

## Purpose

`operations/harness-phase4/` is reserved for a future thin operator wrapper over Phase 3.

Phase 4 is not a canonical execution owner.

## Contract

The Phase 4 wrapper contract is defined in:

```text
operations/harness-phase4/PHASE4_WRAPPER_CONTRACT.md
```

## Relationship to Phase 3

Phase 3 owns canonical execution evidence.

Phase 4 may later package operator invocation and call Phase 3, but must not create competing `report.json`, `report.md`, `exit_code`, or `execution_result.json`.

## Current status

No Phase 4 implementation is present in this PR.
