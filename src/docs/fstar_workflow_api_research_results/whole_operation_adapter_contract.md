# Whole-operation adapter contract

**Status:** Architecture refinement after adversarial and proof-model critiques. Signatures below are semantic notation, not typechecked F*. No implementation, build, or tests.

## Decision candidate

Use one durable external work node for each operation that owns a complete resource lifecycle. Adapter handles acquisition, use, collection, and release/recovery. Ordinary F* nodes parse raw output and prove semantic properties. Keep scoped capabilities as optional library mechanism for demonstrated algorithms that must interleave resource calls. Do not add a mandatory capability DSL or serialize callbacks/handles.

**Observed:** Current `workflow.evaluate` is pure and returns actions (`WorkflowCore.fst:423-461`). `external` records typed-codec tags, input/capture, and budget reservation but no semantic validator or adapter binding (`:945-1031`). Artifact tags include materialized files/live capabilities, but validator rejects them (`:361-379,654-668`). Runner has scripted outcome cases, not real resource drivers (`Runner.ml:141-151`).

**Inference:** Whole-operation boundary fits current model and target static analyzer. API call granularity does not make external effect atomic. After any possibly dispatched operation whose result is lost, choose reconciliation, same-key deduplicated redelivery, or durable `Unknown`; never infer success/non-application from process loss.

## Typed operation and result layers

Separate request decoding, raw response shape, and semantic verification. Request and raw types are domain types; neither is a generic resource handle.

```text
OpSpec<I, Raw> = {
  operation_id, operation_version,
  request_codec : Codec<I>,
  raw_codec : Codec<Raw>,
  output_contract : OutputContract,
  maximum_charge : nat,
  validate : (x:I) -> Raw -> option (y:O(x) & P(x,y))
}

Outcome<I,Raw> =
    Applied(raw:Raw, receipt:Receipt, artifacts:ArtifactManifest, charge:ChargeEvidence)
  | Pending(token:Token, evidence:CorrelationEvidence)
  | NotApplied(evidence:NonApplicationEvidence)
  | Rejected(diagnostic:Diagnostic, receipt:option Receipt)
  | Unknown(reason:Diagnostic, token:option Token)

ExternalRaw : Work<I, OutcomeValue<Raw>>
Verify : Work<(I & Raw), option (O(I) & P(I,O(I)))>
```

`OutcomeValue` should be a typed sum retained by workflow, not a fake successful `Raw`. Prefer explicit `Applied/Failed/Unknown` branches over exceptions converted to `Raw`. `validate` is pure total F* code. Shape decoding proves only `Raw` well-formedness. `P` requires an F* checker/certificate verifier or explicit named trust axiom. Invalid/malformed response never becomes `Verified`.

Alternative optimization: after `validate`, persist canonical `(y, proof-erased witness/checkable evidence)` as completion. Restore must run a sound decoder/checker indexed by original request to reconstruct proof, or name trusted validation evidence and pin validator build digest. Keep raw receipt/artifact digest for audit. A stored `Raw` alone is not a verified result.

Typed codecs need:

```text
decode(encode(x)) = Some x
decode(w)=Some x ==> ValidInput(x)             // requests
decode_raw(w)=Some r ==> WellFormedRaw(r)       // response shape only
decode_verified(x,w)=Some(y,p) ==> P(x,y)       // verified result
```

The first law alone does not establish sound acceptance of arbitrary bytes. Codecs, validators, schemas, driver and adapter configuration need immutable version plus content/build digest or trusted immutable registry premise. Stable strings alone do not bind implementation bodies.

## Host driver boundary

Do not pretend current F* source contains `IO`. Workflow evaluator creates durable actions; host driver consumes a committed intent and returns candidate events. This matches runner shape without asserting F* effect/extraction support.

```text
Key = (run_id, occurrence_path, attempt, operation_id, operation_version,
       config_fingerprint, request_digest)

Driver<Op> = {
  dispatch : CommittedIntent -> HostResult<Outcome<I,Raw>>,
  reconcile : Key -> RequestDigest -> Option<Token> -> HostResult<Outcome<I,Raw>>
}
```

