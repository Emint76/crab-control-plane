# APPLY_MODEL

## Goal

Define the Phase 2 controlled apply surface for the harness "Краб".

## Scope clarification

This document describes the `repo-native-scaffold` Phase 2 profile.

It does not describe the `check-layer-strict` profile, which performs external checks only and does not render decision artifacts, runtime-ready package, report, or handoff readiness.

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

## Relationship to Phase 3

Phase 2 render output is upstream input only.

Phase 3 is the intended canonical execution owner. Phase 2 `runtime-ready/` is not itself an execution target and does not prove runtime execution.

## Live runtime policy

- live runtime mutation is forbidden in Phase 2
- render output is run-scoped only
- a later execution owner may consume the rendered package
- Phase 2 does not implement full execution, migration, or deployment behavior
