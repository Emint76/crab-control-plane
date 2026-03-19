# review-queue

## Purpose
Track artifacts that need approval, revision, hold, or rejection decisions before final placement. This database holds operational review state, not the sanctioned artifact itself.

## Required properties
- title
- item_type
- status

## Optional properties
- priority
- owner
- source_refs
- related_packet_id
- related_note_id
- review_state
- next_action

## Statuses
- `pending_review`: artifact is ready for reviewer attention.
- `in_review`: reviewer is actively assessing the artifact.
- `changes_requested`: reviewer has issued a return-for-revision decision.
- `on_hold`: review is paused pending external clarification or missing evidence.
- `approved_for_placement`: review passed and the artifact may move to its authorized destination.
- `rejected`: artifact failed review and should not continue without explicit restart.
- `closed`: operational review work is complete.

## Transition rules
- `pending_review -> in_review` when a reviewer begins assessment.
- `in_review -> changes_requested` when the review decision is `return_for_revision`.
- `in_review -> on_hold` when the review decision is `hold`.
- `in_review -> approved_for_placement` when the review decision is `approve`.
- `in_review -> rejected` when the review decision is `reject`.
- `changes_requested -> pending_review` after the artifact is revised and resubmitted.
- `approved_for_placement -> closed` after placement or admission completes.
- `rejected -> closed` when no further review action remains.

## Relation to packet-based workflow
- Review queue entries should reference the artifact under review and any related packet IDs.
- The authoritative structured outcome is the review decision object, while the queue row tracks operational progress.
- `review_state` may mirror the structured decision at a high level but does not replace it.

## Why this is operational state
Review queue rows record who is reviewing what and where the work sits now. They are not the final review decision artifact, policy text, or KB content.
