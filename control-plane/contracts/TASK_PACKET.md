# TASK_PACKET

Structured request for delegated subtask execution.

## Purpose
Provide a bounded execution contract for a delegated subtask so the executor knows what to use, what to avoid, and what constitutes completion.

## Field semantics
- `id`: stable unique task identifier used across Notion, result packets, review, and observability.
- `task_type`: enumerated category of work such as extraction, synthesis, review preparation, source capture, or schema tightening.
- `title`: short human-readable label for the task.
- `objective`: exact statement of the task outcome being requested.
- `scope`: boundary statement describing what material and decisions are in scope.
- `inputs`: array of structured input references, each with `type`, `ref`, and optional `description` and `version_hint`.
- `constraints`: explicit prohibitions or rules that must be honored during execution.
- `expected_outputs`: structured list of outputs expected from the executor.
- `acceptance_criteria`: reviewable statements used to judge completion.
- `destination_hint`: likely next destination for the primary output; advisory only.
- `priority`: operational urgency signal.
- `provenance_requirements`: evidence expectations that must be preserved in outputs.
- `notes`: extra operator guidance that does not override formal constraints.
- `status_hint`: initial workflow state suggestion for the operational plane.

## Required fields
- `id`
- `task_type`
- `title`
- `objective`
- `scope`
- `inputs`
- `constraints`
- `expected_outputs`
- `acceptance_criteria`
- `destination_hint`
- `priority`

## Optional fields
- `provenance_requirements`
- `notes`
- `status_hint`

## Validation notes
- `id` should be machine-disciplined and unique within the workflow.
- `task_type`, `destination_hint`, `priority`, and `status_hint` are enumerated in schema for consistency.
- `inputs` must contain structured references rather than free-form pasted content.
- `expected_outputs` are typed objects so later review can distinguish packets, notes, source packages, and reports.
- `destination_hint` does not authorize final placement; placement policy still applies.

## Example object explanation
See `examples/sample-task-packet.json`.
- The example delegates a bounded extraction task.
- Its inputs are explicit document references.
- Its constraints prevent invention of new architecture or layers.
- Its expected outputs identify both a result packet and a semantic note proposal.

## Workflow relation
- Created from intake and delegation activity in Notion.
- Consumed by the executor during subtask execution.
- Linked to the resulting result packet and observability records by `id`.
- May trigger later review and placement decisions depending on what the task produces.
