# Cosmetics and Household Chemistry Extraction Guidance

This directory contains reusable domain guidance for cosmetics and household chemistry knowledge extraction.

It does not register concrete knowledge profiles.

## Ownership

The canonical repository owns the generic profile contract:

```text
knowledge/kb/extraction-profiles/knowledge-extraction.v1.md
```

A deployed instance owns concrete `knowledge_profile_id` values and their active registry entries. An instance may create a recipe/formula profile using `profile_contract_id: knowledge_extraction.v1`, but the concrete profile ID, instruction file, and selected output template are instance-local configuration.

## Optional Output Templates

The repository may provide optional reusable output templates, including:

```text
knowledge/kb/asset-templates/recipe-formula-extraction.md
```

That template is an optional output shape. It does not activate a profile, register a profile, or define a canonical `knowledge_profile_id`.

## Boundaries

- Concrete profile IDs are created by the instance.
- `knowledge_profile_id` is not a `knowledge_type`.
- `knowledge_type` remains an instance-local placement taxonomy segment.
- Neither this domain index nor an output template performs registration.
- Admission and Phase do not validate semantic correctness.
- Domain-specific extraction decisions belong to the instance-defined instruction.
