# LOCAL_DISPOSABLE_TARGET_SELECTOR_CONTRACT

## Purpose

This document defines a bounded local-only selector file for disposable apply target selection.

It is not a full local overlay.
It is not a secrets/config/identity layer.
It is only a non-secret local target selector for disposable workspace/state roots and approval label.
It is not a live target selector and must not be promoted into one.

## Status

This selector is local-only and outside Git.
It does not authorize live runtime apply or Crab invocation.

## Scope

The selector may provide only the absolute local paths and approval label needed to call the existing controlled disposable apply surface.
It remains disposable-only and does not add new OpenClaw integration power.

## Supported selector file shape

The selector is a JSON file with only:

```json
{
  "kind": "openclaw-disposable-target-selector",
  "version": 1,
  "workspace_target": "/abs/path/to/disposable-openclaw-workspace",
  "workspace_approved_root": "/abs/path/to/approved-workspace-root",
  "state_target": "/abs/path/to/disposable-openclaw-state",
  "state_approved_root": "/abs/path/to/approved-state-root",
  "approval_label": "operator-approved",
  "local_only": true,
  "disposable_only": true
}
```

## Required fields

- `kind`
- `version`
- `workspace_target`
- `workspace_approved_root`
- `state_target`
- `state_approved_root`
- `approval_label`
- `local_only`
- `disposable_only`

## Forbidden fields and content classes

The selector must not include:

- API keys
- tokens
- OAuth credentials
- provider/model config
- bot identity
- channel IDs
- real runtime selectors
- KB/memory contents
- arbitrary extra properties

## Outside-Git requirement

The selector file path must be absolute.
The selector file must be outside the repository root.
The selector file content must not be committed.

## Relationship to LOCAL_OVERLAY_CONTRACT

This selector is a narrow exception for non-secret disposable target-path selection only.
It does not implement the broader local overlay described in `docs/LOCAL_OVERLAY_CONTRACT.md`.
It does not permit secrets, provider config, model config, identity, channels, or live-runtime target selection.

## Relationship to CONTROLLED_DISPOSABLE_APPLY_CONTRACT

The selector wrapper may drive controlled disposable apply by forwarding validated selector values to `operations/harness-openclaw-disposable-apply/bin/run_controlled_disposable_apply.sh`.
It must not bypass target validation, no-secret validation, placement plan validation, evidence schema validation, or no-live-runtime validation.

## Relationship to live runtime apply

Live runtime apply remains forbidden and out of scope.
This selector does not authorize live runtime targets or live runtime writes.
This bounded disposable selector is not a live target selector.
It must not be promoted into one by naming convention, path convention, wrapper reuse, or operator habit.
Future live-runtime target selection is separately governed by `docs/LIVE_TARGET_SELECTOR_CONTRACT.md` and must not be inferred from this selector.

## Non-goals

- no full local overlay implementation
- no secrets/config management
- no provider/model/auth/token/identity ingestion
- no Crab invocation approval
- no live runtime apply
- no deploy
- no migration
- no Phase 2/3/4 behavior changes
