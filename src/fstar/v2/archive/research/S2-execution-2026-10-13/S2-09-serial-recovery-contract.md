# S2-09 — Serial store, every-cut recovery, and semantic theorem

**Status:** complete at specification-contract level. P10 and P16 remain
theorem targets over the supplied contracts; no source proof or concrete
journaler is claimed.

## P10 contract and theorem

The journaler is serial. An authorized append is linearizable against its
exact expected prefix and either commits exactly one event or returns stale
without changing the journal bytes. At most one append is active for a run.
Event and journal codecs have round-trip and canonical-encoding laws.

The physical bytes returned by a load are the single durable source of truth.
`load_store` is their decoded projection, constrained by `load_bytes_decode`.
For every valid history `H` and recovery-load cut `c`, let `J(H,c)` be the
longest prefix whose commit points passed the barrier and `B(H,c)` the exact
loaded bytes. P10 requires:

```text
decode_journal(B(H,c)) = Ok(J(H,c))
encode_journal(J(H,c)) = B(H,c)
recover(H,c) = replay(J(H,c))

for cuts c <= d:
  J(H,c) is a prefix of J(H,d)
```

The second equation follows from the journal codec's canonicality law and the
first. The recovery barrier settles or fences every append request from the
old controller before loading; none can commit after the load. An event whose
commit point passed remains present at every later cut in the same position.
An in-flight append at process exit may commit before the barrier and then is
included, or it aborts and cannot appear later. “Journaled” means the append
linearization point has passed.

This theorem is conditional on the journaler contract. P13 must show that a
concrete store's append, flush, load, and fencing operations satisfy it. Disk
loss, corruption, rollback, and external edits remain outside the crash
model. The journaler need not accept concurrent inputs; abstract workflow
nodes may execute concurrently while all writes serialize through this
interface.

## P16 composition

P16 takes a controller trace `tau`, its serialized append projection, and any
recovery-load cut. P10 proves the exact prefix and canonical bytes. P15 proves
that every event was authorized under its current replay head across all
allowed interleavings. `SemWF` retains those append-time origin witnesses as
ghost state. P1/P2/P4/P5 supply typed root/generated DAGs and stable topology;
P6/P7 supply exact local/external result provenance; P8 supplies ledger
invariants. P16 composes these facts at every cut.

The conclusion has separate domains:

- **Recovered state:** `recover` is exactly `replay(J_c)`; semantic witnesses
  correspond to precisely the events in that committed prefix.
- **Graph and value correctness:** every root/generated graph is universally
  typed and acyclic; reconstructed ready inputs agree with typed wiring; each
  committed result or generated graph has exact pinned provenance.
- **No repeat after commit:** `NoPostCommitExecution(tau)` is a controller
  trace property. The separate state property says committed occurrences are
  absent from the recovered frontier. A pending intent at the cut can be
  retried only with its exact committed operation/key/request/resume binding;
  P7 reconciles retries to the same logical effect. Eventual completion is
  not asserted here.
- **Optional resources:** P9 extends the theorem to physical resource
  publication and stable immutable logical identity when the workflow claims
  those guarantees.

The theorem guide's compact `P10P15CutTransfer` is intentionally narrower: it
only transports `SemWF` and exact replay across a cut. It is not a substitute
for full P16.

## Alternatives and limits

- Serial journal appends were retained. The executor and adapter may overlap
  independent work; a concurrent journaler would add no required expressivity
  and would complicate the one-transition ghost proof.
- The crash cut is the recovery-load barrier after old requests settle or are
  fenced. This resolves the exit-versus-in-flight-append race without losing
  an event whose commit point has passed.
- The abstract theorem ranges over a journaler value that proves its contract.
  Physical storage correctness is a P13 refinement proof, not an unchecked
  premise smuggled into P10 and not an implementation detail of replay.

## Review provenance

- [P10 journaler/cut audit](S2-09-journaler-cut-audit.md)
- [P16 composition audit](S2-09-p16-composition-audit.md)
- S2-08 P8/P9 composition audit was rechecked for interactions with this node.
- Independent reviews passed after the loaded-byte and trace-scope
  clarifications. No DAG topology or acceptance condition changed.

The normative statements are in [implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md)
and [key_correctness_theorems.md](../../schema_era_2026-10-14/key_correctness_theorems.md). No
`.fst`/`.fsti` source, implementation, F* command, or tests were used.
