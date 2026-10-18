# Adversarial critique: durability and resource proof models

**Scope.** Audit of `durability_proof_semantics.md`, `resource_adapter_architectures.md`, current source map, and controlling problem spec. No source edits/builds/tests. Labels: **Established** = current source/report evidence; **Inference** = follows from inspected model/source; **Conjecture** = design claim needing experiment or proof.

## Verdict

Both notes identify important trust boundaries. Neither yet states a complete theorem for actual extracted execution. Main gap: labels abstract away critical instruction-level cuts and then assume storage/adapter facts that decide whether recovery can proceed. Strongest honest claim without backend cooperation is safety plus durable `Unknown`, not full restart equivalence or exactly-once effects.

Current prototype has useful reducer-level facts, not runtime refinement. `WorkflowCore.fst` replays journal events; recovered `Prepared` becomes `Unknown`; `external` consumes `Succeeded` output. But `Runner.ml` owns snapshot writes, process-local event queue, dispatch decisions, fake adapters, and recovery loop. No F* theorem connects this OCaml code or filesystem calls to abstract labels. `resume_evaluate` re-evaluates workflow from root input. Report explicitly leaves all-cut continuation and extracted refinement open. **Established.**

## Strongest true theorems

### A. Local committed-completion no-rerun

Strictly quantify this only for workflow occurrences whose result is durably memoized:

```text
Theorem MemoizedCompletionNoReinvoke:
  forall run, plan, input, k, w, trace.
    Compatible(run, plan) /\ ReplayValid(run) /\
    CompletionCommitted(run, k, w) /\
    ResumeTrace(run, plan, input, trace)
    ==> count(trace, InvokeLocalBody(k)) = 0
        /\ count(trace, DispatchNewAttempt(k)) = 0.
```

Need prove evaluator looks up completion by occurrence and plan identity *before* invoking body, decodes/checks stored `w`, and never evicts/overwrites terminal completion. `InvokeLocalBody` excludes reducer bookkeeping and codec/checker execution; define it precisely. This theorem does not apply to current `pure`: it re-runs on each evaluation, and root resume re-evaluates. Current `external` has a narrow `Succeeded`-output consumption path, but no generic occurrence memo table or proved extracted dispatch short-circuit. **Established / blocker:** `WorkflowCore.fst:464-481,855-864,969-1030`.

For nonmemoized deterministic pure code, prove weaker statement:

```text
CompletionCommitted(k,w) ==> count(ExternalEffect(k), ResumeTrace) = 0
```

This permits local recomputation. Do not call it “no rerun.”

### B. External effect safety under indistinguishable crash worlds

Model backend state `B`, not a fixed list of future replies. Let `H` be committed local history. After send/accept/reply-loss, there can be states `(H, B_applied)` and `(H, B_not_applied)` indistinguishable to recovery. If adapter has neither same-key deduplication nor truthful reconciliation, any deterministic choice fails one world: resend duplicates effect in applied world; skip loses effect in non-applied world. Random choice cannot guarantee both either.

Strongest unconditional theorem:

```text
Theorem NoFabricatedEffect:
  forall reachable local history H, recovery actions a.
    NoAuthenticatedEvidence(H, applied_or_not_applied)
    ==> recovery cannot claim Succeeded or authorize fresh-key retry;
        it may preserve uncertainty as durable Unknown.
```

To prove useful retry/no-duplicate guarantees, explicitly assume an adapter contract: stable key binds `(run, occurrence, attempt, op version, request digest)`; same-key redelivery is idempotent, or reconciliation returns authenticated, truthful `Applied(result)` / `NotApplied`; correlated results cannot be replayed across keys. These assumptions must be about backend semantics, not merely signature checks. F* can prove the reducer respects evidence; it cannot prove remote service honors evidence. Current `op_spec` has no adapter field or response-validation contract. **Established:** source map; `WorkflowCore.fst:945-1031`.

### C. Conditional cut safety, not blanket equivalence

