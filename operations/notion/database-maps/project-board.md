# project-board

## Purpose
Track grouped operational initiatives that contain multiple intake items, task packets, review items, or KB admission efforts. This is a coordination view, not a canonical knowledge store.

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
- `planned`: project exists but execution has not started.
- `active`: at least one operational workstream is underway.
- `at_risk`: project progress is threatened by blocked tasks, unresolved review, or missing evidence.
- `awaiting_review`: primary deliverables are produced and major review remains.
- `closed`: project scope is complete, canceled, or superseded.

## Transition rules
- `planned -> active` when delegated work starts.
- `active -> at_risk` when blockers materially threaten progress.
- `at_risk -> active` after the blocking condition is resolved.
- `active -> awaiting_review` when major outputs are produced and awaiting final review.
- `awaiting_review -> closed` when remaining review work is complete or the project is otherwise concluded.

## Relation to packet-based workflow
- The project board may link multiple task packets and review items through `related_packet_id` or supporting relations.
- It does not replace task or result packets; it aggregates them for operator visibility.
- `source_refs` may point to shared evidence bundles relevant to the project.

## Why this is operational state
A project row reflects coordination status across multiple artifacts. It is mutable workflow state and not a sanctioned knowledge asset.
