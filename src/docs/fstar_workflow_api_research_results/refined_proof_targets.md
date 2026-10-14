# Refined proof targets

**Scope.** Tighten durability theorem sketches using `proof_model_critique.md` and `adversarial_review.md`. These are proposed definitions and theorem targets, not claims established by current source. No implementation or test claims.

## 1. Machine state and concrete protocol substates

Model a run configuration as `C = (D,V,B,A,Q)`: `D` durable journal/database bytes; `V` volatile runner state; `B` backend state; `A` artifact-store state; `Q` scheduler/worker state. A crash drops `V,Q` except independently durable worker/backend state. Transitions split host calls at their actual persistence and effect boundaries. A trace records all transitions and the crash may occur between any adjacent transitions.

For each occurrence `k=(run,path)` and attempt `a`, use these projected states (the projection is derived from append-only journal evidence; it never deletes history):

```text
Absent
IntentCommitted(a,key,requestDigest,maxCharge,pinnedIds)
DispatchMayHaveOccurred(a,key)          // durable before entering adapter
CallEntered(a,key)                       // volatile fact; crash loses it
BackendMayHaveApplied(a,key,B')          // modeled backend transition
ReplyReceived(a,key,raw)                  // volatile until receipt persistence
ReplyReceiptCommitted(a,key,rawDigest)    // evidence only, not success
OutputValidated(a,valueDigest,proofId)
ArtifactBytesStaged(id,digest)
ArtifactBytesDurable(id,digest)
ManifestValidated(manifestDigest,refs)
CompletionCommitted(a,valueDigest,proofId,manifestDigest,charge)
Consumed(k,valueDigest)
Unknown(a,reason)                         // dispatch-quiescent projection
```

`IntentCommitted` and all later durable states are defined by concrete committed records, not by successful in-memory functions. `DispatchMayHaveOccurred` is committed before adapter entry, so recovery treats that attempt as possibly sent even if call never began. `BackendMayHaveApplied` is backend state, not local journal knowledge. `ReplyReceived` may be lost at crash; `ReplyReceiptCommitted` preserves raw response digest/bytes but does not certify it. Validation and artifact states are separate. Blob bytes are persisted and digest-checked before a manifest can name them. `CompletionCommitted` is one database linearization point containing validated output/evidence identifiers, all durable artifact references, terminal outcome, and one budget settlement. If stores cannot share transaction, replace this point with an explicit finalize protocol and prove all its intermediate states safe; do not assume a multi-store atomic primitive.

Concrete cuts include before/after each record append; during snapshot encode, temporary write, file sync, rename, directory sync, SQLite transaction/commit; before/during/after adapter entry; backend effect before reply; reply before receipt commit; response decode before semantic validation; validation before artifact write; partial blob write; bytes durable before manifest; manifest durable before terminal commit; terminal commit before volatile projection; and before/after downstream consumption. Each host primitive must map every cut to old state, new state, or explicit uncertain state under a narrow storage/OS contract. Tests cover selected cuts; refinement proof must cover all modeled outcomes.

`CompletionCommitted` means bytes/records in `D,A` satisfy a mechanically checked structural predicate: record links occurrence, pinned identities, output digest, evidence/checker version, manifest digest, and terminal settlement; every referenced byte object is present and digest-consistent under the storage contract. It does **not** mean runtime will recover it; that is a theorem to prove from storage refinement. This avoids defining recoverability into the premise.

## 2. Trace observations and fan equivalence

Raw execution traces are labeled transition sequences. `Obs` removes internal bookkeeping and restart labels but retains per-occurrence input/output/evidence, every visible external effect with attempt/key, durable artifact bytes/provenance, budget ledger events, and failure/unknown outcomes.

For sequential workflows, observation equality preserves effect order. For `fan(left,right)`, pairing remains ordered `(leftResult,rightResult)`, but ready branches may execute concurrently. Define `hb` as transitive causal order: within each branch, workflow data dependencies, shared-resource conflicts, and explicit scheduler/adapter ordering. Two finite effect traces are equivalent iff they induce equal per-occurrence outcomes and equal labeled effect partially ordered sets modulo permutation of adjacent independent events. Independence must be justified by disjoint capabilities/resources and no cross-branch data/control dependency; absent such proof, preserve order. This is Mazurkiewicz-trace equivalence, not arbitrary sorting. Artifact and budget events remain associated with their producer/attempt. If deterministic scheduler order is selected instead, the equivalence theorem may use exact sequence equality, but must state and prove that scheduler policy.