Use one transition system with local durable store `D`, backend state `B`, artifact store `A`, and volatile state `V`. Cut can occur *inside* host action. For any cut, recovery must produce either (i) validated committed completion and continue without redispatch, (ii) safe same-key reconciliation/redelivery under adapter contract, or (iii) explicit `Unknown`/unavailable. Then prove prefix safety:

```text
Theorem RecoveryPrefixSafety:
  forall execution e, cut c, recovered r.
    WellFormedRuntime(e) /\ StorageRefines(e) /\ AdapterSafety(e)
    /\ Recover(DurablePrefix(c)) = r
    ==> ObsEffects(r) is a permitted prefix/refinement of ObsEffects(e)
        /\ no committed consumer sees invalid/missing output
        /\ no budget is settled twice
        /\ unresolved external outcome remains Unknown.
```

This is weaker and more defensible than `Obs(Resume)=Obs(Uninterrupted)`. Equality requires stronger adapter replay semantics and a definition of backend nondeterminism. “Same future backend outcomes” is unsafe as currently worded: backend outcomes may depend on effects before the cut. Either compare paired executions from related backend states under a bisimulation, or define an oracle trace that includes pre-cut effects and prove relation preservation. Do not stipulate identical replies independently of backend history; that assumes away the hard case.

Even the weaker theorem needs actual runtime refinement. F* reducer lemmas alone do not prove `Runner.ml` JSON encoding, file replacement, fsync, adapter event handling, or process cut behavior. **Established:** `WorkflowStore.fst:327-339`, `Runner.ml:94-140,193-290`; report says refinement absent.

## Circularity and hidden assumptions

1. **`DurableSuccess` bakes in target.** It means an atomic committed completion already names validated output, artifacts, provenance, and success status. Then “durable success is recoverable” is near-definitional. Still need prove runtime can establish this predicate and storage refinement preserves it across power loss/corruption. Separate `CompletionIntent`, `BytesDurable`, `ManifestDurable`, `Validated`, `CompletionCommitted` states.
2. **T2 assumptions already include short-circuit.** The note says resume interpreter short-circuits before body/dispatch. That is the central implementation lemma, not a harmless premise for claiming implementation-level no-rerun. Prove evaluator behavior and extracted runner simulation.
3. **Cut granularity too coarse.** Prefix boundaries between abstract labels miss cuts during encode/write/fsync/rename/directory-fsync, after remote acceptance before reply, between response decode and validation, during blob write, and between durable journal append and in-memory projection. Need each concrete primitive have atomicity contract or split states around it. A crash after rename but before directory sync may restore old/new/missing file depending platform/FS contract; current runner merely attempts directory fsync.
4. **Atomic completion is not a free primitive.** SQLite journal + blob store cannot atomically commit together without a protocol. “Atomic or recoverable staged commit” must specify durable stage records, idempotent repair, hash verification, orphan cleanup, and the exact linearization point. Otherwise property assumes itself.
5. **Code identity is more than stable strings.** IDs/versions do not prove callback body unchanged. Need content/build digest plus registry, dependency, codec, validator, adapter, runtime ABI/toolchain policy, or trusted immutable deployment assumption. Current resume compares caller-provided build/manifest/codec labels; a valid edited root input can remain replay-valid. **Established:** implementation map and `WorkflowExamples.fst:561-573`.
6. **Replay validity is not authenticity.** `state_is_replay_valid` means replay from current header/journal yields matching projection. It does not authenticate header or defend against coherent rewrite. Need storage integrity/trusted DB boundary or authenticated snapshot chain. Do not infer input authenticity from replay consistency.
7. **“Same future backend outcomes” is circular/underspecified.** An effect may change backend state, which changes later observations. Require backend-state relation and adapter simulation, or weaken to safety/prefix refinement.
8. **Unknown is not simply absorbing.** It must stop *new dispatch*, yet allow evidence-driven transition to `Succeeded`/`Failed`/`NotApplied` where protocol permits. Call it “dispatch-quiescent”; specify legal evidence transitions. Current reducer permits `Unknown -> terminal`, and `NotApplied` handling/retry is a separate transition. **Established:** `WorkflowCore.fst:726-754`.
9. **Progress premise can be vacuous.** “Attempt reaches terminal or Unknown” is trivially satisfied if attempt starts in Unknown or runner can mark it Unknown immediately. State start condition: committed Prepared plus dispatched/possibly-dispatched attempt. Prove bounded local path to durable quiescence, with finite store commit and watchdog assumptions. Also distinguish operation outcome from runner liveness. An adapter may block in uninterruptible FFI; a watchdog cannot make a blocked thread return unless process isolation/kill semantics are assumed.
10. **Budget settlement needs events and scope.** Define reservation per attempt, cumulative cap, concurrent linearization, terminal charge event idempotency, overcharge behavior, cancellation/refund policy, and whether “budget” is admission estimate or actual backend spend. Kernel proves ledger arithmetic only; external cost bound requires honest adapter/backend evidence. Current reducer permits `Prepared -> Succeeded` and status record lacks correlation/authentication evidence. **Established:** `WorkflowCore.fst:719-748`.
11. **Artifact provenance is asserted unless checked.** A digest proves bytes match digest only under hash/byte-store assumptions; does not prove source, tool, or semantic correctness. `BlobTree` shape checks do not prove materialization confinement or that collected bytes came from declared paths. Current reducer rejects `MaterializedFile`/`LiveCapability`; artifact records lack content digest and atomic success link. **Established:** `WorkflowCore.fst:654-668,370-379`.
12. **B/C do not solve distributed atomicity.** Per-step journaling still leaves effect-before-ack cut. Scoped handle rank-2 typing cannot force host FFI to obey scope, stop process escapes, or recover cursor snapshot. C adds cuts and protocol state; it does not strengthen remote guarantees absent adapter contract.

