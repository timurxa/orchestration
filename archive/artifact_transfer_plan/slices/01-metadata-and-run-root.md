# Slice 1 — artifact registry and ID-based runtime state

## Purpose

Make RuntimeContext the sole owner of ArtifactRecord values. Replace
persistent A plus ArtifactMeta storage with ArtifactID references while
keeping active execution and generated flows on A.

## Status

Rework required. Current implementation has directories and sidecar metadata,
but no registry and still stores typed values in runtime state.

## Files

- src/vecherinka_runtime.nim
- runtime execution tests
- generated source fixtures only if needed to prove no comptime dependency

## Target types

    type ArtifactRecord*[A] = object
      data*: A
      meta*: ArtifactMeta

    RuntimeContext[A].artifacts*: Table[ArtifactID, ArtifactRecord[A]]

Add main-thread helpers:

- register an independently created A with metadata;
- look up a record by ID;
- validate table key and ArtifactMeta.id;
- reserve output ID/root without publishing an incomplete record.

## Runtime migration

Change persistent fields:

- Activation.input plus artifact_meta becomes artifact_id.
- WorkNode.input/output become Option[ArtifactID]; remove paired metadata.
- JoinState.slots become seq[Option[ArtifactID]]; original input becomes ID.
- PendingModel stores input ID and reserved output identity/root.
- WorkPlan.output becomes output ID; remove separate output metadata.
- ready queues carry activations containing IDs.
- runtime/global events carry IDs or reservation data, never records.

At each handler boundary:

1. Resolve ID from context.artifacts.
2. Copy or borrow record.data into local A.
3. Run existing fk_raw, fk_it, fk_so, lift, join, and model logic.
4. Register newly created A before storing or queuing its ID.

Registration rules:

- initial input registers before entry activation;
- raw values register when reached;
- projections and lift-produced values register before handoff;
- pass-through reuses its ID;
- fanout reuses input ID;
- joins register constructed values;
- model output registers only after successful validation.

Generated Flow[A] fields remain unchanged. Generated model submit can retain
A and metadata as processing arguments; only runtime-owned storage changes to
IDs and records.

## Important invariants

- Every runtime-held artifact has one context-table record.
- No ID is queued before its record exists.
- No output ID is published before typed output validation succeeds.
- A fresh model root may exist without a record while model work is pending.
- Reader threads never access the table.

## Test gate

Add tests for:

- initial input registration and lookup;
- raw, it, lift, join, and model registration;
- pass-through ID preservation;
- distinct IDs for newly created values;
- node/join/pending/plan fields storing IDs;
- unknown ID failure;
- table key and metadata ID mismatch;
- source root unchanged after registration;
- generated Flow[A] lowering unchanged.