## 3. Strict memoized no-reinvoke and weaker pure recompute

Let `Pinned(W,run)` bind actual content/build identities for workflow code, callbacks, validators, adapters, codecs, dependencies, and schemas (or an explicit trusted immutable registry assumption). Let `ReplayValid(D)` mean replay yields the journal projection; this alone does not authenticate `D` or prevent rollback/tampering.

### P1. Memoized completion no-reinvoke

```text
Theorem MemoizedCompletionNoReinvoke:
  forall run,W,x,k,a,w,D,V,B,A,t.
    Pinned(W,run) /\ ReplayValid(D) /\
    CompletionCommitted(D,A,k,a,w) /\
    ResumeStarts((D,V,B,A,Q),W,x,t)
    ==>
      count(t, InvokeLocalBody(k)) = 0 /\
      count(t, DispatchFreshAttempt(k)) = 0 /\
      (forall consume(k,w'), UsesCheckedDecode(w,w')).
```

`InvokeLocalBody` excludes reducer lookup, decoding, and a separately identified sound checker; it includes calling the node’s authored function. `DispatchFreshAttempt` excludes evidence-driven reconciliation and same-key idempotent transport needed to resolve a prior incomplete attempt; a completed attempt permits neither. The interpreter rule must consult immutable completion record before body/adapter branch, decode and re-establish evidence, then return stored value. Prove that rule by induction on resume evaluation, with completion-table uniqueness/terminal immutability. Then prove extracted runner simulates the rule. Do not assume “resume short-circuits”; that is the central lemma.

Premises say a valid completion record exists at resume start. They do not assume it is recoverable, validated by this runtime, or correctly written. `StorageRefines` must prove committed records survive allowed crashes without fabrication/tampering; `Pinned` prevents changed code from reinterpreting the same record. Strict no-reinvoke applies only to memoized occurrences.

### P2. Pure recomputation safety

For an incomplete local node whose code has a proved pure, total semantic model and whose extracted implementation refines that model:

```text
Incomplete(k) /\ PureRefinement(k) /\ ResumeTrace(t)
 ==> count(t, InvokeLocalBody(k)) may be positive
     /\ count(t, ExternalEffect(k)) = 0.
```

This permits recomputation; it is not “no rerun.” F* `Tot` alone does not prove extraction has no host effects. If the body itself is memoized, P1 is the relevant theorem.

## 4. Backend state and recovery theorems

Do not compare executions using an unkeyed phrase like “same future replies.” Adapter results depend on backend state and effect history. Define `R_B(B1,B2,H)` as relation between backend states after matching visible history `H`. Adapter contract supplies either (a) a simulation/bisimulation: related states, same keyed request `(run,k,a,opDigest,requestDigest)`, and same allowed nondeterministic choice produce correlated transitions/results and related successor states; or (b) only safety facts about key deduplication, authenticated reconciliation, and no fabricated claims.

### P3. Recovery prefix safety (base guarantee)

Let `e` be a finite concrete execution, `c` any concrete crash cut, and `e'` any recovery continuation from durable prefix at `c` with actual backend state `B_c`. Under storage refinement, pinned-code compatibility, reducer correctness, adapter safety, and valid evidence checks:

```text
Theorem RecoveryPrefixSafety:
  Reach(e) /\ CrashCut(e,c) /\ Recover(DurableBytes(c)) = r
  ==>
    every effect in e' is allowed by the keyed adapter protocol from B_c
    /\ no committed consumer reads invalid or missing output
    /\ no attempt settles budget twice
    /\ no unresolved attempt is reported Succeeded or given a fresh key
    /\ committed observations in e' preserve observations already committed before c
    /\ uncertain possibly-applied effects may project only as Unknown until evidence.
```

Effect safety premise means: stable key exactly binds run, occurrence, attempt, operation content/config identity, and canonical request digest; backend deduplicates same-key calls **or** reconciliation returns authenticated truthful `Applied(result)`/`NotApplied`; result is correlated to that key. If neither holds, recovery can only preserve `Unknown` and refrain from unsafe fresh-key retry. Prefix safety concerns actual `B_c`; it does not pretend backend state resets or provide remote exactly-once.

