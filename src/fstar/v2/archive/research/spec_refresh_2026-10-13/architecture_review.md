# Architecture review: serial journaler, parallel execution

## Verdict

Architecture sound if journal is sole authority and every concurrent completion is revalidated against latest committed head. Serial append is enough for safety; it does not itself prevent duplicate dispatch, preserve external-effect semantics, or prove fair progress. Main gap: spec has event/store contracts and broad concurrency targets, but no explicit in-flight ownership/resumption transition system tying volatile workers and adapter calls to serialized journal events.

Strongest objection: `CallIntent` is durable handoff, while retries/recovery can dispatch same intent more than once physically. “One logical outcome” is insufficient unless adapter contract says same stable key resumes/queries one logical operation and prevents or contains duplicate effects. A non-idempotent adapter that performs effect, loses response, then repeats effect after recovery is a counterexample. Exclude such adapters or require operation-specific deduplication/query semantics.

## Required abstract contracts

### 1. One serial, linearizable journal head

- State always `replay(J)` for latest durable prefix `J`; append atomically changes `J` to `J ++ [e]`, or rejects with no change. `expected_head` is compare-and-append fencing, not a hint.
- Every event gets one sequence identity at commit. Event order is serialization order, not execution/completion order. Independent completions may produce different valid histories.
- Validate `enabled`, occurrence uniqueness, exact reconstructed input, indexed decoding, and semantic authorization against current head at commit. On stale-head rejection: reload/replay, reconstruct, reauthorize, retry. Never append an event authorized only against stale state.
- One process may own journaler; multi-process writers need same linearizable CAS/fencing. A per-process mutex is insufficient.

Evidence: `implementation_spec.md` §4.1 says expected head must equal current sequence and event must be legal at replayed head (lines 806–816); P13 append authorization is separate (891–899); store premises require serialization/fencing (1191–1193). Make atomic binding of P13 authorization to the CAS head explicit.

### 2. Claiming and executing ready occurrences

- Readiness uses committed graph plus committed outputs for only input-wire dependencies. Volatile results never enable dependents.
- A local/generator worker gets immutable claim `(run, occurrence, pinned identity, input value/fingerprint, allocation, observed head)`. A live scheduler grants at most one active claim per occurrence. Commit rechecks occurrence still pending and same reconstructed input/allocation. Stale claims are discarded/recomputed.
- Duplicate local/generator computation before commit is safe only because code/generator is pure/total and same pinned input/allocation yields same result. It is still waste, not exactly-once execution. After committed completion/graph, never dispatch/recompute as semantic work.
- Bounded concurrency means finite active set plus fair admission/retirement. Do not wait for lowest key or earliest dispatch to finish; any completed independent action may append next.

Evidence: spec allows independent ready nodes concurrently (implementation_spec.md:617–618), says committed results are absorbing and pre-commit recomputation allowed (around 927–935), and key theorem note identifies missing `ReadyInput` agreement between sparse committed-input reconstruction and full `PortEnv` evaluator (key_correctness_theorems.md:191–230). Require lemma: if wire dependencies are committed, all completion extensions agreeing on those ports evaluate same typed input.

### 3. External calls with out-of-order responses

- For each adapter occurrence, append exactly one `CallIntent` before first dispatch. Intent key is stable occurrence key; adapter receives identical pinned operation, canonical request, reconstructed input, and resume data on every retry/recovery.
- Adapter may hold multiple distinct intents concurrently. Response carries key; accept/validate for that key only. Any outcome can be serialized next, regardless of intent order or request start order. No head-of-line wait on another request.
- `CallOutcome(k)` legal iff exactly one committed intent for `k`, no outcome yet, response correlated to it, validator accepts at exact input, charge within reserved maximum, artifacts durable. It settles only `k`; duplicate, cross-key, early, and over-charge outcomes reject.
- Recovery replays pending intents and resumes each same logical call. Adapter contract must define effect-safe at-least-once dispatch: stable-key deduplication, status lookup, or operation-specific idempotence/reconciliation. It must guarantee one logical terminal result/evidence/charge and eventual availability under liveness premises. “Same intent” without this does not control repeated side effects.
- Outcome bytes/results may arrive in any order; they stay volatile until authorized append. Crash before append resumes intent; crash after commit reuses outcome and does not redispatch.

