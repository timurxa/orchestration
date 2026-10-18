# V2-01 implementation addendum

> **Historical snapshot — before the final simplification audit.** In
> particular, the bundle identity is still not proved to match its registry
> contents; see the current P0 boundary in `implementation_spec.md` and
> `V2-01-02-simplification.md`.

**Date:** 2026-10-12

The earlier `V2-01-identity-audit.md` is a pre-implementation snapshot; its
statement that there is no resolver or journal vocabulary no longer describes
the current source. `WorkflowV2.Identity.fst` now contains a derived
`work_package`, heterogeneous work/codec lookup, exact-successful-resolution
lemmas, same-identity registry-bundle evidence, and codec canonicality lemmas.
`WorkflowV2.Journal.fst` now declares first-order event/action vocabulary.
The full module set passes the strict V2 `verify` command.

The audit's principal cautions remain current: registry uniqueness is a proof
field rather than a fact derived from a concrete closed registry constructor;
exact F* value selection does not prove the host reloads that bundle after
restart; and graph decoding still needs existential schema/type resolution.
V2-01 is complete only as the declaration milestone. P0 and host refinement
are not claimed discharged.
