# Durability proof semantics

**Purpose.** Formalize strongest meaningful workflow guarantees and distinguish F* model theorems from store, adapter, and OS assumptions. This is a theorem-design note, not a claim that current prototype proves them. Proof length is not a design penalty.

## 1. State and trace model

Let `W` be a workflow manifest pinned to implementation, operation, adapter, codec, and schema versions; `x:I` immutable root input; `k=(run_id,path)` stable node occurrence; `a:nat` attempt identity. Let `S` be abstract committed workflow state, `V` volatile process state, `B` backend state/history, and `A` durable artifact bytes/manifests. A committed state contains a contiguous event prefix, root input, pinned plan, per-occurrence decisions/completions, artifact references, and budget ledger. `Recover` decodes only committed bytes and reconstructs `S`; corrupt or incompatible data yields explicit invalid/unavailable state, never invented success.

Use labeled transitions `S,V,B,A --e--> S',V',B',A'` where labels include `LocalInvoke(k)`, `IntentCommit(k,a,r)`, `AdapterCall(k,a,request)`, `Effect(k,a)`, `AdapterReply(k,a,r)`, `ArtifactCommit(id,digest)`, `CompletionCommit(k,w)`, `Consume(k,w)`, and `Crash/Restart`. A crash drops `V` and preserves only storage-contract-committed bytes plus backend effects. A cut is any finite prefix boundary, including between any two labels. `DurableSuccess(S,k,w)` means one committed completion atomically names canonical validated result `w`, its artifact manifest/references, provenance, and terminal-success status; `w` decodes and re-establishes the declared contract.

`Obs(trace)` records final typed values and their established evidence, ordered externally visible effects, artifact bytes and provenance, kernel-accounted budget, and explicit failure/unknown outcomes. It ignores internal scheduler steps and restart markers. Trace equivalence `t1 ~= t2` means equality of these observations, including effect order and failures; liveness is a separate infinite-trace property.

An occurrence is complete only at `CompletionCommit`, not after in-memory return, process exit, adapter success reply, artifact staging, or a result-validation step alone. A durable value has type `Σ y:O(x). P(x,y)` or fixed carrier plus checked evidence. Raw response is never such a value.

## 2. Theorem sketches

These are candidate statements to encode and prove after API/runtime semantics are fixed. Quantification is universal over workflow plans, well-typed inputs, reachable valid states, finite traces/cuts, and code that meets stated contracts; no example-only quantification.

### T1. Dependent composition preserves values and evidence

For all `x:I`, let stage one return `(m,p):Σ m:M(x). P(x,m)`. Let static stage two accept `c:Ctx = Σ x:I. Σ m:M(x). P(x,m)` and return `(y,q):Σ y:N(root(c),mid(c),evidence(c)). Q(root(c),mid(c),evidence(c),y)`. Then:

```text
run(then_keep(f,g), x)
  = (m,p,y,q)
  where run(f,x)=(m,p), run(g,pack(x,m,p))=(y,q)
  and q : Q(x,m,p,y).
```

The equality is definitional or propositional per API choice; no cast, dynamic closure capture, or erased evidence reconstruction. Projecting public output may hide `m,p` only if result family retains them (for example `Σ m:M(x). N(x,m)`) or a proof establishes an output-only postcondition. For fixed-carrier `B,C`, composition returns `y:C` with `R(x,y) = exists m,p. P(x,m) /\ Q(x,m,p,y)`, retaining ghost witnesses or checking a serialized certificate. This theorem needs F* functions/contracts and typed context packing; persistence needs indexed codec soundness and rechecking evidence after decode. Current `workflow i o`, `then_flow`, `fork`, and `lift` are nondependent (`WorkflowCore.fst:459-549`), so T1 is not expressible in current workflow type.

### T2. Completed occurrence is not invoked after restore

For all pinned `W`, `x`, valid committed `S`, occurrence `k`, and every resumed trace `t`:

```text
DurableSuccess(S,k,w)
 /\ Resume(W,x,S) terminates or emits explicit unavailable/error
 ==> count(LocalInvoke(k), t)=0
     /\ count(Effect(k), t)=0
     /\ every Consume(k,w') uses decode_validate(w) with w' = decoded(w).
```

