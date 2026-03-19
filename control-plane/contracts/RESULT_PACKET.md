# RESULT_PACKET

Structured result returned by delegated execution.

## Purpose
Report what a delegated task produced, how well supported the output is, what remains unresolved, and what downstream action should happen next.

## Field semantics
- `task_id`: identifier of the originating task packet.
- `result_summary`: concise statement of what the execution accomplished.
- `produced_artifacts`: structured list of outputs with artifact identity, type, role, and path or reference.
- `unresolved_issues`: issues that block approval, further placement, or confident use.
- `confidence`: bounded confidence assessment of the result quality.
- `evidence`: structured support references such as documents, notes, captures, or logs.
- `suggested_placement`: proposed downstream destination for the primary artifact.
- `suggested_followups`: additional actions that should happen after review.
- `warnings`: non-blocking concerns that reviewers should notice.

## Required fields
- `task_id`
- `result_summary`
- `produced_artifacts`
- `unresolved_issues`
- `confidence`
- `evidence`
- `suggested_placement`

## Optional fields
- `suggested_followups`
- `warnings`

## Validation notes
- `task_id` must match an existing task packet identifier.
- `produced_artifacts` should not be free-form objects; the schema requires artifact identifiers, types, and references.
- `evidence` should indicate support type and reference so provenance can be reviewed.
- `suggested_placement` is advisory and must be reconciled with placement policy.
- A medium or low confidence result may still be valid, but the uncertainty should be reflected in unresolved issues or warnings.

## Example object explanation
See `examples/sample-result-packet.json`.
- The example reports one semantic-note artifact produced from an extraction task.
- The unresolved issue states why the output is not yet KB-ready.
- Evidence points back to the source document used during execution.

## Workflow relation
- Produced after subtask execution.
- Used by placement and review workflows to decide next actions.
- Linked to Notion operational rows, review decisions, and observability records via `task_id` and artifact identifiers.