`HostResult` includes timeout/crash/unavailable as uncertainty, not implied failure. Calls must be bounded by a watchdog that can terminate/isolate the worker or caller; a thread blocked in uninterruptible FFI is not bounded merely because a watchdog exists. Adapter event carries and authenticates `Key`, output digest, protocol evidence, and event identity. Reducer verifies correlation/version/schema and allowed transition; adapter does not write workflow state directly.

### Dispatch states and cut handling

Suggested durable protocol:

```text
IntentCommitted(reservation, request_digest)
DispatchMayHaveOccurred(key)      // commit before invoking driver
    -> Pending(key, token)
    -> Applied(key, raw_digest, receipt, manifest, charge_evidence)
    -> NotApplied(key, authenticated_evidence)
    -> Unknown(key, reason, token?)
    -> Rejected(key, diagnostic, receipt?)
ResultValidated(...)
ArtifactsDurable(...)
CompletionCommitted(...)
```

Persisting `DispatchMayHaveOccurred` before call is conservative: crash between this event and actual call is treated as possibly sent. After restart, `IntentCommitted` alone is not proof no dispatch happened unless the runtime's ordering/storage theorem establishes that fact. If reducer currently moves `Prepared` directly to success/failure (`WorkflowCore.fst:724-739`), strengthen before claiming lost-call safety.

Unknown is durable and dispatch-quiescent. It retains reservation. Reconciliation appends evidence and may refine the current projection to applied/not-applied/terminal; history remains append-only. Fresh attempt only after authenticated `NotApplied`; same-key redelivery only when adapter/backend guarantees deduplication. Terminal success/failure/cancellation absorbs duplicates and late conflicts. A local operation ID does not provide backend deduplication.

Strong safety claim is **prefix safety**, not unconditional restart equivalence:

```text
WellFormedRuntime /
StorageRefines /
AdapterSafety
  ==> every recovered effect is justified by correlated evidence;
      no completed occurrence is dispatched again;
      unresolved dispatch recovers as reconcile or Unknown;
      no observer consumes incomplete artifact references.
```

AdapterSafety includes stable-key semantics: same-key redelivery is idempotent, or reconciliation returns authenticated truthful `Applied(result)` / `NotApplied`, with no cross-key replay. Without it, two backend states (applied vs unapplied) can share identical local post-crash history; no recovery choice guarantees both no-duplicate and no-lost-effect. Full resumed/uninterrupted trace equivalence needs a backend-state relation/bisimulation and an explicit schedule/trace relation; “same future replies” alone is circular when pre-cut effects alter later backend outcomes.

## Static analyzer: one operation owns workspace lifecycle

```text
SourceTree -- analyze operation --> RawAnalysis { report_bytes, declared_outputs }
RawAnalysis -- parse_report --> ParsedFindings
ParsedFindings + SourceTree -- check/certificate --> VerifiedFindings
```

`analyze` request binds exact source-tree digest, relative-path schema, analyzer binary/container digest, argv, declared environment/config identity, output contract, and max charge. Host adapter:

1. Verify request codec and tree validity; safely materialize into fresh isolated root.
2. Launch pinned analyzer with restricted filesystem/network/credentials according to declared policy.
3. Capture capped stdout/stderr, exit status, and declared outputs only.
4. Reject path traversal, symlink escape, path collision, undeclared files, missing required output, invalid file kind, byte cap breach.
5. Preserve exact output bytes and provenance; metadata excluded unless explicitly in contract.
6. Stage output content-addressed bytes; verify digests and manifest; only then publish reference set.
7. Return raw report/artifact manifest and receipt; workflow validates report structure in F*; semantic checker establishes `Sound(source, findings)` when possible.

Materialization/collection contracts:

