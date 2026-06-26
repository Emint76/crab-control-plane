# Knowledge Distillation Flow Matrix

## Purpose

The Knowledge Distillation Flow Matrix defines the instance-local routes by which an accepted input asset may be distilled into a new knowledge asset.

Contract ID:

```text
knowledge_distillation_flow_matrix.v1
```

`matrix` is the human-facing name. The data model is a directed graph.

The canonical repository owns the generic contract, the meaning of nodes and flows, path semantics, and the placeholder template. The deployed instance owns the active matrix, concrete nodes, concrete flows, concrete `knowledge_type` values, concrete `knowledge_profile_id` values, instructions, and output templates.

The canonical repository must not contain the active concrete matrix for an instance.

## Top-Level Parameters

A matrix contains:

```text
matrix_contract_id
matrix_id
nodes
flows
```

Rules:

- `matrix_contract_id` is `knowledge_distillation_flow_matrix.v1`.
- `matrix_id` is instance-defined.
- `nodes` declares semantic asset classes used by the instance matrix.
- `flows` declares allowed semantic transformation routes between nodes.

## Node Parameters

Each node contains:

```text
node_id
asset_kind
knowledge_type
```

Rules:

- `node_id` is an instance-defined routing identifier.
- `asset_kind` is either `source_capture` or `knowledge_asset`.
- `knowledge_type` is absent or null for a `source_capture` node.
- `knowledge_type` is required and instance-defined for a `knowledge_asset` node.
- Node IDs are not canonical repository taxonomy.
- Nodes describe semantic asset classes used by the instance matrix.

## Flow Parameters

Each flow contains:

```text
flow_id
from_node_id
to_node_id
knowledge_profile_id
status
```

Rules:

- `from_node_id` and `to_node_id` reference declared nodes.
- The input node may be `source_capture` or `knowledge_asset`.
- The output node must be `knowledge_asset`.
- `status` supports at least `draft`, `active`, and `disabled`.
- Only `active` flows may be executed.
- Each flow represents exactly one semantic transformation edge.
- Each flow selects one instance-defined `knowledge_profile_id`.
- The output node determines the requested instance-local `knowledge_type`.
- Multiple active flows may target the same output node.
- The same output knowledge type may therefore be produced independently from different input asset types.
- Each resulting asset retains lineage to the actual input asset used.

The flow matrix must not replace the existing profile registry or taxonomy config:

```text
flow matrix
= allowed semantic transformation routes

profile registry
= instructions and output template for performing a selected transformation

taxonomy config
= allowed physical placement mapping from knowledge_profile_id to knowledge_type
```

## Single-Step Flow Semantics

A flow represents exactly one edge:

```text
one declared input node
-> one declared output node
```

One normal `knowledge-admission` execution processes one selected active flow.

The agent must not encode an entire multi-stage chain as one opaque flow.

## Node Resolution

A concrete input asset must be mapped to a declared matrix input node before flow selection.

For an admitted `knowledge_asset`, `asset_kind` and its admitted `knowledge_type` may identify the node.

For a `source_capture`, or whenever several nodes match the same asset characteristics, node selection is not automatically unique.

Rules:

- if exactly one declared node matches, the agent may use it;
- if multiple declared nodes match, the agent must stop and ask the user to select the input node, output node, or concrete flow;
- the same ambiguity rule applies to requested output-node resolution;
- flow execution begins only after both input and output nodes are unambiguous.

The agent must not guess a node from:

- folder name;
- source-family name;
- asset ID;
- asset slug;
- profile ID;
- undocumented semantic interpretation.

Do not add node fields or runtime selector mechanisms to bypass ambiguity. Node selection is a process step owned by the agent and operator context.

The output of every flow is a separate knowledge asset with:

- its own stable `asset_id`;
- its own placement-only `asset_slug`;
- its own `knowledge_type`;
- its own profile-defined payload;
- direct lineage to the actual input asset;
- transitive provenance back to originating source assets.

## Ordered Multi-Step Path Semantics

