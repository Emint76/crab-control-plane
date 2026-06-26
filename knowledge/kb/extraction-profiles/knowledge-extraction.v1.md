# knowledge_extraction.v1

## Purpose

`knowledge_extraction.v1` is the canonical generic contract for instance-defined knowledge extraction profiles.

It defines the cross-domain requirements that every deployed agent instance must satisfy before preparing a knowledge candidate for admission. It is not a concrete `knowledge_profile_id`.

Concrete profiles are created by the deployed instance after control-plane installation and after receiving a concrete extraction task.

Example instance-local shape:

```text
<instance-config-root>/
  knowledge-profiles/
    <instance-defined-profile-id>/
      profile.json
      instruction.md
```

## Required Instance Profile Fields

An instance-defined profile must provide:

```text
profile_contract_id
knowledge_profile_id
instruction_ref
output_template_ref
payload_kind
placement_policy_id
status
```

The `profile_contract_id` value for this contract is:

```text
knowledge_extraction.v1
```

`knowledge_profile_id` is instance-defined. In plain terms: knowledge_profile_id is instance-defined. It is the concrete extraction profile identifier, not a canonical repository taxonomy and not a `knowledge_type`.

## Cross-Domain Rules

Every instance-defined profile using this contract must preserve these rules:

- an accepted provenance-bearing input asset is required;
- the input asset may be an accepted `source_capture` asset;
- the input asset may be an already admitted `knowledge_asset` when an active instance Knowledge Distillation Flow Matrix flow authorizes that transformation;
- semantic extraction is agent-owned;
- directly source-stated material, agent interpretation, inference, not stated, and not validated must remain distinguishable;
- direct provenance to the selected input asset must be preserved;
- transitive provenance back to originating source assets must be preserved;
- upstream input assets must not be mutated;
- every downstream knowledge asset needs a new stable identity;
- concrete profile instructions are instance-owned;
- output template selection is instance-owned;
- the concrete profile is selected through the active instance flow being executed;
- one profile execution performs one semantic transformation edge;
- `knowledge_profile_id` is instance-defined;
- `knowledge_type` is a separate instance-local placement value;
- Admission and Phase do not validate semantic correctness;
- concrete domain vocabulary, tables, fields, safety rules, and extraction decisions belong to the instance-defined instruction.

## Boundaries

This generic contract is not a semantic validator.

It is also not:

- a parser;
- a canonical taxonomy;
- a Phase implementation;
- a concrete recipe, component, product-type, or formulation profile;
- a registry of active profiles.

The canonical repository may provide optional reusable output templates, but an instance-defined profile must explicitly select them. The presence of an optional template in the repository does not activate a concrete extraction profile.