## Minimal cut-state protocol that supports honest proofs

Keep kernel operation protocol small. Use durable states/events below; define every boundary as append/commit or an explicit uncertain interval. Artifacts staged separately from journal.

```text
Absent
  -> IntentCommitted(key, request_digest, reserved_max, pinned_versions)
  -> DispatchMayHaveOccurred(key)       // commit before calling adapter
  -> { Pending(token), Unknown }         // only correlated adapter evidence
  -> ReplyStaged(raw_reply_digest)       // optional durable raw receipt
  -> OutputValidated(output_codec, proof/checker_version, value_digest)
  -> ArtifactRefsValidated(manifest_digest, refs)
  -> CompletionCommitted(value/ref set, provenance, actual charge, terminal status)
  -> Consumed
```

Required rules:

- `IntentCommitted` precedes any call. Restart from Intent alone cannot infer no dispatch; it enters reconciliation/Unknown.
- `DispatchMayHaveOccurred` is deliberately conservative. Crash after it always behaves as possibly sent, even if call never started.
- `ReplyStaged` is evidence, not success. Decode/semantic validation may fail; invalid reply becomes failure/Unknown by declared policy, never completion.
- Artifact bytes become durable and digest-verified before `ArtifactRefsValidated`; orphan bytes are allowed. Completion references only validated durable refs.
- One atomic journal commit makes validated value, evidence, artifact manifest refs, terminal status, and budget settlement visible together. If impossible with chosen stores, use recoverable staging protocol with idempotent finalize/repair; prove no consumer observes half-completion.
- `CompletionCommitted` is immutable. Resume may check/redecode and then consume; never rerun body or dispatch occurrence.
- Fresh attempt requires authenticated `NotApplied` for prior key, or an explicit policy weakening no-duplicate guarantee. `Unknown` is dispatch-quiescent, not evidence of failure.
- Every append/rewrite has concrete storage crash semantics. Filesystem/SQLite contracts listed as axioms must be narrow and independently testable; they cannot say “recovery returns same state” when that is theorem target.

This protocol still cannot give exactly-once remote effects by itself. It yields at-most-one logical key plus truthful uncertainty, conditional on key stability and adapter/backend semantics.