```text
ValidTree(t) /\ Materialize(root,t)=Ok(paths)
  ==> confined(paths,root) /\ Read(paths)=t

Collect(root, contract)=Ok(tree)
  ==> valid_tree(tree)
      /\ dom(tree) subset contract.allowed
      /\ contract.required subset dom(tree)
      /\ returned bytes equal exact bytes read from confined regular files
```

These require OS/adapter refinement: path normalization, symlink and race handling (e.g. directory-relative no-follow opens), process isolation/termination, output completeness, digest correctness. F* proves tree logic/validator only after receiving evidence; it cannot prove analyzer actually saw the input without trusted adapter evidence/refinement. A report parser proves syntax, not report truth.

### Artifact crash protocol

If blob store and journal do not share atomic transaction, use idempotent stages:

```text
StageBytes(digest, bytes) -> DurableBytes(digest)
StageManifest(op_key, ordered refs, provenance) -> DurableManifest
CommitCompletion(value/raw digest, manifest digest, charge, terminal) // journal linearization point
```

Every completion reference must resolve to already durable verified bytes. Crash before completion may leave orphan bytes/manifests; recovery may garbage-collect only unreferenced staging after safe age/lease rule. Missing/corrupt referenced bytes makes completion unavailable/corrupt and must not silently rerun analyzer as though incomplete. True atomicity claim depends on blob-store durability and journal commit semantics. Current `ArtifactSaved` stores tree bytes/references structurally but has no real external blob staging or materializer (`WorkflowCore.fst:654-768`).

Analyzer local side effects should be sandbox-local and disposable. If adapter can prove process termination and no externally visible write, it may rerun computation after lost response under explicitly idempotent local semantics, but still account compute cost and prevent conflicting artifact publication. If analyzer accesses remote state or emits writes, treat as distributed effect: reconcile/deduplicate or `Unknown`.

## Simple network/JEV-like request

Example: typed `GET /catalog/{key}` is read-only; request contains endpoint identity, method/path/query, schema version, TLS policy/config identity, and secret-reference identity (never secret bytes). Raw response contains status, headers under allowlist, body bytes, server receipt/request ID, and response digest. `raw_codec` checks shape/limits; F* decoder checks content type/schema; F* predicate establishes only checked properties.

For a mutating request or model/JEV generation call, key binds `(run, occurrence, attempt, operation/version, config fingerprint, request digest)`. Reconcile by provider idempotency token or authenticated request lookup. If provider lacks dedup/reconciliation and reply is lost after send, durable `Unknown`; no fresh attempt. For read-only GET, retry may be allowed under declared idempotent/read consistency contract; this says nothing about returning same bytes under changing remote state. JEV-like variable provider charge requires authenticated charge evidence; otherwise `spent` is local ledger estimate, not actual spend proof. Over-reservation evidence is recorded as adapter-contract violation and stops normal settlement; never clamp and call success.

## Inline/library equivalence

Inline and reusable package are packaging forms of same `OpSpec` + `Driver` contract. Equivalent semantics is a relation to prove/assume between implementations, not identity by matching string labels.

Required for equivalence:

- Same request/raw/result schema and codec soundness, operation version, canonicalization, validator/checker digest.
- Same driver behavior relation for every key and reachable backend/store state: correlated outcomes, same effect trace modulo declared equivalence, same reconciliation, idempotency and `Unknown` policy.
- Same resource config bytes/fingerprint, secret version policy, tool/provider identity, output contract, budget semantics, and build/runtime ABI assumptions.
- Library package digest/dependency closure pinned; inline implementation checked against this contract. Equal identity and config are necessary manifest conditions, not proof of code equivalence.
- Construction inertness: importing/configuring descriptor performs no IO, dispatch, or storage mutation.

Proof obligations: request encode/decode roundtrip/soundness; raw output shape soundness; `validate` soundness; effect correlation and terminal monotonicity; adapter trace safety under `Key`; output completeness/confinement; artifact-before-reference; budget reservation/settlement once; extraction/host refinement. A client may discharge semantic theorem for `P`; driver owes assumed/refined contract. No API signature can prove third-party service honors its promise.

