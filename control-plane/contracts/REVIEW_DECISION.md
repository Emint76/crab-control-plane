# REVIEW_DECISION

Review outcome for an artifact.

## Purpose
Provide the authoritative structured record of review status for a candidate artifact, including whether it is approved, blocked for revision, held, or rejected.

## Field semantics
- `artifact_id`: identifier of the artifact under review.
- `decision`: enumerated outcome: `approve`, `return_for_revision`, `hold`, or `reject`.
- `rationale`: concise explanation of why the decision was reached.
- `blocking_issues`: issues that prevent approval or placement.
- `required_changes`: concrete revisions required before resubmission.
- `approved_destination`: destination authorized if the artifact is approved or conditionally staged.
- `reviewer_notes`: extra guidance that helps the next operator or author.

## Required fields
- `artifact_id`
- `decision`
- `rationale`

## Optional fields
- `blocking_issues`
- `required_changes`
- `approved_destination`
- `reviewer_notes`

## Validation notes
- `decision` is enumerated and should control downstream state transitions.
- `approved_destination` should align with placement policy; it must not authorize an impossible destination.
- `blocking_issues` should be populated for `return_for_revision`, `hold`, or `reject` when the reason is substantive.
- `required_changes` should be actionable rather than generic.

## Example object explanation
See `examples/sample-review-decision.json`.
- The example returns a semantic note for revision because provenance is incomplete.
- The destination remains Obsidian because the artifact is still a draft semantic note.

## Workflow relation
- Created during review in the operational plane.
- Controls whether an artifact returns for work, waits for clarification, is rejected, or can move to sanctioned storage.
- May authorize KB placement only when the artifact also meets admission requirements.