`decode_validate` must return `(y,proof)` satisfying `P(x,y)`, through proved checker/certificate verifier or named decoder trust assumption. The theorem requires completion lookup by stable occurrence and immutable plan/schema identity, durable output, and a resume interpreter that short-circuits before body/adapter dispatch. If a local node is pure and its output was not stored, weaker property is only `count(Effect(k),t)=0` under purity; the body may run again. Exact no-invocation does not follow from pure termination.

**Boundary:** Current `pure` calls `apply` on each evaluation and stores no result (`WorkflowCore.fst:464-481`). `resume_evaluate` re-evaluates root plan (`855-864`). `external` consumes stored `Succeeded` output after codec decode (`969-1030`), so it has a narrow prototype-level no-dispatch path for a matching success record, but no semantic validator, artifact-completion transaction, or authenticated output evidence. Current source cannot establish T2 generally.

### T3. Crash recovery preserves observation

For all reachable `W,x,S0`, finite execution prefix `t`, cut `c`, and same pinned future backend outcomes `β`:

```text
Reach(W,x,S0,t) /\ Cut(t,c)
 /\ StorageContract /\ CodeCompatibility /\ AdapterContract
 ==> Obs(Resume(Recover(lastCommitted(c)), β)) ~= Obs(Continue(t, β)).
```

This is strongest form and requires adapter effect deduplication/reconciliation; deterministic local nodes; persisted route/control choices or deterministic reconstruction; atomic completion including blobs; same future backend outcomes; and no incompatible migration. `Unknown` must agree on both traces when outcome cannot be resolved. If adapter contract only promises no unsafe duplicate and no invented success, replace `~=` with safety refinement: restored trace is a prefix/refinement preserving completed values and effects, may end `Unknown`, and never fabricates an effect/result. Do not claim equivalence when external effect could occur after last local commit but before reply.

Crash cuts must cover: before/after intent commit; before dispatch; during call; backend acceptance before reply; reply before validation; after validation; while staging bytes; bytes durable before manifest; manifest before terminal result; terminal result before downstream consume. `Recover` must either restore committed completion or produce explicit `Unknown`/unavailable. Staged orphan bytes are harmless; committed references to absent or corrupt bytes are forbidden by storage contract.

### T4. Adapter safety, bounded-call progress, and liveness split

Safety, for every attempted `(k,a)` and accepted reply `r`:

```text
AcceptReply(S,k,a,r) ==> Correlated(r,W,k,a,config,requestDigest)
 /\ (Verified(r,y,p) ==> P(input(k),y) / ValidEvidence(p))
 /\ Terminal(S,k,a) ==> every later state preserves same terminal outcome.
```

Effect safety: after any lost reply, next action is same-key deduplicated redelivery, reconciliation, authenticated `NotApplied` followed by permitted new attempt, or durable `Unknown`. It cannot blindly create a fresh key/effect. Authentication, provider idempotency, reconciliation truth, and semantic validity of external claims are adapter/checker contracts, not consequences of F* typing alone.

Progress claim, for each accepted attempt: assuming (i) scheduler weak fairness for continuously ready local actions, (ii) watchdog interrupts or returns every adapter call within persisted bound, (iii) store commits enabled events within finite time, and (iv) deadline/retry accounting advances under named clock assumption, attempt eventually reaches durable terminal state or durable quiescent `Unknown`. `Unknown` stops automatic dispatch/polling, retains reservation, and can be refined only by appended correlated reconciliation evidence. This theorem does not imply backend success. Eventual remote terminal success additionally assumes backend eventual response and adapter fairness. Fairness for unrelated ready nodes is separate scheduler theorem.

No unconditional progress theorem is true if scheduler never runs, store blocks forever, watchdog cannot interrupt, or adapter call diverges. No theorem can promise backend success without backend liveness.

### T5. Artifact integrity and completion atomicity

For each committed reference `r` in completion `k`, all restarts either recover exactly declared byte string `b` with matching digest/schema/provenance and validate `P` against it, or report explicit unavailable/corrupt state without exposing verified completion. For file-tree adapter, under filesystem contract:

