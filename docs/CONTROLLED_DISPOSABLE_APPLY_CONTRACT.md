# CONTROLLED_DISPOSABLE_APPLY_CONTRACT

## Purpose

This document defines the boundary for future controlled disposable apply.
Controlled disposable apply is the first possible apply-like stage after dry-run evidence, placement plan schema validation, local overlay contract, and disposable workspace/state contract.

## Status

The initial controlled disposable apply skeleton is implemented.
It remains local-only and disposable-only.
It is not approved for Crab invocation.
No OpenClaw mutation outside explicitly disposable local targets, deploy, migration, or live runtime integration is included.
The initial skeleton validates the disposable state target but may perform zero state writes until placement plans explicitly distinguish state-target writes.
Local overlay reading is still not implemented.
The initial skeleton validates its primary repo-local evidence against JSON Schemas.
The initial skeleton understands `workspace|state` placement target semantics, writes only workspace-target files on the current positive path, and fails closed on `state` until future explicit state-write expansion.

## Scope

This contract defines what controlled disposable apply must prove before writing to explicitly disposable local OpenClaw workspace/state targets.
The current skeleton is the first bounded implementation of this contract.
It does not authorize live runtime writes, deploy, migration, local overlay reading, or Crab invocation.

## Controlled disposable apply definition

Controlled disposable apply means applying a schema-validated proposed OpenClaw placement plan only to explicitly disposable local OpenClaw workspace/state targets.
It is local-only.
It is non-production.
It must be safe to clean up.
It must fail closed if the target is not explicitly disposable.
Successful controlled disposable apply does not authorize live runtime apply.

## Allowed future inputs

Controlled disposable apply may consume only:

- schema-validated `proposed_openclaw_placement_plan.json`
- Phase 3 repo-native evidence
- dry-run adapter evidence
- explicit disposable workspace path
- explicit disposable state path
- explicit human approval record

Local overlay target selectors remain future work and are not read by the initial skeleton.

## Forbidden inputs

Future controlled disposable apply must never consume:

- real OpenClaw workspace
- real OpenClaw state
- real KB
- real memory
- live runtime config as committed source
- tokens as source content
- secrets as source content
- production bot/channel identity as source content
- unreviewed arbitrary file targets

## Allowed future writes

Controlled disposable apply may write only to:

- explicit disposable OpenClaw workspace path
- explicit disposable OpenClaw state path when future schema support distinguishes state writes
- repo-local evidence directory for controlled apply

The initial skeleton writes proposed files only into the explicitly disposable workspace target and records zero state writes unless future schema support expands this.
It understands `target_surface = workspace|state` on placement plan items, but rejects `state` writes in the current implementation.

## Forbidden writes

Always forbidden:

- live OpenClaw runtime
- real personal agent workspace/state
- real KB
- real memory
- local overlay
- secrets files
- production deploy target
- Git-tracked runtime contents

## Required preconditions

Before future apply can start, all must be true:

- dry-run adapter is green
- placement plan schema validation is green
- local overlay contract exists
- disposable workspace contract exists
- target path is explicitly disposable
- target path has passed validation
- human review approves the exact target
- no live runtime target is used

Disposable target path validation may be implemented by `operations/harness-openclaw-target-validation/bin/validate_disposable_target_path.sh`.
This validation exists now as a validation-only surface and does not authorize apply.
No-secret-leakage validation for repo-local dry-run evidence is implemented by `operations/harness-openclaw-safety-validation/bin/validate_no_secret_leakage.sh`.
This validation remains required before future apply and does not authorize apply.

## Required validations before apply

Implementation must validate:

- target path containment
- target path marker / disposable marker
- real-agent-state denylist
- placement plan schema still valid
- placement target semantics are explicit
- input refs are repo-relative where expected
- no-secret-leakage precheck
- no-live-runtime precheck
- cleanup path safety

## Required evidence during apply

Implementation must emit evidence such as:

- `apply_meta.json`
- `input_refs.json`
- `target_refs.json`
- `apply_plan_snapshot.json`
- `pre_apply_snapshot.json`
- `apply_actions.json`
- `checks/run_dir_invariants.json`
- `checks/target_path_validation.json`
- `checks/no_secret_leakage_validation.json`
- `checks/no_live_runtime_validation.json`
- `checks/evidence_schema_validation.json`

## Required evidence after apply

