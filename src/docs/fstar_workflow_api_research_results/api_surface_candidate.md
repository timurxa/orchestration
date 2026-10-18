# Minimal F* workflow API candidate

**Status:** design candidate; pseudo-signatures only. No implementation or compile claims.

## Decision

Use one dependent work type, `Work I O`, with correctness evidence carried in output family. Do not add `Verified` as kernel wrapper. Offer it as a type alias/helper over `Work` when useful. Keep kernel small: `id`, `fan`, dependent `seq`, plus one typed external-operation constructor. Derive `keep_input` and `then_keep` in ordinary F* library.

This follows adversarial review's minimal-core recommendation. It rejects a kernel resource DSL: one analyzer invocation is one durable external node; its host adapter owns materialize/run/collect protocol. F* nodes parse and check typed results. Scoped capabilities remain later library work if a real workflow needs F* to interleave resource calls.

Labels below: **Observation** = source fact; **Decision** = selected design; **Assumption** = boundary outside F* proof; **Pseudo-signature** = semantic F*-shaped notation, not compile-checked syntax.

## Core types and operations

### Work and output evidence

**Pseudo-signature:**

```fstar
type Work (i:Type0) (o:i -> Type0)

type Verified (i:Type0) (o:i -> Type0)
              (p:(x:i) -> o x -> Type0) =
  Work i (fun x -> Sigma (fun y:o x -> p x y))
```

`Work i o` means each root input `x:i` yields output of type `o x`. Constant family `fun _ -> B` gives ordinary fixed carrier. Input dependence is in `o x`, not just `i`'s type. Evidence is part of result type: `Sigma y. p x y`. `Verified` is only alias; no second workflow semantics.

`Verified` is convenient name for fixed carrier plus dependent postcondition. For an intrinsically refined result, put refinement directly in `o x`. These are different authoring spellings, not separate kernel models:

```fstar
type PrimeAfter (x:nat) = Sigma (fun n:nat -> prime n /\ n > x)
type PrimeAfterViaContract =
  Verified nat (fun _ -> nat) (fun x n -> prime n /\ n > x)
```

F* equality between two encodings may require explicit conversion lemmas; do not assume definitional equality. Both expose prime witness and proof to composition.

### Identity, same-input fan, sequencing

**Pseudo-signatures:**

```fstar
val id : #i:Type0 -> Work i (fun _ -> i)

val fan : #i:Type0 -> #a #b:(i -> Type0) ->
  Work i a -> Work i b -> Work i (fun x -> a x & b x)

val seq : #i:Type0 -> #m:(i -> Type0) ->
          #n:((Sigma (fun x:i -> m x)) -> Type0) ->
  Work i m -> Work (Sigma (fun x:i -> m x)) n ->
  Work i (fun x -> Sigma (fun y:m x -> n (x,y)))
```

`id x = x`. Note output family is constant `i`; writing `fun x -> x` is ill-kinded for ordinary values because `x` is not a type.

`fan f g x = (f x,g x)`, left-to-right pair order. This states dataflow only. It does not promise parallel execution, fairness, or branch completion order. Pending/failure remains explicit in evaluator state; join exposes pair only once both outputs exist.

`seq f g x`: run `f x = y`; call statically supplied `g` on packed context `(x,y)`; return `(y, g(x,y))`. `g` is a `Work` value with stable plan identity, not a runtime-selected closure. Its input is a typed dependent pair. `seq` preserves intermediate output for later proof/evidence use.

### Derived retention and proof-aware spelling

Define `Ctx i m = Sigma (fun x:i -> m x)`.

```fstar
val keep_input : Work i m -> Work i (fun x -> i & m x)
let keep_input f = fan id f

val then_keep : Work i m -> Work (Ctx i m) n ->
  Work i (fun x -> Sigma (fun y:m x -> n (x,y)))
let then_keep f g = seq f g
```

`then_keep` is naming/record-friendly alias for `seq`, not kernel constructor. Since `Ctx i m` unfolds to `Σ x. m x`, signatures match. For proof-bearing stage one choose `m x = Σ y:O x. P x y`; `g` receives original `x`, value `y`, and proof `P x y` as ordinary packed input.

Projection stays ordinary typed F*: `fst`, `snd`, named record selectors. Do not add string/path projection DSL. For a later workflow needing only one field, give it a statically declared `Work` over full context; total selectors run inside that node. If users repeatedly need context mapping, add library `first`/`second` only with typed signatures and untouched-field laws.

## Dependent codecs and evidence restoration

**Decision:** proofs need not be serialized. Encoded value alone cannot reestablish a proposition. Decode must return evidence by recomputation or certificate checking, indexed by the exact original input.

**Pseudo-signature:**