```text
ValidTree(t) /\ Materialize(root,t)=Ok(paths)
 ==> confined(paths,root) /\ Read(paths)=t
Collect(root,contract)=Ok(t)
 ==> ValidTree(t) /\ paths(t) subset allowed(contract)
     /\ each byte string equals bytes from a confined regular file.
```

Proof needs path normalization/containment, symlink and race policy, regular-file checks, collision rejection, required/optional output rules, atomic durable bytes-before-reference ordering, and content verification on read. OS/filesystem behavior remains an assumption or separately verified host refinement. Metadata exclusions must be explicit. Temporary path or process handle is never durable artifact identity.

Current reducer validates basic blob bytes/tree shape and provenance parent IDs (`WorkflowCore.fst:646-668`), rejects `MaterializedFile` and `LiveCapability`, and appends `ArtifactSaved` independently of operation status (`762-768`). `artifact_record` has no content digest or atomic link to success (`370-379`). Current store state is journal encoding/replay, not external blob persistence (`WorkflowStore.fst:256-339`). Thus this is not yet artifact integrity/atomic completion proof.

### T6. Budget safety

For every reachable state `S`:

```text
valid(S.budget)
 /\ S.budget.reserved = Σ reservation(k,a) for in-flight or Unknown attempts
 /\ S.budget.spent + S.budget.reserved <= S.budget.limit.
```

Every intent reserves maximum charge against latest serialized state before dispatch. Terminal success settles only if authenticated `actual <= reservation`; failure/cancel settlement follows explicit policy; unknown retains reservation; refund requires authenticated definite nonapplication. Simultaneous admissions must linearize against one serialized state. This proves kernel ledger accounting only. Provider-cost bound requires adapter/backend to respect declared maximum and charge evidence authenticity. Overcharge cannot be silently clamped: record violation and refuse normal verified settlement.

**Current source fact:** `reserve`, settle functions and preservation lemma declarations exist (`WorkflowCore.fst:262-305`); `OperationPrepared` reserves, pending/unknown retain budget, success calls bounded settlement, failure/cancel consumes reservation, and confirmed `NotApplied` refunds (`681-761`). `settle_unknown` is identity. Replay-preservation lemma declarations are present (`889-945`). This does not prove provider spend; authentication of the nonempty `NotApplied` evidence string is absent. Duplicate event replay is idempotent only for exact same event bytes/sequence (`770-780`).

## 3. Reducer invariants and useful subsidiary theorems

1. **Replay determinism:** `replay(header,events)=Some S1` and same arguments imply same `S1`; appending accepted suffix equals replaying suffix from prefix state. Source has `replay_append_law` declaration (`WorkflowCore.fst:866-888`) and `WorkflowStore.decode_state` delegates to replay (`WorkflowStore.fst:331-337`).
2. **Event identity:** only next sequence applies; exact old event is no-op; conflicting duplicate/gap rejected (`WorkflowCore.fst:770-780`). Host must still ensure bytes truly committed and not torn/reordered.
3. **Terminal monotonicity:** accepted status changes: `Prepared -> Pending|Unknown|terminal`, `Pending -> Unknown|terminal`, `Unknown -> terminal`; terminal only permits identical status (`WorkflowCore.fst:719-748`). Equal status is a no-op. This model permits `Prepared -> Succeeded` and has no evidence field proving response correlation.
4. **Attempt progression:** first attempt is 0; new attempt after `NotApplied` increments previous attempt (`WorkflowCore.fst:698-718`). Reducer checks adapter ID equals capability and evidence string nonempty for NotApplied (`749-761`); it does not verify authenticity.
5. **Route persistence:** `so` persists selected return/child plus snapshot and checks manifest/input/version equality when restored (`WorkflowCore.fst:1033-1116`). `choose` is evaluated before persisted expansion. Determinism/effect-freedom of `choose` is not enforced by type; resume behavior after no commit can repeat its computation.
6. **Occurrence uniqueness:** path is `run_id + path segments` (`WorkflowCore.fst:237-260`). Sound uniqueness requires path construction compositionality and no two dynamic children sharing same child ID at same parent slot; host/run ID uniqueness also needed across runs.