## Budget and progress boundary

Reserve max before `DispatchMayHaveOccurred`. Pending/unknown retain reservation. Settle once for terminal verified/raw outcome using authenticated charge `<= reserved`; overcharge causes durable violation, not silent success. Release reservation only on authenticated `NotApplied`. Failed/cancel charging full reservation is policy, not evidence of actual spend. Distinguish local admission bound from provider billing.

For a committed `DispatchMayHaveOccurred` attempt, under finite durable-store commits, functioning watchdog/worker isolation, scheduler fairness, and adapter's bounded local return contract, runner reaches a durable terminal status or `Unknown` within stated local bound. This does **not** assume remote eventual response. Remote success liveness requires separate backend assumption. Pending operation must not block unrelated ready nodes. Clock/deadline and watchdog kill semantics need explicit host model.

## Optional scoped capability: library extension only

Use only where F* algorithm must interleave typed calls, e.g. DB cursor scan with per-page F* validation and aggregation. This does not become a kernel resource language. One durable operation still owns cursor lifecycle; extension exposes a capability only inside its driver callback. Result and crash semantics remain whole-operation contract.

```text
with_snapshot_cursor : DbDesc -> Query ->
  (forall h. Cursor h Open -> HostM (Cursor h Closed, Aggregate & Evidence)) ->
  HostM (Outcome<Aggregate>)

next : Cursor h Open -> HostM (option (Row & Cursor h Open))
```

Here `h` is abstract and cannot be serialized. API may prevent direct return of `Cursor h` under parametricity, but does not prove linearity, no alias, release, or host confinement. Use F* state/effect specifications to prove page validation and aggregate invariant; host refinement must prove cursor operations respect snapshot token and close/kill behavior. After crash, driver restores same snapshot/position if DB guarantees durable cursor/snapshot; otherwise whole operation becomes `Unknown` or restarts only if query is explicitly safe to repeat and no external writes occurred. F* callback must be pinned and deterministic; recovery reruns from a durable logical checkpoint or replays from beginning over same snapshot. Do not persist an arbitrary continuation closure. Each driver call is a crash cut; stepwise visibility costs explicit protocol and proof work. If restartable intermediate phases are first-class product need, model them as separate durable work nodes, not an interpreter for generic `Acquire/Use/Collect/Release` AST.

**Strongest objection:** Whole-operation contract can become too large and opaque: F* cannot see whether correct tree was materialized, all artifacts collected, or process was killed. Answer is explicit, testable, independently reviewable host contract with narrow assumptions and evidence; not pretending F* proves OS behavior. If a concrete multi-step algorithm needs per-call proof, the optional scoped library extension can improve local reasoning, but it does not remove host assumptions or distributed unknowns.

## Evidence and next question

Repository references: `src/docs/fstar_workflow_api_next_research_spec_draft.md:55-146`; `src/fstar/v0/WorkflowCore.fst:318-379,423-461,654-768,829-839,945-1031`; `src/fstar/v0/WorkflowExamples.fst:14-41,51-113`; `src/fstar/v0/Runner.ml:94-139,141-151,193-285`.

Critiques incorporated: `src/docs/fstar_workflow_api_research_results/adversarial_review.md:9-44,105-124,131-152`; `proof_model_critique.md:39-85,90-124,131-141`. They establish the need to correct pseudo-IO, distinguish prefix safety from backend-dependent trace equivalence, add `DispatchMayHaveOccurred`, bind code/config identity, and avoid mandatory second DSL. These are design conclusions, not implementation facts.

**Next investigation:** formalize one host-driver simulation with backend state `B`, durable store `D`, artifact store `A`, volatile state `V`; enumerate cuts before/after dispatch, raw response, bytes staged, manifest staged, terminal commit. Prove prefix safety under minimal storage/adapter assumptions; show countermodel when backend offers neither idempotency nor truthful reconciliation. Separately typecheck one scoped cursor library interface against actual F* effect/extraction path before promoting it beyond optional extension.
