# SYSTEM_MAP

## Purpose
This map describes the control-plane flow from intake through review, retrieval, and observability without treating the repository as a live runtime instance.

## End-to-end flow
`intake -> delegation -> validation -> execution -> result capture -> placement -> review -> sanctioned storage / retrieval -> observability feedback`

## Flow stages

### 1. Intake
- A request enters the operational plane as a Notion inbox item.
- Intake records title, item type, status, and enough context to decide whether delegation is needed.
- Intake does not create KB assets or semantic notes by itself.

### 2. Delegation
- The orchestrator or operator translates an intake item into a task packet.
- Delegation fixes scope, inputs, constraints, and expected outputs.
- The task packet becomes the bounded execution contract for the subtask.

### 3. Validation
- Task packets are checked against schema and policy before execution.
- Required evidence inputs, acceptance criteria, and destination hints must be present.
- Invalid or underspecified packets return to the operational plane for repair rather than entering execution.

### 4. Execution and result capture
- A delegated executor performs the bounded subtask.
- The executor returns a result packet with produced artifacts, evidence, unresolved issues, and suggested placement.
- Result capture does not itself authorize KB admission.

### 5. Placement
- Placement policy determines whether the output belongs in Notion, Obsidian, KB, observability, or a split across layers.
- Mixed outputs are decomposed so each artifact is stored according to role.
- Placement decisions must record rationale and preconditions.

### 6. Review path
- Assets requiring approval move through the review queue in Notion.
- Review produces a review decision: approve, return for revision, hold, or reject.
- Only approved and sufficiently provenanced assets may enter the KB as sanctioned assets.

### 7. Retrieval path
- Retrieval prefers sanctioned KB assets first.
- Obsidian notes may support reasoning but do not replace source-bearing KB assets.
- Notion operational records may provide context for current state but are not treated as knowledge assets.
- Observability records support diagnosis of how an answer or artifact was produced.

### 8. Observability capture
- Each significant run should emit identifiers that link intake, task packet, result packet, and review outcome.
- Observability stores execution evidence, eval outputs, routing metrics, and failure signatures.
- Observability informs future improvements but does not auto-edit control-plane policy.

### 9. Future evolution-loop relationship
- The evolution loop may analyze repeated failures, low-confidence results, or routing mistakes.
- It may propose policy, prompt, schema, or template changes.
- Proposed changes require human review and a normal repository change process before becoming part of the control plane.

## Main components and boundaries

| Component | Primary role | Must not do |
|---|---|---|
| Notion | operational workflow state | act as canonical policy or final KB |
| Obsidian | semantic note layer | act as queue manager or approval system |
| KB | sanctioned asset store | hold raw task traffic or mutable workflow state |
| Observability | execution evidence and reports | replace review decisions or knowledge storage |
| Git repo | control-plane source of truth | act as live runtime database |

## Key control points
- **Delegation control:** task packet completeness and scope discipline.
- **Validation control:** schema conformance and policy checks.
- **Placement control:** route by role, not by convenience.
- **Review control:** approve only assets with adequate provenance and fit.
- **Retrieval control:** prefer sanctioned assets over drafts.