```fstar
type IndexedCodec (i:Type0) (o:i -> Type0) (p:(x:i)->o x->Type0) = {
  schema_id:string;
  schema_version:nat;
  encode:(x:i) -> (y:o x) -> Bytes;
  decode:(x:i) -> Bytes -> option (Sigma (fun y:o x -> p x y));
  encode_roundtrip:(x:i) -> (y:o x) ->
    Lemma (decode x (encode x y) == Some (y, proof_for y));
  decode_sound:(x:i) -> (b:Bytes) ->
    Lemma (decode x b = Some (y,proof) ==> p x y)
}
```

Last two fields are theorem intent, not literal dependent pattern syntax. `decode_sound` is the key arbitrary-wire law; round-trip alone does not make external bytes trustworthy. A raw external response first decodes to raw schema, then a proved validator/checker constructs verified result. Invalid bytes, failed checker, failed process, or uncertain effect remain explicit failure/unknown states; never coerce them to proof-bearing output.

Persist stable schema/family ID and version, index codec ID/version, value codec ID/version, checker/certificate-verifier ID/version, and source/request digest where relevant. Type family implementation is not a durable schema. Restore resolves pinned versions or reports unavailable; schema migration is named and proved. Pair/context codec decodes `x` first, then decodes dependent `m x`; do not treat dependent context as unindexed pair bytes.

## Durable node identity and occurrence paths

**Observation:** current prototype manifests have tagged `MPure`, `MThen`, `MFork`, `MLift`, `MExternal`, `MSo`; occurrence is run ID plus structural path. `then_flow` and `fork` assign distinct left/right path segments. See [WorkflowCore.fst](/Users/alex/areas/productive/orchestration/src/fstar/v0/WorkflowCore.fst:206) and [WorkflowStore.fst](/Users/alex/areas/productive/orchestration/src/fstar/v0/WorkflowStore.fst:50).

**Decision:** retain structural plans; persist versioned constructor tags and stable child slots. Every local work node pins code ID/version, capture codec/version and encoded capture, input/output schema IDs/versions. External node also pins operation/adapter ID/version, immutable config fingerprint, request schema/digest, budget contract, and result validator. Never serialize native closure, F* function, or live OS handle.

`id` is pure and can be structural `MId` with fixed version; it need not require registry entry. It still has defined canonical lowering and type codecs if its value crosses a durable boundary. `fan` creates stable ordered `FanLeft`/`FanRight` slots. `seq` creates stable `SeqFirst`/`SeqSecond` slots; second receives `(root,first-output)`.

`keep_input` is derived as `fan id f` at source level, but naïve desugaring changes plan shape and adds an `id` slot. Therefore manifest builder must canonicalize this spelling to one specified `KeepInput` constructor with one child slot for `f`, or always persist expanded `fan` shape from first version. Choose one before runs exist; pin lowering version. Recommended: `KeepInput` tag, child path `KeepChild`, returned pair order `(input,output)`. It evaluates `f` once. Do not switch lowering under existing manifest version.

Projectors `fst`/`snd` are pure F* functions, not work occurrences. If projection is wrapped as a durable local node, it needs its own stable code ID/version and path slot. Prefer selectors inside next node's statically pinned code. A source refactor that changes `seq`/`fan` tree changes slots; workflow identity/version must reject incompatible resume or use explicit migration. No promise that paths survive arbitrary refactoring.

**Derivation:** keeping input can preserve a value through a pending downstream node only if restore can reconstruct it. It is either in persisted upstream result/context via codec or recoverable from root input and a proved deterministic path. Make that recovery rule explicit; never depend on process memory.

## External operation: one durable node, adapter-owned lifecycle

**Decision:** static analysis uses one external whole-operation node. CLI adapter owns safe materialization, process launch, collection, and resource recovery. Kernel does not add `Acquire/Use/Collect/Release` mini-language. F* validates typed raw response, parses report, and proves findings.

**Pseudo-signature (declaration only):**

```fstar
type OpSpec (i raw:Type0) = {
  operation_id:string;
  operation_version:nat;
  request_schema:CodecTag;
  raw_schema:CodecTag;
  maximum_charge:nat
}

val external : OpSpec i raw -> Work i (fun _ -> raw)
```

This signature describes successful typed result only. Actual evaluator/runner separately models pending, failure, rejection, and `Unknown`; result is not available downstream before correlation, raw decoding, validation, artifact durability, and terminal commit. Driver calls are host operations over committed intents, not an undefined F* `IO` effect. A lost reply requires same-key reconciliation or durable `Unknown`; local operation ID alone does not prove exactly-once effects.

Adapter contract must bind exact encoded request, occurrence/attempt, pinned executable and configuration, output allowlist, source digest, and response. Path confinement, symlink/race handling, byte limits, artifact staging/publication, watchdog, and remote charge remain host assumptions or separately proved refinement. Staged bytes must not be referenced by durable completion until available under defined crash-recovery protocol.

