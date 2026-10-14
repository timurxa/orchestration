# S2-06 store-boundary addendum

**Scope:** read-only check of patched `append_authorized`, commit/ack/crash semantics, `RunStarted` bootstrap, and P10. No F* or tests.

## Findings

**Target:** spec now clearly distinguishes append linearization/commit from acknowledgement. `AppendTransition` makes matching-prefix append change exactly `J` to `J ++ [e]`; stale prefix leaves storage unchanged. P10 defines cuts by append commit point, so cut recovers old or new prefix independent of acknowledgement. `CommittedUnacked` blocks a second append until coordinator reloads same committed prefix and clears the attempt. `RunStarted` is authorized from `initial_state`; it is the bootstrap event, with empty journal as valid unstarted state. Crash before start commit leaves empty journal; after commit, persisted event is sole source of input.

**Established:** these are normative targets/contracts, not implementation proofs. P10 and concrete append refinement remain future obligations; no claim that physical store meets these laws.

## Remaining cut ambiguity: append may finish after controller dies

The small-step text says crash clears append slot and reloads latest prefix “at any step boundary … during append.” It does not explicitly say what happens to a write already submitted to storage but whose linearization point has not occurred at process exit. If that abandoned operation can still linearize after restart has loaded old prefix, then restarted controller temporarily holds `S = replay(J_old)` while durable head has advanced to `J_old ++ [e]`. Its next append will be stale and can safely reject, but P15’s invariant that controller state matches latest committed prefix is false until refresh; it could also claim work from stale frontier meanwhile. Commit fencing prevents stale candidate visibility, yet the claimed per-step source-of-truth invariant needs a rule.

Minimal closure: define append call as cancellation/settlement-safe across owner death, or require new coordinator to fence/drain old append attempts before loading and taking steps. Alternatively define the restarted controller’s authoritative state as the prefix at its load linearization, allow it to be temporarily behind, and require re-load/replay before every action authorization/append plus current-head gating before adapter dispatch. Then weaken “latest prefix” invariant to the exact loaded prefix until refresh. P10 must order the load and any abandoned append commit in one journaler history. A crash cut must not imply in-flight request is canceled unless store contract proves cancellation.

Counter-schedule: controller A submits append for `e` at head `J`; A exits before reply and before `e` linearizes. Controller B loads `J`, then old storage request for A linearizes to `J+[e]`. B still holds state `replay(J)` and may form another candidate from that state. CAS rejects B’s stale write, so no fork; however the current P15 state equation is violated between A’s late commit and B’s reload. If B can dispatch an external operation based on stale frontier before append validation, intent-before-dispatch could also be violated. Require durable `CallIntent` reread before any submit, as existing text says, and close the more general stale-state action boundary.

If append operations are indivisible abstract steps and a crash is ordered strictly before or after their commit step, there is no ambiguous “commit after recovery load” in the abstract machine. State this explicitly as the abstract schedule rule, then make P13 prove concrete refinement (including abandoned I/O behavior).

## RunStarted source-of-truth boundary

Per-journal bootstrap semantics are coherent: fixed request `R` parameterizes `ControllerStep_R`; before commit request is caller-owned and nondurable; after commit replayed `RunStarted` supplies root input/graph/plan/budget. A crash before commit can retry; after commit must ignore request. P11 correctly excludes empty unstarted state from no-stuck.

Two caller/store premises still need explicit owner:

1. **Retry equality:** “caller may submit the request again” means same `StartRequest` for the same attempted run. If caller resubmits changed input/budget/entrypoint under same run identity while journal remains empty, either this is a new allowed bootstrap choice or must be rejected by an idempotency binding. The current per-trace parameter `R` fixes request within one abstract trace, but restart API contract should say equality/caller responsibility.
2. **Global run-identity uniqueness:** expected-head CAS on one journal prevents two `RunStarted` events in that journal. It cannot prevent two separate empty stores from bootstrapping the same `RunIdentity`. Since call keys/occurrences derive from run identity, cross-store duplicate identity can collide in shared adapter key namespace. The stated uniqueness requirement needs a system-level allocator/registry or an explicit unique-ID premise enforced by caller/store. A per-journal append fence is insufficient.

A useful bootstrap law is: for one logical run key, all retries/concurrent starts map to one journal/store; start event commits at most once; after any successful/possibly committed attempt, reload decides outcome before another request is accepted. For distinct stores, allocator guarantees distinct run identities in every live/recoverable namespace.

## Conclusion

Patched prefix/commit/ack equations remove prior ambiguity about what “acknowledged” means. Remaining boundary is abandoned append I/O relative to restart load, plus bootstrap retry identity and cross-store run-ID uniqueness. These do not undermine per-journal CAS; they delimit P15’s latest-state invariant and the P13/P10 service contracts needed to claim it.