### P4. Strong restart equivalence (optional, stronger)

For executions `e1,e2` cut at corresponding states `(D1,V1,B1,A1)` and `(D2,V2,B2,A2)`, assume committed local/artifact projections equal, `R_B(B1,B2,H)`, pinned implementations equal, and adapter plus scheduler transitions satisfy weak bisimulation modulo fan trace equivalence above. Then resumed observations are equivalent to uninterrupted continuation observations:

```text
RelatedAtCut(e1,e2) /\ StorageRefines /\ BackendBisim /\ SchedulerBisim
 ==> Obs(Resume(e1)) ~= Obs(Continue(e2)).
```

This is conditional semantic equivalence, not a theorem from replay alone. Without backend bisimulation/deduplication, retain P3 only. Same raw reply list is not a substitute for `R_B`: it can force replies inconsistent with pre-cut effects and hide duplicate-dispatch behavior.

## 5. Unknown: append-only evidence, dispatch-quiescent

Store append-only history `H_k,a`; define projection `status(H)` separately. `Unknown(a)` means outcome/effect unresolved and scheduler may not automatically issue `Start`/fresh-key `Dispatch` for `(k,a)`. It retains attempt reservation. It is **dispatch-quiescent**, not terminally absorbing: explicit authorized reconciliation may append request/reply evidence, and a verified transition may project `Unknown` to `Applied/Failed/NotApplied`. Historical Unknown event remains in `H`.

Permitted post-Unknown transitions:

- append a uniquely correlated reconciliation request/evidence event (manual or explicitly budgeted bounded policy);
- refine projection to terminal result only from authenticated result/effect evidence and validated output;
- refine to authenticated `NotApplied`, release attempt reservation, then permit new `a+1` with a fresh intent;
- remain Unknown if evidence unavailable or contradictory.

Forbidden: replace/erase Unknown history; automatically poll forever; issue a fresh attempt while prior outcome unresolved; infer no effect from timeout/process death; settle/refund reservation without evidence. Repeated same-key retransmission for the same attempt is permitted only if backend contract makes it idempotent/reconciling and it consumes no second reservation. A budgeted reconciliation action is a separate chargeable event if policy accounts for its cost.

## 6. Attempt-aware budget invariant

Let `Latest(k)` be greatest prepared attempt for occurrence `k`. `Open(k,a)` iff `a=Latest(k)` and its projected state is `IntentCommitted`, `DispatchMayHaveOccurred`, `Pending`, or `Unknown`; terminal `NotApplied` is settled/released, other terminal states are settled once. Same-key retries/reconciliation do not create attempts. Historical attempts remain in journal but are excluded from outstanding reserve.

```text
Theorem AttemptBudgetInvariant, for every reachable committed S:
  valid(S.budget)
  /\ S.budget.reserved = Σ_{k,a | Open(k,a)} reservation(k,a)
  /\ S.budget.spent = Σ_{k,a | SettledCharge(k,a)} charge(k,a)
  /\ each (k,a) occurs at most once in Open and at most once in SettledCharge
  /\ S.budget.spent + S.budget.reserved <= S.budget.limit.
```

Admission linearizes with intent+reservation commit against latest serialized state. A success settlement event carries one authenticated charge `c <= maxCharge`; reducer consumes reservation and records charge exactly once. Unknown retains reservation. Authenticated NotApplied releases it and records zero operation charge; later attempt gets a new reservation. Failed/cancelled settlement policy must say whether ledger books actual charge, known charge, or full reserved estimate. If full reservation is charged by policy, call it conservative kernel accounting, not measured provider spend. Same-key retry never double-reserves/double-settles. An overcharge response records a violation/quarantine outcome; it cannot pass ordinary verified success settlement. The invariant bounds ledger accounting; provider cost bound additionally assumes truthful authenticated charge and provider respects maximum.

## 7. Nonvacuous progress properties

First prove **local progress to quiescence**, not remote success. Start condition must exclude an already-Unknown state:

