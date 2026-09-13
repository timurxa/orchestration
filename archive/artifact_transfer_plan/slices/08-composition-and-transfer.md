# Slice 8 — composition and ID transfer

## Purpose

Prove artifact transfer through flow composition using IDs into one global
per-context registry.

## Status

Rework required. Existing tests prove sidecar metadata propagation, not
registry-backed references.

## Work

Sequential transfer:

1. Model A resolves input ID to A data.
2. Model A creates and publishes one ArtifactRecord.
3. Model B receives model A's output ID.
4. Runtime resolves that ID to A data and metadata.
5. B materializes locations into B's fresh root.
6. B publishes a new record and output ID.

Composition rules:

- raw/it/lift-created values register before handoff;
- pass-through paths reuse IDs;
- fanout branches reuse input ID;
- join slots store IDs, not A values or metadata;
- join construction resolves slot IDs to A values, creates new A, and registers
  one output record;
- distinct source roots remain addressable through runtime-relative Location
  values;
- no directory ownership passes between records.

Generated pack/unpack and Flow[A] remain unchanged.

## Test gate

- two sequential model calls;
- model after it, so, and lift;
- same-root and distinct-root fanout;
- distinct-root join retains both locations;
- every stored node/join/plan reference resolves through context table;
- source artifact remains unchanged;
- no persistent runtime field stores copied A plus ArtifactMeta.
