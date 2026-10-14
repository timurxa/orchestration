# S2-07 audit — out-of-order outcomes and conditional progress

Read-only adversarial review by `/root/s207_adapter_liveness_audit`. No
source, implementation, F* run, or tests.

## Required P7 transitions

For a committed pending intent, adapter submission is allowed only with the
exact derived stable key, pinned operation identity, reconstructed typed
input, canonical request, and committed resume data. It consumes capacity.
Different keys may be outstanding together; retries/queries for the same key
refer to the same logical operation. A response must match that key and
request binding, pass the pinned validator at the exact input, and carry a P7
receipt witness for evidence, charge, effects, and artifact references.
Charge must fit the maximum reserved by the intent. A validated response can
produce only that key's `CallOutcome`; current-head authorization and replay
allow at most one commit. The committed outcome absorbs the key; duplicate or
late callbacks are ignored.

The complete terminal tuple for a key must be stable across overlapping
retries: exact output bytes, evidence, charge, and artifact references (or a
canonical terminal identity that uniquely determines all of them). Otherwise
two valid callbacks for one still-pending key could race to commit different
settlements. Different keys may return different outputs for identical
requests.

## Adversarial schedules

- Remote effect succeeds, reply is lost, restart resubmits same key while the
  old request still runs: retries join/reconcile without a second unaccounted
  effect and converge on the same terminal tuple.
- A slow key `k1` and completed key `k2` overlap: `k2` can be validated and
  committed before `k1`; completion order creates no head-of-line wait.
- Two retries for one key return in reverse order: both responses agree on
  one terminal tuple; only one outcome commit is permitted.
- A duplicate response after outcome commit is discarded.
- A response for a changed request, operation identity, or absent intent is
  rejected.
- Distinct keys with identical input remain distinct; each has its own
  outcome and charge, and may have different valid outputs.

## Progress boundary

Safety and liveness are separate. Liveness needs fair retry/query scheduling,
an available adapter, eventual operation completion or definitive
reconciliation, serial journal append progress, and finite relevant crashes.
A positive finite in-flight bound is needed for useful bounded concurrency.
If capacity is full, the controller must consume completed keys and release
slots; it must not wait for a particular earlier key. One permanently stuck
key may retain a slot, so progress for other work is conditional on available
capacity; it cannot be inferred from at-least-once delivery alone. A pending
intent must not remain forever in an irreconcilable “unknown” state under P7.

## Event boundary

`CallOutcome` already carries artifact references in the journal event
vocabulary. The `OpRef` sketch should expose them in its schematic outcome
record too, so their same-key correlation is explicit. P9 remains the separate
proof of durable backing-object identity.

## Receipt-to-journal encoding seam and resolution

Post-edit review found that raw receipt `reply_bytes` and canonical journal
`output_bytes` were named as if they were the same bytes. The normative spec
now defines `persist_x(T)`: validate the raw reply at exact `x`, encode the
typed result with the pinned indexed output codec, and copy evidence, charge,
and artifact references from that exact receipt. `CallOutcome` stores the
projection, not raw reply bytes. Its `P7ReceiptWitness` proves the projection
matches all event fields. Replay checks canonical typed bytes with the indexed
codec and never reruns external validation/effects. The key theorem guide's
`correlated(intent,outcome,k)` expands to this witness/equality. The reviewer
confirmed this projection is consistent across the API sketch, event guard,
authorization, candidate, replay, and theorem guide.