Evidence: event definitions require stable occurrence call key and same intent/request/input across recovery (implementation_spec.md:851–862); P7 asks resumable intent semantics, effect safety, correlation, eventual outcome (1204–1206); key note already separates logical result from volatile callback. Tighten adapter liveness/effect contract to state retry behavior and ambiguity after lost response.

### 4. Dynamic graph generation

- Generator input and allocation are fixed by committed predecessors and occurrence ledger. Pure total generation can run before commit and repeat after a crash.
- Commit one `GraphCommitted` event containing exact canonical result and exact occurrence-lifted allocation plan; atomically validate generator result, graph typing/DAG, allocation split, and parent still unexpanded. Children become visible only after commit.
- Child occurrence IDs must derive deterministically from committed graph-introduction identity plus local key (or another injective stable path), never from volatile task order. Concurrent independent generator commit order may change graph occurrence labels, not wiring or provenance.
- After commit, recovery uses exact graph bytes; no regeneration/replacement. Duplicate graph commits reject.

Evidence: implementation_spec.md:832–844, 911–925; graph occurrence is introduced by `GraphCommitted` event (864–871); allocation plans have canonical key alignment and injective lift (630–649). Add explicit commit-time duplicate/unexpanded check and stable identity rule if not already embodied in occurrence definition.

### 5. Concurrent budget allocation

- Allocate charge/fuel statically per occurrence at `RunStarted` / each `GraphCommitted`; workers cannot reserve by racing on a shared free counter. Distinct active tasks consume only their disjoint committed allocations.
- Generator commit replaces only that generator's allocation with child plan; total child allocations fit it. Intent moves exactly occurrence maximum from allocated to reserved. Outcome settles once; `q <= max`; remainder returns to free. Replay derives maps; no worker-local settlement is authoritative.
- Prove invariant after every serialized permutation of independent `GraphCommitted`, `CallIntent`, `CallOutcome`, and local completion. Child occurrence key sets disjoint; no plan can double-assign key. In-flight results do not affect ledgers until event commit.

Evidence: detailed conservation and occurrence-local equations in implementation_spec.md:1068 onward, P8 in theorem table (P8 around 1174). Concurrency proof should quantify over arbitrary legal event order, not only sequential `next` behavior.

### 6. Crash cuts and visibility

Required cuts, each recovers exact committed prefix and no volatile result:

| Cut | Required recovery behavior |
|---|---|
| Local/generator computes, before result/graph append | Drop volatile result; pure work may rerun. |
| `GraphCommitted` commit before ack | Reload; use exact graph/plan; never recommit or regenerate. |
| `CallIntent` commit before dispatch | Resume that same intent. |
| External effect/request in flight, before outcome append | Query/deduplicate/reconcile same key; no new logical call. |
| Outcome validated/artifacts durable, before append | Resume same intent or recover same terminal adapter outcome; artifact may be orphaned but unreferenced. |
| Outcome/completion commit before ack | Reload; reuse committed value; do not dispatch or expose twice. |
| Stale worker response after recovery/another commit | Revalidate against recovered head; reject if occurrence already settled or input/identity/allocation differs. |
| Append commit racing crash | Store exposes old or new whole prefix by linearization point. |

Evidence: every-cut store theorem covers prefixes and uncertain acknowledgement (implementation_spec.md:961–1024); artifact publish-before-reference and commit-before-use at 927–931; guide clarifies exactly-once journaled completion, not physical local execution, and external ambiguity (graph_and_recovery_guide.md:229–231). Include orphan artifact cleanup as operational policy, not safety theorem.

### 7. Progress under bounded concurrency

- `next(S)` can describe a canonical choice, but parallel semantics must expose a set/frontier of enabled actions and all fair schedules; otherwise bounded worker concurrency/out-of-order response behavior is not represented.
- Journaler fairness: every authorized ready event eventually gets append opportunity, stale CAS retries do not starve. Scheduler fairness: every ready occurrence eventually claimed; finite pool slots recycled. Adapter returns by key independently; a slow request cannot block unrelated ready outcomes.
- Termination premises cover local/generator/validator termination, adapter eventual terminal outcome per intent, append availability, fair dispatcher, and finitely many crashes. Safety does not imply these liveness claims.

