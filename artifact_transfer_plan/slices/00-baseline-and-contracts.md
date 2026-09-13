# Slice 0 — baseline and revised registry contracts

## Purpose

Freeze current behavior, then define the runtime-owned artifact registry before
changing metadata plumbing.

## Status

Rework required. Existing baseline records old sidecar behavior.

## Work

1. Preserve unrelated dirty worktree changes.
2. Confirm current project build/test commands.
3. Record current Flow[A] and generated Artifact shapes.
4. Define record ownership and ID-reference invariants.
5. Add or specify fixtures for scalar, nested object, Location, sequence,
   option, and tagged output values.
6. Keep fake transport tests unchanged until compatibility adapters exist.

## Contract

    type ArtifactID* = uint64

    type ArtifactMeta* = object
      id*: ArtifactID
      artifact_dir*: Path

    type ArtifactRecord*[A] = object
      data*: A
      meta*: ArtifactMeta

    type RuntimeContext*[A] = ref object
      artifacts*: Table[ArtifactID, ArtifactRecord[A]]

Invariants:

- record.meta.id equals table key;
- records live only in RuntimeContext.artifacts;
- persistent runtime state stores IDs, not copied records;
- active processing resolves IDs and uses ordinary A;
- independently generated A values may be registered later;
- no generated Flow[A] or compile-time artifact packer references records.

Output decoding still returns explicit success/error without constructing an
invalid A; decoder result shape remains a separate Slice 4 decision.

## Test gate

- Existing execution, lowering, interface, and IPC tests pass.
- Contract fixture covers first registration and table lookup.
- Baseline generated source remains record-free.
- No implementation changes occur outside revised registry work.
