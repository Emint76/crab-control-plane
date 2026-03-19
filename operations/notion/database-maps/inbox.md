# inbox

## Purpose
Capture newly arrived work before it is delegated, rejected, or routed elsewhere. The inbox is an operational staging area, not canonical policy or sanctioned knowledge storage.

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
- `new`: item has arrived and awaits triage.
- `triaging`: operator is deciding whether to delegate, reject, or merge with existing work.
- `ready_for_tasking`: sufficient clarity exists to create a task packet.
- `closed`: item was rejected, merged, or otherwise resolved without further inbox action.

## Transition rules
- `new -> triaging` when an operator starts assessing the intake item.
- `triaging -> ready_for_tasking` only when the item has enough context to generate a task packet.
- `triaging -> closed` when the item is duplicate, out of scope, or otherwise disposed of.
- `ready_for_tasking -> closed` after a task packet is created and the active workflow continues in the task queue.

## Relation to packet-based workflow
- Inbox items may eventually produce a task packet, but are not themselves task packets.
- `related_packet_id` is empty until delegation occurs.
- `source_refs` may point to intake evidence used to prepare delegation.

## Why this is operational state
Inbox rows represent mutable workflow position and triage status. They are not durable semantic notes and they are not sanctioned KB assets.
