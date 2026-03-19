# APPROVAL_POLICY

## Purpose
Define how artifacts are approved, returned, held, or rejected before they become sanctioned assets or final control-plane changes.

## Scope
Applies to review decisions for KB admission, control-plane artifact updates, and any output that claims sanctioned or approved status.

## Allowed behavior
- Approve artifacts that meet contract requirements, placement policy, and provenance minimums.
- Return artifacts for revision when the underlying role is correct but the artifact is incomplete.
- Hold artifacts when external clarification or missing evidence is expected.
- Reject artifacts that violate policy boundaries or are not fit for sanctioned storage.

## Forbidden behavior
- Approving an artifact with unresolved blocking issues.
- Marking an artifact as approved only inside an Obsidian note or markdown comment without a review decision.
- Approving KB placement when provenance minimums are missing.
- Treating workflow completion as equivalent to approval.

## Required checkpoints
1. Validate the artifact against its contract and schema.
2. Confirm placement target matches artifact role.
3. Confirm provenance sufficiency for KB-bound assets.
4. Record the review decision, rationale, and required changes if not approved.
5. Ensure the operational plane reflects the active review state.

## Interaction with adjacent layers
- **Notion:** review queue tracks current review status and next action.
- **Contracts:** review decision contract is the structured approval record.
- **KB:** receives assets only after approval and admission conditions are met.
- **Observability:** may store review metrics and failure patterns, but not substitute for the review decision itself.

## Examples
- Approve a source capture package that has canonical pointer, stable representation, and retrieval timestamp.
- Return a knowledge note for revision because source links are missing.
- Hold an asset when legal or access review is pending.
- Reject an artifact that mixes queue state and supposed KB content in one file.

## Failure modes / common mistakes
- Using `approve` as a convenience status before checks are complete.
- Omitting the rationale, which makes later audit difficult.
- Confusing `hold` with `return_for_revision`; the former waits on an external condition, the latter requests changes.
- Allowing approved destination to conflict with placement policy.
