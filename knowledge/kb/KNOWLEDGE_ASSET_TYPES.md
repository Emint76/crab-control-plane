# KNOWLEDGE_ASSET_TYPES

## Purpose

This document records the repository boundary for knowledge asset typing.

The canonical repository does not define active concrete extraction profiles, domain-specific output templates, or a canonical knowledge type taxonomy.

Concrete `knowledge_profile_id` values and their domain-specific semantics are instance-defined.

## Canonical Rule

The repository owns the generic extraction profile contract:

```text
knowledge/kb/extraction-profiles/knowledge-extraction.v1.md
```

A deployed instance may define concrete profiles using that contract. Those instance profiles may select local or reusable output templates, but the selection and profile semantics are instance configuration and must not be treated as canonical repository registration.

## Boundary

- `profile_contract_id` identifies the generic canonical mechanism, currently `knowledge_extraction.v1`.
- `knowledge_profile_id` identifies a concrete instance-defined extraction profile.
- `knowledge_type` is a separate instance-local placement taxonomy segment.

Do not derive `knowledge_type` from `profile_contract_id`, `knowledge_profile_id`, instruction paths, template paths, asset IDs, or slugs.

Admission and Phase do not validate semantic correctness. Semantic extraction is agent-owned, and later semantic review belongs to the wiki/semantic layer.