## Worked compositions

### Prime refinement

```fstar
type PrimeAfter (x:nat) = Sigma (fun n:nat -> prime n /\ n > x)

val next_prime : Work nat PrimeAfter
// Each x yields (n, proof: prime n / n>x).

val next_gap : Work (Sigma (fun x:nat -> PrimeAfter x))
  (fun c -> PrimeAfter (fst (snd c)))

val two_primes : Work nat
  (fun x -> Sigma (fun p:PrimeAfter x -> PrimeAfter (fst p)))
let two_primes = then_keep next_prime next_gap
```

No runtime-selected continuation. `next_gap` is static durable plan node; input includes original `x`, first prime, proof. Output retains first prime plus second prime. To encode across restart, encode each natural; decoder checks both primality and inequalities against reconstructed `x`/first prime.

### Static analysis

```fstar
type Source = BlobTree
type Raw = { report:Bytes; outputs:BlobTree }
type Parsed = { findings:list Finding; certificate:option Bytes }
type Findings = list VerifiedFinding

type AnalyzeCtx = Sigma (fun s:Source -> Raw)
val analyze : OpSpec Source Raw -> Work Source (fun _ -> Raw)

val parse : Work AnalyzeCtx
  (fun c -> Sigma (fun p:Parsed -> ReportWellFormed (fst c) (snd c) p))

type ParsedResult (s:Source) =
  Sigma (fun r:Raw -> Sigma (fun p:Parsed -> ReportWellFormed s r p))
type CheckCtx = Sigma (fun s:Source -> ParsedResult s)
val check : Work CheckCtx
  (fun c -> Sigma (fun f:Findings -> Sound (fst c) f))

val analyzed_and_parsed : Work Source
  (fun s -> ParsedResult s)
let analyzed_and_parsed = then_keep analyze parse

type PipelineResult (s:Source) =
  Sigma (fun parsed:ParsedResult s ->
    Sigma (fun findings:Findings -> Sound s findings))
val pipeline : Work Source PipelineResult
let pipeline = then_keep analyzed_and_parsed check
```

`PipelineResult` formed by `seq` retains parser result/proof plus checker result/proof; `ParsedResult` retains raw report and source-indexed syntax evidence. `check` sees source through `fst c`; no source capture or serialized continuation. A library can define typed `findings_of`. `analyze` adapter snapshots/materializes `Source`, runs pinned analyzer, collects report/output tree. `parse` proves syntax only. `check` proves `Sound source findings` or verifies analyzer certificate. Without sound proof, use `UnverifiedFinding`; parsing cannot claim truth.

## Laws and boundaries

- **Type law:** every reachable result has family `o x`; `seq`, `fan`, `keep_input` preserve exact indices and ordered values. Composition transports proof evidence by ordinary dependent-pair construction.
- **Recovery law:** successful durable output decodes to same typed value and re-establishes every semantic predicate. Completed node is not dispatched again; incomplete pure local computation may be recomputed. This is an all-cut store/runtime theorem, not a consequence of API types.
- **Occurrence law:** same pinned plan, root input, and schema versions reproduce node slots. Changed tree requires rejection or explicit migration. Stable IDs do not prove executable equivalence.
- **Adapter law:** adapter reply correlates to exact request/attempt/config; validation precedes downstream use; unresolved effects retain reservation and become reconciled or `Unknown`. Eventual remote success requires backend assumption.
- **Extraction law:** source F* proof does not prove OCaml host behavior by itself. State/prove extraction refinement, store atomicity, runner correctness, and OS assumptions. Tests support claims but do not replace them.

## Provenance and open obligations

- **Observation:** current code uses fixed `workflow i o`, `then_flow`, and `fork`; no dependent output family is implemented. `code_ref` already stores ID/version and codec tags. [WorkflowCore.fst](/Users/alex/areas/productive/orchestration/src/fstar/v0/WorkflowCore.fst:459)
- **Observation:** current codec proves round-trip, not arbitrary-wire decoder soundness. [WorkflowCore.fst](/Users/alex/areas/productive/orchestration/src/fstar/v0/WorkflowCore.fst:15)
- **Observation:** adversarial review rejects a hybrid `CapProgram` kernel, calls out ill-kinded identity spelling `fun x -> x` for ordinary values, and recommends `Work I O`, same-input `fan`, context-passing `seq`, derived `keep_input`/`then_keep`, and one whole-operation adapter.
- **Open:** typecheck indexed family/context encodings; prove dependent codec soundness and evidence reconstruction; define canonical manifest constructors/path compatibility; formalize host adapter and artifact crash protocol; prove extracted runner refinement and all-crash-cut completion property.
- **Not claimed:** pseudo-signatures compile; host/OS assumptions hold; external effects execute exactly once; arbitrary refactors preserve occurrence paths.