Evidence: P11/P14 and progress assumptions (implementation_spec.md:1159–1206); key note's target contract says outcomes can append in arbitrary completion order but could spell out no head-of-line blocking (key_correctness_theorems.md:232–250).

## Counterexamples to rule out

1. **Duplicate external dispatch:** intent committed; worker A performs payment; response lost; recovery resubmits; payment performed twice. Fix: same-key dedupe/query or reject operation.
2. **Outcome swap:** responses for `k1`,`k2` arrive reversed; runner writes response bytes to whichever worker slot finishes first. Typed bytes can decode correctly yet attach wrong evidence/charge. Require key-based correlation and validation at exact input.
3. **Stale authorization:** worker verifies completion against `J_n`; another append advances head; worker submits stale event. CAS rejects by expected head; caller must reload/re-authorize, not blindly retry with new head.
4. **Duplicate occurrence claim:** two scheduler threads see same ready node and both dispatch. Local result may be same, but duplicate computation/accounting and especially external effects violate one-dispatch assumptions. Enforce live claim plus committed absorbing checks; journal remains ultimate authority.
5. **Child before graph commit:** generator worker exposes in-memory child list before `GraphCommitted`; child completion append then crashes. Replay has no child graph. Prohibit dispatch/authorization until commit acknowledged or recovered as committed.
6. **Budget race:** two generators both read same free budget and allocate it to children. Per-occurrence committed allocations and single-threaded ledger transition prevent this; do not derive child plans from mutable live free budget.
7. **Incomplete environment:** evaluator reads entire `PortEnv`; scheduler only has outputs on dependency subset. Passing partial map as full environment is ill-typed or reads absent unrelated port. Define partial evaluator/readiness-extension lemma.
8. **Completion-order DAG edges:** treating append sequence as causal edge makes independent out-of-order outcomes appear dependent; treating worker launch order as stable vertex ID makes resumed/reordered runs change IDs. Keep event sequence, occurrence identity, and causal/data edges distinct.

## Recommendations for spec refresh

### `key_correctness_theorems.md` / `implementation_spec.md`

Add named targets/contracts:

- `dispatch_claims_unique_and_head_revalidated`: one live local/generator claim per occurrence; per-result immutable input/identity/allocation; append CAS and semantic authorization bound to current replay head; stale-result recovery rule.
- `adapter_retry_effect_safety`: stable call key; same logical request across retries; dedup/query/idempotence premise; response correlation; exactly-once *logical settlement* distinguished from physical delivery/effect.
- `concurrent_permutation_safety`: any fair legal serialization of independent completions preserves WF, dependent types, allocation ledgers, uniqueness, and absorbing outcomes.
- `partial_input_evaluation_agreement`: dependency-local reconstruction is defined exactly when ready and equals full typed evaluator under every compatible completion extension.
- `bounded_frontier_liveness`: fair slot assignment, append fairness, per-key adapter progress, and no head-of-line blocking.

Make append operation accept proof/claim scoped to `(head, occurrence, input, allocation)` or show equivalent refinement. Clarify `next` versus enabled-action frontier; single `next` cannot alone model simultaneously in-flight work.

### `src/docs/vecherinka_tui_dag_spec.md`

State that event sequence and DAG edges are different relations: append/completion order is not causality. Preserve distinct occurrence IDs for repeated work; assign stable IDs when occurrence/graph commit becomes durable, not when parallel task finishes. Keep edges for actual causal/data/control relations only; do not draw edges merely because one event appended earlier. Include per-occurrence durable `CallIntent`, pending/in-flight adapter state, completion commit sequence, and recovery reuse in detail pane if source schema supports them. If this TUI DAG documents only current Vecherinka runtime rather than v2, state that boundary explicitly; its `work_id` creation-order rule (lines 36–49) should not be reused as v2 journal sequence semantics.

## Evidence boundary

This is a specification review, not proof status. Current `WorkflowV2.Journal.fst` declares event/action vocabulary then explicitly says V2-04 will define replay and that vocabulary grants no transition authority (lines 95–109). Treat replay, adapter, store, and runner claims as targets/premises until discharged. The key-correctness note already contains the right core concurrency shape; review asks to make ownership, retry-effect safety, stale-head reauthorization, and fairness explicit.