```text
Theorem AttemptQuiesces:
  forall k,a. Durable(DispatchMayHaveOccurred(k,a))
  /\ AttemptUnresolved(k,a)
  /\ StableRunInterval /\ FairScheduler /\ BoundedKillableAdapter
  /\ FiniteStoreCommit /\ AdvancingDeadline /\ FiniteLocalValidation
  ==> eventually Durable(Terminal(k,a) or Unknown(k,a)).
```

Exact premises:

1. **Stable interval:** after finitely many crashes, one process interval remains long enough to perform bounded protocol work; arbitrary infinite crash loops defeat liveness.
2. **Scheduler fairness:** every continuously enabled journal/reconcile/timeout action eventually runs; independent ready work is not starved by a pending branch.
3. **Adapter boundedness:** each call has deadline and returns or is isolated in a process the watchdog can terminate within bound. A watchdog around uninterruptible FFI/thread is insufficient. Kill/process semantics and late-worker fencing are trusted/runtime premises.
4. **Store liveness:** each enabled append/transaction eventually commits or returns a classified failure; if storage permanently unavailable, theorem conclusion is explicit unavailable/failure only if that state can itself be durably committed. Otherwise no durable-quiescence conclusion.
5. **Deadline advancement:** use persisted finite poll/retry count or a clock with explicit monotonicity/restart semantics. Expiry handler is fair and can commit Unknown. Deadline alone does not bound a blocked call.
6. **Bounded local work:** decode, validation/checker, digest, and reducer terminate within their declared model. Expensive checker must be scheduled under its own progress/resource contract.

Remote terminal success requires additional backend eventual-response assumption plus fair reconciliation and valid result. Without it, terminal-or-Unknown is strongest liveness. `Unknown` may remain indefinitely if reconciliation is unavailable. If intent was committed but `DispatchMayHaveOccurred` absent, scheduler either dispatches or safely records a conservative Unknown; no claim of backend result follows.

Fan fairness is separate: each continuously ready branch is eventually scheduled under weak fairness. Pair completion requires both branch values; one branch being pending must not erase or block the other branch's local progress.

## 8. Proof layering and source boundary

1. **F* functional theorems:** dependent composition/evidence; reducer transitions; append-only Unknown projection; attempt-aware ledger; memo-table lookup-before-call; completion uniqueness.
2. **Abstract machine theorem:** induction over every substate/cut proves P1–P4 and progress under named premises.
3. **Extracted runner refinement:** prove OCaml runner, codecs, queue, and process protocol simulate machine, especially fresh-dispatch gating and completion lookup. Current source lacks this bridge.
4. **Host contracts:** SQLite/file commit and recovery, fsync/rename outcomes, blob durability/digest, OS process kill/watchdog, clock, backend idempotency/authenticity/charges. State as narrow assumptions or verify separately; tests do not replace theorem.
5. **Selected tests:** exercise crash matrix and scripted backend states, including both indistinguishable worlds (backend effect applied vs not applied), duplicate/late replies, all artifact commit cuts, Unknown reconciliation, and competing attempt reservations.

Current source boundary remains: `WorkflowCore.pure` invokes callback during evaluation and `resume_evaluate` reevaluates root (`WorkflowCore.fst:464-481,855-864`); no memoized local completion table exists. Reducer replay/status/budget helpers are model facts, not runner refinement (`681-864`). `WorkflowStore` encodes journal model, not SQLite/fsync guarantees (`327-339`). `Unknown`-to-terminal is modeled as status replacement projection today; refined append-only evidence protocol is a design target. No source/build/test conclusion beyond this audit.

## 9. Required next proof work

1. Define journal events and reducer projection for every substate above, including dispatch intent, raw receipt, validator evidence, artifact staging/manifest, completion, settlement, and reconciliation evidence.
2. Prove reducer safety/attempt ledger invariants by induction over events, with all duplicates, late/conflicting events, and crashes.
3. State scheduler/adapter host semantics as transition contracts; prove bounded attempt-to-Unknown under exact fairness/watchdog/store premises.
4. Prove P1 from abstract evaluator rules, then connect `Runner.ml` resume and dispatch paths by simulation. Do not infer P1 from deterministic `Tot` callbacks.
5. For stronger P4, define backend relation and prove adapter simulation; otherwise retain prefix safety and explicit Unknown.