## Adapter architecture critique

**Established current fit:** Current core already models a whole typed external operation as durable intent and OCaml adapter action. Its small surface matches A. It does not materialize files, persist real resource handles, or connect to actual service. The proposed A/B/C descriptions are design sketches, not compile-tested APIs.

**A: whole operation.** Best minimal kernel boundary when adapter owns multi-step resource lifecycle. Contracts must include idempotency/reconciliation, correlation, output validation, artifact staging/collection, boundedness/cancellation semantics, budget evidence. Opaque implementation reduces F* visibility but can still support honest `Unknown` and typed local post-validation. No proof that whole operation is atomic just because API call is one function.

**B: scoped capability.** Rank-2 handle scope is useful type discipline, not host enforcement. F* node code with effects requires an actual effect model and extracted-runtime refinement; arbitrary IO/callbacks would invalidate replay. Each effect call creates a crash cut and partial-progress state. Better only when resource is local/modelled and adapter operations individually have tractable contracts.

**C: typed lifecycle AST.** Current sketch is at risk of violating core spec: `CapProgram` is a closed operation language interpreted by driver, i.e. second DSL if workflow author must express dynamic logic in it. “Compile typed F* node to protocol calls” needs ordinary F* execution, not a general F* interpreter or serialization of closures. Clarify split: F* runs local algorithm; typed effect calls cross adapter boundary and produce journal events. If AST exists only inside library for fixed protocol, demonstrate it is ordinary F* abstraction and not mandatory user language. C’s `Acquire/Use/Collect/Release` names add no guarantee over A unless their transitions and crash states are proven.

Recommendation “C general, A derived, B closed” is not warranted yet. **Inference:** A is smallest supportable kernel given current source/spec. C may be library-level protocol abstraction after comparison; B is specialized local capability layer. Keep choice provisional pending concrete examples, actual F* types, cut proof, and extracted runner refinement. The spec requires compare alternatives, not force a winner from concept sketches.

## Exact proof/test target list

1. **Typed core:** dependent `then` preserves input-indexed output/postcondition; `fan` slot order; traversal shape; route direct/child result and bounded recursion. These are F* theorems, distinct from persistence.
2. **Construction inertness:** no adapter/event/store action during descriptor/workflow construction; theorem over effect semantics plus test that construction trace empty.
3. **Reducer:** event sequence/idempotency; status transition evidence; attempt uniqueness; no settle twice; budget invariants; route choice immutable; completion monotonicity. Strengthen reducer input with correlated proof/evidence, not bare status labels.
4. **Code and codec compatibility:** prove encode/decode value and evidence soundness for all accepted wires, canonical formats, build identity binding. Current codec roundtrip is one-directional and state codec lacks general roundtrip; decoder acceptance needs semantic predicates.
5. **Recovery model:** induct on every transition and all cut states using backend relation; prove prefix safety and conditional progress, then stronger equivalence only under explicit backend bisimulation/dedup assumptions.
6. **Extracted refinement:** simulation relation from F* abstract state/events/actions to OCaml runner + serialization + storage. Cover exceptions, duplicate/late/out-of-order events, parser failures, fsync/rename, process restart. This is central blocker, not optional follow-up.
7. **Artifacts:** separate bytes/manifest/journal; prove digest/read integrity under store assumption; checker soundness; provenance semantics; path confinement/materializer FFI contract; no reference before bytes durable. Current materialization unavailable.
8. **Progress:** scheduler fairness for continuously ready work, pending does not block independent ready work, bounded/killable adapter operation, store liveness, clock semantics. Test event scripts exercise selected traces; they do not prove fairness or all cuts.

## Next investigation

Formalize two indistinguishable post-crash backend worlds for one non-idempotent operation, then define the minimal adapter contract that separates them. In parallel, enumerate concrete runner cut points around intent snapshot, adapter call, reply event, blob persistence, and completion snapshot. This will expose whether a proposed equivalence is possible or only prefix safety plus `Unknown`.
