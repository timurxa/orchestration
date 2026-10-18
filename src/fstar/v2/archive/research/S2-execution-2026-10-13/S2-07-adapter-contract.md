# S2-07 — Multi-inflight external adapter

**Status:** complete at specification-contract level. P7 remains a theorem
target over supplied adapter contracts; this report does not claim a source
proof or a concrete adapter implementation.

## Selected contract

Section 2.1 defines a stable logical call key
`K = (operation_identity, CallKey)`. `CallKey` is a run-relative
`NodeOccurrence`, so its path already contains run identity. The exact request
binding is `Q = (canonical_request_bytes, committed_resume_data)`, derived
from the replayed input and pinned request codec. The intent stores resume
data once; the request remains derived rather than becoming a second durable
source of truth. Reusing `K` with a different `Q` is a key conflict.

For each `(K,Q)`, the adapter has at most one exact terminal tuple
`T = (reply_bytes, evidence, charge, artifact_refs)`. Overlapping or recovered
retries may return Pending or the same T; they cannot pick a second result.
This does not make the operation pure: distinct keys can yield different
outputs for identical requests. An operation-specific `EffectSafe` law covers
all submit/query schedules and adapter restarts. Deduplication/status state
must persist or an equivalent remote reconciliation source must exist. If a
non-idempotent effect can occur while its reply is lost and cannot be
reconciled, the operation is inadmissible.

The raw `reply_bytes` are not the journal's typed output encoding. At exact
replayed input `x`, `validate_reply x reply_bytes` produces `y : o x`; the
pinned indexed output codec encodes `y` canonically. `persist_x(T)` pairs those
canonical `output_bytes` with the same receipt's evidence, charge, and
artifact references. `CallOutcome` stores that projection. Its
`P7ReceiptWitness` proves key/request/effect/receipt provenance and equality
to all event fields. Replay decodes canonical typed output bytes; it does not
rerun validation or the external effect. The raw receipt is proof history,
not an extra durable workflow value. P8 proves charge settlement once; P9
proves artifact backing when claimed.

## Interleaving and liveness

The configured multi-inflight capacity `B` is finite and at least two. The
adapter may accept distinct keys up to B and may return them out of order. A
completed key can be validated and queued for its own serial journal append
without waiting for another key. Same-key overlapping retries across crash
are safe because they preserve one terminal tuple and one abstract effect.
The durable `enabled_frontier` is logical; volatile capacity gates immediate
submission but does not remove a pending intent from the frontier. Fairly
consuming a response frees capacity. Safety holds even if a key never
completes; P7/P14 liveness additionally require adapter availability, fair
retry/query and response service, eventual completion or definitive
reconciliation, serial append progress, and finitely many relevant crashes.

## Proof split

- P7 proves adapter binding, same-key terminal stability, effect safety,
  exact-input receipt validation, truthful evidence/charge bounds, and
  conditional outcome availability.
- P15 proves the workflow submits only after intent commit, binds every
  callback to replayed state, commits at most one outcome, and never dispatches
  a committed outcome. A late result for a still-pending key is equivalent by
  P7; after outcome commit it is discarded.
- P3 enforces the one structural outcome transition; P8 proves ledger
  settlement once; P9 proves persistent resource identity when claimed; P10
  and P16 carry the committed canonical result through recovery.
- P13 proves a concrete adapter, request encoding, capacity policy, and
  durable deduplication/reconciliation source refine these contracts.

## Alternatives and limits

Stable-key dedup/status is the general reusable route. Operation-specific
idempotence or reconciliation is also accepted when it proves the same
`EffectSafe` relation. Blind at-least-once redelivery without either law is
rejected. Exactly-once physical transport is not claimed. The model permits
arbitrary distinct-key nondeterminism while requiring deterministic
same-key receipt replay. A finite capacity can be occupied by a permanently
stuck operation; then further dispatch progress is outside liveness premises.

## Review provenance

- [S2-07-adapter-retry-audit.md](S2-07-adapter-retry-audit.md) identified
  exact request binding, key conflict, stable terminal receipts, restart-safe
  effect reconciliation, and the P7/P15/P8/P9 proof split.
- [S2-07-adapter-interleavings-audit.md](S2-07-adapter-interleavings-audit.md)
  identified concurrent same-key retries, out-of-order completion, bounded
  capacity, progress assumptions, and artifact correlation. Its follow-up
  found the raw-reply/canonical-output encoding seam; `persist_x` closes it.
- Post-edit independent review confirmed the receipt-to-event projection is
  consistent across §2.1, event replay, authorization, controller candidate,
  and `key_correctness_theorems.md`; no remaining concrete mismatch was found.

No F* source, tests, adapter implementation, or DAG topology was changed.
