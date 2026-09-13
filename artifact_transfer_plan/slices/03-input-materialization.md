# Slice 3 — compile-time input materialization

## Purpose

Restore historical recursive materializer for model input.

## Files

- `src/vecherinka_comptime.nim`
- artifact materialization tests

## Work

Port and adapt historical walker:

- `materialize_node_kind`;
- `materialize_tree`;
- field and variant inspection;
- sequence and option traversal;
- instruction path helpers;
- location contract path traversal.

Generated materializer signature should receive:

- typed input value;
- source artifact root;
- destination artifact root;
- optional initial instruction text.

Generated output:

```text
problem.goal: string = Fix parser
problem.codebase: location = repo
items[1]: string = first
optional: Option:none
```

Behavior:

- inline leaves become text;
- `Location` leaves copy source payload to identical relative destination path;
- variants visit active branch only;
- sequences use one-based human paths;
- absent options emit explicit none marker;
- source errors become model submission errors before agent creation.

Resolve aliases and distinct wrappers. Preserve public field names. Reject unsupported object shapes at compile time.

## Test gate

- scalar input text exact;
- nested object paths exact;
- active variant only;
- inactive variant not copied or rendered;
- sequence indexes one-based;
- present option materializes;
- absent option emits none;
- file copied;
- directory copied recursively;
- missing location returns error;
- ordinary strings remain literal;
- repeated model input gets independent destination copy.

## Done when

Fake transport can inspect complete materialized input instructions and destination tree.

