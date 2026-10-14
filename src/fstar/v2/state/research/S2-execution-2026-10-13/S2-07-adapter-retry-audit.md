# S2-07 audit — stable keys and effect-safe retry

Read-only design review by `/root/s207_adapter_retry_audit`. No source,
implementation, F* run, or tests.

## Findings

Current §2.1 already rejects purity assumptions for external work. It permits
nondeterministic outputs across distinct calls, requires a durable intent
before invocation, and requires either stable-key deduplication/status lookup
or operation-specific idempotence/reconciliation. It also requires exact
input validation, charge bounds, and conditional progress.

P7 needs a named adapter history/transition contract to make these statements
provable:

1. Derive a stable key `K` from run identity, pinned operation identity, and
   the call occurrence. Derive a request fingerprint `Q` from the exact
   canonical input/request bytes, committed resume descriptor, and pinned
   operation/configuration identities. The exact tuples are authoritative;
   hashes require a separate collision-free contract.
2. The committed intent fixes `(K,Q)` before any external effect. A retry or
   query with the same `K,Q` joins that logical operation. Reuse of `K` with
   any different `Q` is a key conflict and is rejected, never a new call.
3. Repeated or overlapping deliveries for one key preserve one logical
   operation and converge on one exact terminal tuple. The tuple includes
   reply bytes, evidence, charge, and artifact references. Once terminal, all
   retries return that tuple; distinct keys remain nondeterministic even when
   their requests are identical.
4. An adapter-specific effect law states that repeated physical deliveries
   are observationally equivalent to at most one authorized abstract effect,
   and reconciliation can determine whether/which effect occurred. Dedup or
   reconciliation state must survive adapter restart, or an equivalent
   durable remote status source must exist. A non-idempotent effect with a
   lost-reply ambiguity and no reconciliation is inadmissible.
5. The pinned validator checks typed output at the replayed exact input.
   Separately, a P7 receipt witness binds evidence, charge, and artifacts to
   `(K,Q)` and the adapter's effect law; validation of output bytes alone
   cannot prove physical-effect or charge truth. P7 requires charge to fit
   the reserved maximum; P8 proves single ledger settlement; P9 proves backing
   artifact durability when claimed.

## Concrete counterexamples

- A transfer executes, its reply is lost, and a service that ignores the
  caller's stable key performs the transfer again on blind retry.
- Recovery supplies changed request or resume bytes for the same occurrence;
  the adapter must reject the key conflict rather than return a cached result.
- Adapter restart loses its dedup map and no remote status source can reveal
  whether an effect occurred.
- Two overlapping retries for one key return individually valid but distinct
  reply/charge/evidence/artifact tuples; one key must not admit this race.
- Two runs or operation configurations accidentally share a remote key;
  key scope and request fingerprint must prevent aliasing.

The refinement is P7's proof boundary. P15 proves controller dispatch and
outcome-commit safety; P3 enforces one structural outcome; P8 proves ledger
settlement once; P10/P16 carry the committed result through recovery.