## 4. What is theorem, assumption, source fact, or test

| Category | Claims / evidence |
|---|---|
| **Theorem sketch, not established** | T1–T6 above; model-to-extracted-runtime simulation; all-cut recovery; adapter safety; filesystem confinement; fairness/liveness. No implementation or extraction proof is inspected here. |
| **Current source facts** | Constant-family `workflow`; typed `code_ref`/codecs with encode-after-decode roundtrip law; local pure eval; sequential host-language evaluation for fork/lift; event reducer/replay; state re-encoding only when replay-valid; route expansion persisted; operation reservation/status logic; narrow external success decode. Sources and exact lines listed below. |
| **Source proof declarations, not verified here** | `Lemma` declarations include codec roundtrip, budget preservation, path/product slot facts, replay append and replay budget preservation. This read-only audit did not compile F*; declarations are not reported as build-verified proofs. |
| **Explicit assumptions needed** | Atomic/linearizable durable commits and crash consistency; durable bytes and digest integrity; pinned compatible code/codecs; faithful extracted OCaml/refinement; adapter correlation/authentication/idempotency/reconciliation; bounded calls/watchdog; scheduler/store progress; provider max-charge honesty; OS path/filesystem semantics; clock/deadline behavior. |
| **Tests can establish** | Selected encoding/reducer behavior and selected injected crash cuts; real CLI boundary examples; scripted adapter traces. Tests do not prove all cuts, all plans/inputs, actual provider cost, or OS refinement. Existing draft states this distinction (`fstar_workflow_api_next_research_spec_draft.md:211-279`). |

## 5. Countermodels and strongest objections

- **No-rerun without persisted local result:** local deterministic `f` computes `y`, process crashes before downstream use; resume calls `f` again. If “not rerun” means no body invocation, T2 false even when `f` pure. If only no duplicate effect is required, need an effect classification and proof that `f` is pure.
- **No exactly-once without backend support:** client sends payment; server commits; reply lost; client restarts. Two worlds have identical local durable state, one with payment and one without. Resend duplicates in first; skip loses operation in second. Only idempotency/reconciliation/authenticated nonapplication resolves; otherwise `Unknown` is strongest truthful result.
- **Crash equivalence without atomic completion:** artifact bytes persist, status does not; or status persists, artifact bytes do not. Recovery either repeats external effect or references absent output. Need one linearization point or staged protocol with repair proof.
- **Dependent proof cannot survive arbitrary decode:** serialized `n` may parse yet fail `n>x` or primality. Roundtrip on encoder-produced values does not establish soundness for arbitrary wire. Recompute proof/check certificate or trust named checker.
- **Budget bound without charge contract:** provider charges above max while reducer rejects settlement. Kernel ledger can remain valid while real spend exceeds limit. Cannot claim actual cost bound from reservation arithmetic.
- **Progress without fairness/bounds:** scheduler continually selects pending poll, store blocks, or adapter blocks forever. No terminal/Unknown checkpoint appears. Liveness must assume scheduler, watchdog and store progress.
- **Replay validity is not storage truth:** a forged but internally consistent journal replays; current `state_is_replay_valid` checks replay equality, not authentication, fsync, anti-rollback, or atomicity. Storage contract needed.
- **Stable operation name is not stable semantics:** same ID/version/config labels can point to changed binary, resolver, validator, or output codec. Pinning needs content/build identity or trusted registry compatibility policy; equality of strings alone is not proof of semantic sameness.
- **Artifact provenance strings are not cryptographic lineage:** valid parent IDs only establish references exist; they do not prove bytes descend from parent, producer effect, or claimed validator. Add digest/signature/certificate contracts if those claims matter.

## 6. Source provenance and exact boundaries

