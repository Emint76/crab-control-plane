# Phase 3 unresolved items

## execution_target schema contract

Status: open.

Current state:
- `operations/harness-phase3/bin/validate_execution_target.py` performs hand-written semantic validation.
- This is acceptable for the current fail-closed hardening step.

Target state:
- Add explicit `execution_target.schema.json` or equivalent contract coverage.
- Validate frozen `input/execution_target.json` against that schema before semantic checks.
- Keep semantic checks for canonical target_ref, write-surface, and unsafe path rules.

Reason:
- Phase 3 is the canonical execution owner.
- Execution target validation should eventually be contract-backed, not only code-backed.