A distillation path is an ordered sequence of connected active flows.

Example shape:

```text
flow A: node 1 -> node 2
flow B: node 2 -> node 3
flow C: node 3 -> node 4
```

Adjacent flows connect when:

```text
flow A.to_node_id == flow B.from_node_id
flow B.to_node_id == flow C.from_node_id
```

Path order is derived from graph connectivity.

A path considered for one user request must be a finite simple path:

- the same `flow_id` must not occur more than once in one path;
- the same `node_id` must not occur more than once in one path;
- the agent must not execute a cyclic or indefinitely repeating path;
- a matrix may contain cycles for separately requested transformations, but one execution request must not traverse a cycle;
- exactly one active path means exactly one matching finite simple active path;
- if path resolution remains ambiguous because of cycles or several simple paths, stop and ask the user to choose.

Do not introduce:

- numeric step ordering;
- cycle counters;
- a duplicate sequence field;
- a graph engine;
- a second path registry;
- an opaque full-chain flow type.

The existing `nodes + flows` model is sufficient.

## Intermediate Admission Rule

Every step produces a separate admitted knowledge asset.

The output of one step must be successfully admitted before it is used as the canonical input to the next step.

The process is:

```text
input asset
-> execute one active flow
-> prepare knowledge candidate
-> run normal knowledge admission
-> obtain successful Phase3 evidence
-> use admitted output as the next input asset
-> execute the next active flow
```

Do not use an unadmitted intermediate candidate as canonical input to a downstream flow.

Do not combine several hops into one admission package.

Each hop retains its own:

- candidate;
- admission package;
- destination;
- Phase execution;
- canonical evidence.

## Implicit Shortcuts Are Forbidden

Graph reachability does not authorize an undeclared direct flow.

If the matrix contains:

```text
node A -> node B
node B -> node C
```

the agent must not infer or execute:

```text
node A -> node C
```

unless a separate active direct flow from node A to node C is explicitly declared.

The agent must not:

- skip an intermediate distillation stage;
- invent a missing edge;
- treat transitive reachability as direct authorization;
- activate a draft or disabled flow;
- infer a flow from folder names, profile IDs, asset IDs, or knowledge types.

## Branching And Multiple Incoming Flows

A single output node may have multiple independent incoming flows.

Non-normative, illustrative, instance-defined shape:

```text
input node A -> output node D
input node B -> output node D
input node C -> output node D
```

Rules:

- each incoming flow is independently selectable;
- each incoming flow may use a different `knowledge_profile_id`;
- each execution uses one actual input asset;
- the resulting output asset preserves lineage to that actual input;
- multiple flows targeting the same output node do not imply semantic equivalence;
- Admission and Phase do not reconcile conflicting or overlapping results;
- semantic reconciliation remains the responsibility of the later wiki/semantic layer.

## Non-Normative Conceptual Examples

The following examples illustrate graph capabilities only. They are not canonical taxonomy, not active profile registrations, and not instance configuration.

An instance might later define a connected path such as:

```text
source_capture
-> recipe formula
-> formulation
-> component
```

An instance might also define independent alternatives such as:

```text
source_capture -> product type
recipe formula -> product type
formulation -> product type
```

These words are illustrative and instance-defined. The canonical repository does not register them as concrete `knowledge_type` values or `knowledge_profile_id` values.

## Admission And Phase Boundaries

The matrix authorizes allowed semantic transformation routes. It does not admit assets, create Phase evidence, validate semantic correctness, define physical placement by itself, or replace any existing admission input.

Normal admission still requires:

- an instance profile registry entry for the selected `knowledge_profile_id`;
- an instance taxonomy config that allows the selected `knowledge_profile_id -> knowledge_type` placement pair;
- universal Admission Stage 1 and Stage 2 artifacts;
- standalone admission preflight;
- an accepted exact-HEAD Phase2 baseline;
- Phase4 as the default invocation wrapper;
- Phase3 `kb_admission` as the sole canonical execution and evidence owner.
