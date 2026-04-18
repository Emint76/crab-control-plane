# APPLY_MODEL

## Goal

Define the Phase 2 controlled apply surface for the harness "Краб".

## Rules

- Phase 2 validates first.
- Phase 2 emits machine-readable decisions.
- Phase 2 renders an apply plan.
- Phase 2 renders a runtime-ready output package.
- Phase 2 does not write to a live runtime instance.
- Phase 2 is a scaffold/static-v1 controlled apply surface, not a full decision engine.

## Required machine outputs

Phase 2 must emit:
- `validation_report.json`
- `admission_decision.json`
- `placement_decision.json`
- `apply_plan.json`

Each machine-readable Phase 2 artifact must include:
- `run_id`
- `generated_at`
- `engine_mode`
- `evaluation_mode`

## Render target

The runtime-ready output package is rendered only to:

`operations/harness-phase2/runs/<RUN_ID>/output/runtime-ready/`

This runtime-ready package is a special Phase 2 output, not a placement artifact.

## Live runtime policy

- live runtime mutation is forbidden in Phase 2
- render output is run-scoped only
- a later execution owner may consume the rendered package
- PR-1 does not implement full execution, migration, or deployment behavior