Implementation must emit:

- `post_apply_snapshot.json`
- `apply_report.md`
- `apply_report.json`
- `cleanup_plan.json`
- `rollback_plan.json`
- `exit_code`

The initial skeleton emits these artifacts under `operations/harness-openclaw-disposable-apply/runs/<RUN_ID>/`.
It validates `apply_meta.json`, `apply_report.json`, `target_refs.json`, and `apply_actions.json` against JSON Schemas before reporting success.
This is evidence hardening only; it does not expand apply permissions, authorize state-target write expansion, or approve Crab invocation.

## Cleanup and rollback expectations

Controlled disposable apply must support safe cleanup and rollback for disposable targets only.
It must refuse to delete unexpected paths.
It must never clean up real agent state.
It must produce cleanup and rollback evidence.

## No-secret-leakage requirements

Controlled disposable apply must prove that no secrets are copied into repo-local evidence, reports, snapshots, or committed docs.
Secret-like values must be redacted.
Real bot/channel IDs must be redacted unless explicitly authorized for local-only evidence.

## Relationship to dry-run adapter

Controlled disposable apply depends on the dry-run adapter and its evidence.
Dry-run remains the proposal stage.
Controlled disposable apply is a later stage and must not redefine dry-run semantics.
The initial skeleton consumes dry-run evidence and re-runs no-secret-leakage validation before any apply-like copy.

## Relationship to placement plan schema

Controlled disposable apply may only consume a schema-valid `proposed_openclaw_placement_plan.json`.
It must fail closed if the plan is missing or invalid.
The current skeleton accepts `target_surface = workspace` for workspace copies and fails closed on `target_surface = state`.
This does not authorize state-target write expansion, live runtime apply, or Crab invocation.

## Relationship to local overlay

Local overlay may later provide disposable target selectors and local paths.
The initial skeleton does not implement overlay reading.
Overlay remains outside Git.

## Relationship to disposable workspace contract

Controlled disposable apply depends on `docs/DISPOSABLE_OPENCLAW_WORKSPACE_CONTRACT.md`.
Disposable workspace/state rules remain authoritative for target safety.
This contract does not redefine disposable target semantics.

## Relationship to live runtime apply

Live runtime apply remains forbidden and out of scope.
Successful disposable apply is evidence for local validation only and does not authorize live runtime apply.

## Relationship to Crab-safe orchestration

Crab may not invoke controlled disposable apply unless a future approved wrapper explicitly permits it with bounded args, tests, CI, and human review.
This contract alone does not approve Crab invocation.

## Human review requirements

Future controlled disposable apply requires:

- human review of target paths
- human review of the placement plan
- human confirmation that the target is disposable
- human confirmation that no live runtime target is involved

## Validation expectations

Future implementation must include:

- path containment validation
- disposable target marker validation
- real-agent-state denylist
- placement plan schema validation
- no-secret-leakage validation
- no-live-runtime validation
- cleanup validation
- rollback validation
- evidence shape validation, including JSON Schema validation for primary repo-local evidence

## Promotion gates

Before any future implementation PR for controlled apply:

- controlled disposable apply contract exists
- local overlay contract exists
- disposable workspace contract exists
- dry-run adapter remains green
- placement plan schema validation remains green
- no-secret-leakage requirements are defined
- target validation requirements are defined

Before any future live runtime apply discussion:

- separate live runtime contract
- separate live runtime risk review
- rollback plan
- operator approval
- secret handling contract
- production safety checks

## Non-goals

- no controlled disposable apply beyond the initial local-only skeleton
- no disposable workspace implementation
- no OpenClaw writes outside explicitly disposable local targets
- no live runtime apply
- no deploy
- no migration
- no secrets handling code
- no local overlay implementation
- no real KB write-back
- no Crab permission to invoke apply
- no Phase 2/3/4 behavior changes
- no workflow changes

## Acceptance criteria for future expansion

- controlled disposable apply skeleton remains local-only and disposable-only
- disposable target marker validation exists
- target path containment validation exists
- real-agent-state denylist exists
- placement plan schema validation is enforced before apply
- no-secret-leakage validation exists
- no-live-runtime validation exists
- cleanup evidence exists
- rollback evidence exists
- human approval evidence exists
- tests cover refusal to touch real agent state
- CI or local validation proves controlled apply remains local-only and disposable-only
