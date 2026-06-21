# Skills

`skills/` contains versioned agent-facing skill packages.

The Git package is the canonical source for a skill. A live OpenClaw workspace copy is an installed or runtime copy, not the source of truth.

Expected live placement after a separate install step is:

```text
<OPENCLAW_WORKSPACE>/skills/<skill-name>/
```

Repository presence does not install the skill into OpenClaw, update an existing live copy, or authorize runtime use.

## Boundaries

Skills must follow repository policy, contracts, and Phase ownership.

Skills may describe agent-facing procedures, helper checks, examples, and routing guidance. They must not redefine Phase2, Phase3, or Phase4 semantics.

Skills must not contain:

- secrets or credentials;
- live state;
- KB data;
- generated run evidence;
- caches or bytecode;
- instance-specific config;
- production sync code.

Automated install or apply from Git into OpenClaw is not implemented in this repository.