- `WorkflowCore.fst:5-21`: wire constructors; codec has roundtrip `decode(encode x)=Some x`, no general semantic decoder theorem.
- `WorkflowCore.fst:222-260`: manifest, static path segments, occurrence identity.
- `WorkflowCore.fst:262-305`: budget model and local preservation lemma declarations.
- `WorkflowCore.fst:318-428`: operation statuses, records, artifact record, journal state/context, unindexed `evaluation`.
- `WorkflowCore.fst:459-549`: `workflow i o`, `then_flow`, `fork`, `lift`; no dependent output/postcondition, result cache, or execution effect model.
- `WorkflowCore.fst:577-600`: ready-action predicate and lemma that pending reconcile does not block a later ready action; not a full scheduler fairness proof.
- `WorkflowCore.fst:646-668`, `681-780`: artifact/reducer checks, event transition rules, duplicate/gap rules.
- `WorkflowCore.fst:791-864`: recovered Prepared becomes Unknown; root header stores manifest/input/budget; resume verifies build/manifest/root codec tag and decodes root input before evaluating plan.
- `WorkflowCore.fst:866-945`: replay append/budget lemma declarations; not build-verified in this audit.
- `WorkflowCore.fst:945-1031`: `op_spec` and `external`; success is stored wire decoded via output codec; no raw/validated distinction or response validator; a match binds operation/capability/version/capture/request and codec tags/reservation, not adapter configuration fingerprint or request digest.
- `WorkflowCore.fst:1033-1116`: route chooser/resolver and persisted selection; resolver availability failures explicit.
- `WorkflowStore.fst:175-214`, `256-339`: operation/artifact/event encodings; state encoding is version-1 header plus event list and uses replay for decode; this pure model specifies no SQLite transaction/fsync behavior.
- Draft `fstar_workflow_api_next_research_spec_draft.md:5-29`, `83-129`, `139-169`, `197-260`: intended API, dependent composition, adapter obligations, file contracts, no-rerun/recovery/budget theorem targets.

## 7. Unresolved proof/interface questions

1. What exactly counts as a “local body invocation” for memoized pure nodes, and must every successful local node persist result to satisfy strict T2?
2. Does `Unknown` count as durable non-completion for public API, while retaining operation output only after validator and artifact commit?
3. Does completion atomically include downstream-consumable typed value, evidence/checker version, all artifacts, and terminal status? Define staged blob commit and repair states.
4. Is adapter reply authentication verified in F*, by a trusted host, or represented as an explicit assumption/certificate? Same for NotApplied evidence and provider charge.
5. What defines compatibility across code upgrades: content hash, build ID, registry signature, explicit migrations, or theorem-preserving version policy?
6. What state distinguishes pending adapter token from unknown/quiescent, and which transitions append evidence without replacing history?
7. Is event sequence enough for concurrent writes, or must store expose compare-and-append/CAS transaction theorem? How are two schedulers on one run excluded or reconciled?
8. What is clock semantics for deadlines under process restart, wall-clock skew, and unavailable clock? Prefer finite logical poll/retry budget if wall time not essential.
9. How are artifact digest, path policy, and validator proof encoded without treating cryptographic primitives/OS behavior as proven by F*?
10. Can `external` have partial/non-verified result type while preserving dependent input index, or should rejection/unknown be evaluator-level sum outside `O(x)`?

## 8. Proof dependency map and next inquiry

```text
dependent node contracts + indexed codecs
  -> typed local composition/evidence preservation (T1)
  -> canonical validated completion representation
  -> reducer invariants + atomic durable-store refinement
  -> strict no-rerun and all-cut recovery (T2/T3)
  -> adapter protocol correlation/idempotency/reconciliation
  -> effect safety + conditional terminal-or-Unknown progress (T4)
  -> artifact persistence/materialization refinement (T5)
  -> linearized reservation ledger + provider charge assumption (T6)
  -> extracted OCaml/host simulation theorem
```

**Next inquiry:** specify one executable abstract transition system for `intent -> dispatch -> accepted/pending -> validate/collect -> completion`, including `Unknown`, `NotApplied`, artifact staging, and crashes. Prove reducer invariants and T2/T3 against that model first. Then identify exact SQLite/OCaml primitive contracts needed to refine each abstract commit and adapter step. Keep dependent composition theorem separate from persistence theorem so type-level correctness cannot be mistaken for runtime durability.
