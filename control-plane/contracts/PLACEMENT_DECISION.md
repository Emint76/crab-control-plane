# PLACEMENT_DECISION

Decision about destination layer for an artifact.

## Purpose
Capture the explicit routing decision for an artifact when its destination is non-trivial, mixed, or requires documented rationale.

## Field semantics
- `artifact_id`: identifier of the artifact being routed.
- `artifact_type`: normalized artifact class, such as task-packet, result-packet, semantic-note, source-capture-package, knowledge-asset, or observability-report.
- `placement_target`: chosen destination layer or `mixed` when decomposition is required.
- `rationale`: short explanation of why the destination fits the artifact's current role.
- `required_preconditions`: checks that must be satisfied before placement is executed.
- `post_placement_actions`: follow-up actions required after routing.
- `split_targets`: required when `placement_target` is `mixed`; lists decomposed parts and destinations.

## Required fields
- `artifact_id`
- `artifact_type`
- `placement_target`
- `rationale`

## Optional fields
- `required_preconditions`
- `post_placement_actions`
- `split_targets`

## Validation notes
- `placement_target` is enumerated.
- `artifact_type` is normalized so routing logic can be audited consistently.
- `split_targets` should be used only when one source output must be decomposed across layers.
- Preconditions should state review, provenance, or formatting requirements rather than vague preferences.

## Example object explanation
See `examples/sample-placement-decision.json`.
- The example routes a semantic note to Obsidian because it is useful semantic content but not yet a sanctioned KB asset.
- The post-placement actions show how review can continue without confusing draft status with approval.

## Workflow relation
- Produced during placement review or by a routing component.
- Helps explain why an output moved to a given layer.
- Feeds Notion operational state and may precede review or KB admission.
