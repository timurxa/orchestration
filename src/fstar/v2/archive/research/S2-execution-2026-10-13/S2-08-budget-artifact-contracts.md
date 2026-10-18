# S2-08 — Budget and artifact/resource contracts

**Status:** complete at specification-contract level. P8 and P9 remain proof
targets over the supplied metric, ledger, codec, and resource-store contracts;
this report does not claim F* proofs or a concrete store implementation.

## Decisions

### P8: charge and expansion-fuel ledger

Each run pins one `ChargeMetricIdentity` in `RunBudget`. `OperationIdentity`
binds its operation package to that metric; a run admits only operations with
the same metric. The pinned metric is passed explicitly to graph generation
from the replayed run budget. `GenerationAllocation` contains only the
occurrence's expansion-fuel and charge allowances, so it does not duplicate
the run-wide metric. Generator membership proves admission for every
registry-supported metric and allocation.

For every reachable state `S`, P8 establishes:

```text
total_charge = free + sum(allocated) + sum(reserved) + spent
total_fuel   = fuel_free + sum(fuel_allocated) + fuel_consumed
```

Allocation maps and aggregates are projections from the canonical budget,
committed graph plans, intents, outcomes, and expansions. They are not
independently mutable state. Root plans are checked before subtraction. A
graph commit replaces the generator's pool with bounded child pools, returns
unused charge to `free`, and consumes unallocated expansion fuel. An intent
moves the exact operation maximum from allocated to reserved; its one outcome
moves actual charge to spent and returns the unused reservation to `free`.
Every inequality is checked before natural subtraction. Free remainder is
accounted for but never dynamically reallocated; generators can subdivide
only their committed parent pool. The contract meters only the pinned charge
unit and graph-expansion fuel, not CPU, memory, retries, or wall time.

The theorem split is explicit: P3/P4 establish replay and allocation
transition premises; P7 binds a truthful receipt charge to its logical call;
P15 serializes each ledger transition under arbitrary concurrent completion;
P8 proves aggregate conservation and once-only settlement.

### P9: typed references to durable resources

`ArtifactRef(a)` is an opaque typed reference; `PackedArtifactRef` existentially
packages heterogeneous references in event inventories. The pinned manifest
resolves its artifact type, schema, canonical reference codec, store, and
interpretation. `ResourceProjection` supplies `refs_of` for each typed value
and proves it is an exact duplicate-free inventory. Event artifact lists
equal that projection. Root inputs, graph constants, local results, and
external results use the same projection; evidence and resume bytes cannot
introduce workflow-visible references.

An `ArtifactPackage(a)` supplies publication/validation, restart resolution,
denotation, and a same-logical-resource relation. Its laws require canonical
reference round trips, stable immutable version identity, no overwrite/delete/
ABA while reachable, and idempotent publication or rejection of conflicting
reuse. Every newly referenced backing object is complete and durable before
the journal append commits. Every supported restart resolves a committed
reference to a handle denoting the same typed logical object and version.
“Same” does not mean the same process-local handle; it must preserve all
observations and operations admitted by the pinned resource semantics.

P9 publication witnesses are carried in semantic append authorization and
`SemWF`; P3 replay checks canonical reference syntax and type metadata without
calling the store. A crash after publication but before event commit can leave
an unreachable orphan. P15 exposes references to consumers only after commit.
P9 extends P15/P16 only when persistent resource identity is claimed; P14
adds store-progress assumptions only for workflows that need resolution.
P13 must prove any concrete host store refines the resource package rather
than relying on an unconstrained equivalence relation.

Immutable files, trees, and object-store snapshots fit this abstraction.
Mutable database or network resources require a pinned snapshot/version or a
durable reopen/continuation relation. A process-local socket/cursor handle is
not itself a restart-stable resource.

## Alternatives considered

- A vector of charge units could account for heterogeneous costs, but it adds
  ledger dimensions and is unnecessary for this minimal system. One pinned
  metric makes all compared naturals meaningful.
- Putting the charge metric in every allocation was rejected because it
  duplicates the run-wide source of truth. The metric is taken from
  `RunBudget` and passed to generators explicitly.
- Untyped opaque labels were insufficient for resource recovery. Existentially
  packed typed refs preserve heterogeneity while binding each reference to an
  exact manifest package.
- Requiring the same OS handle after restart was rejected. The contract is
  stable logical identity/version with equivalent admitted observations.
- Making replay query the resource store was rejected: replay remains a pure
  journal transition; publication/resolution facts are semantic witnesses and
  concrete refinement obligations.

## Review provenance

- [Charge/fuel audit](S2-08-charge-ledger-audit.md) checked allocation bounds,
  arithmetic, transition ownership, metric consistency, and P7/P8/P15 split.
- [Artifact/resource audit](S2-08-artifact-contract-audit.md) identified
  missing typed identity, exact inventory, publication order, restart
  identity, and mutation guarantees.
- [Composition audit](S2-08-composition-audit.md) checked P8/P9 against
  S2-04–07, P10, P15/P16, and liveness boundaries.
- Final integrated audit passed. One audit-report wording mismatch was
  corrected so P8, rather than P3/P4, owns aggregate conservation.

The normative contracts are in [implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md),
with theorem summaries in [key_correctness_theorems.md](../../schema_era_2026-10-14/key_correctness_theorems.md).
No DAG topology or acceptance condition changed. No `.fst`/`.fsti` source,
implementation, F* command, or tests were used.
