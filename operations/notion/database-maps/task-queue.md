# task-queue

## Purpose
Track active delegated work after a task packet has been created and before review is complete. This database is the operational execution queue.

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
- `queued`: task packet exists and awaits execution.
- `in_progress`: delegated execution is active.
- `blocked`: execution cannot continue until an identified issue is resolved.
- `awaiting_result_validation`: execution finished and the returned result packet needs validation.
- `moved_to_review`: validated outputs now require review workflow.
- `closed`: task is complete, canceled, or superseded.

## Transition rules
- `queued -> in_progress` when execution begins.
- `in_progress -> blocked` when constraints, missing inputs, or failures stop progress.
- `blocked -> in_progress` after the blocking issue is resolved.
- `in_progress -> awaiting_result_validation` when a result packet is returned.
- `awaiting_result_validation -> moved_to_review` only after result packet validation succeeds.
- `moved_to_review -> closed` when downstream review ownership takes over.

## Relation to packet-based workflow
- Each active row should carry `related_packet_id` pointing to a task packet.
- Validation failures may keep the row in `awaiting_result_validation` while the result packet is repaired.
- `related_note_id` is optional and only links produced semantic notes; it does not replace the packet linkage.

## Why this is operational state
The task queue stores mutable ownership, priority, and execution state. Those properties are operational and must not be confused with canonical knowledge or policy.
