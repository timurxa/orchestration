# F* workflow API: composition alternatives

**Status:** research artifact; no implementation changes.

## Scope and labels

Question: choose typed composition model supporting input-indexed results or guarantees, retaining/projecting input, proof-aware sequencing, durable work identity, and real external work. Three designs below are alternatives, not cumulative requirements.

- **Observation** = directly visible in named source.
- **Derivation** = consequence of signatures or stated semantics.
- **Conjecture** = plausible F* encoding/runtime choice requiring validation.
- **Decision** = recommendation in this artifact.

Notation uses `Tot`, `Type0`, `Σ`, refinements, and indexed families as F*-style notation. Some abbreviations are semantic signatures, not verified F* declarations. “Workflow” below means durable work-node description plus evaluator, not plain function.

## Source observations

- **Observation:** current prototype has `workflow i o` with constant input/output types; `pure`, `then_flow`, `fork`, and `lift` are defined in [WorkflowCore.fst](/Users/alex/areas/productive/orchestration/src/fstar/v0/WorkflowCore.fst:459). `then_flow` feeds left output to right input; `fork` feeds both branches same input and returns ordered pair ([lines 483–499](/Users/alex/areas/productive/orchestration/src/fstar/v0/WorkflowCore.fst:483)).
- **Observation:** local code node carries stable `id`, `version`, capture/input/output codecs and pure `apply`; `pure` writes these tags to manifest ([WorkflowCore.fst](/Users/alex/areas/productive/orchestration/src/fstar/v0/WorkflowCore.fst:464)). Current codec law proves encode/decode round-trip only, not soundness for adversarial wire ([lines 15–21](/Users/alex/areas/productive/orchestration/src/fstar/v0/WorkflowCore.fst:15)).
- **Observation:** store manifest has tagged constructors `MPure`, `MThen`, `MFork`, `MLift`, `MExternal`, `MSo`; occurrences use run ID plus structural path ([WorkflowCore.fst](/Users/alex/areas/productive/orchestration/src/fstar/v0/WorkflowCore.fst:206), [WorkflowStore.fst](/Users/alex/areas/productive/orchestration/src/fstar/v0/WorkflowStore.fst:114)). Thus composition shape currently affects occurrence identity.
- **Observation:** examples show ordinary composition, same-input fork, product lifting, and local additive code ([WorkflowExamples.fst](/Users/alex/areas/productive/orchestration/src/fstar/v0/WorkflowExamples.fst:14)). No dependent result, input-indexed postcondition, prime refinement, or static analyzer implementation appears in these sources.
- **Observation:** draft requires input-indexed result family and fixed-carrier/postcondition alternatives, explicit proof-preserving sequencing, original-input retention, typed static-analysis stages, stable codecs/identities, and honest host/adapter assumptions ([draft §§3–7](/Users/alex/areas/productive/orchestration/src/docs/fstar_workflow_api_next_research_spec_draft.md:29)).

## Design A — proof-carrying dependent output, context-packed sequencing

### Core surface

```fstar
type Work (I:Type0) (O:I -> Type0)
type Verified (I:Type0) (O:I -> Type0)
              (P:(x:I)->O x->Type0)
  = Work I (fun x -> Σ y:O x. P x y)

type Ctx (I:Type0) (M:I -> Type0) (P:(x:I)->M x->Type0)
  = Σ x:I. Σ m:M x. P x m

val it : Work I (fun _ -> I)
val fan : Work I A -> Work I B -> Work I (fun x -> A x & B x)
val keep : Work I A -> Work I (fun x -> I & A x)
// Intended law: keep f x = (x, f x); f runs once.

val project_left  : Work I (fun x -> A x & B x) -> Work I A
val project_right : Work I (fun x -> A x & B x) -> Work I B

val then_keep : Verified I M P
            -> Work (Ctx I M P) G
            -> Work I (fun x -> Σ m:M x. Σ p:P x m. G (x,m,p))
```

`G` may itself be a dependent result family over packed context. A proof-bearing second stage uses `G c = Σ y:N (root c) (mid c) (evidence c). Q ... y`. `then_keep` preserves first value and proof in output, constructs `c=(x,m,p)` without cast, then invokes second node. An output-hiding variant needs a proved projection/postcondition, not erasure by fiat.

### Laws

1. `fan f g` returns `(f x,g x)`; pair order fixed. Readiness and concurrency belong to scheduler semantics, not `fan` law.
2. `keep f` returns original `x` exactly and evaluates `f` once. Projection preserves whichever branch result exists only after join semantics permit it; pending/failure stays explicit.
3. `then_keep f g` returns `(m,p,y,q)` with both contracts. `g` sees original `x`, intermediate `m`, and evidence `p`.
4. For any restored `m`, decoder/checker re-establishes `P x m`; ghost proof is not trusted merely because prior process had it.

### Prime refinement encoding

```fstar
type PrimeAfter (x:nat) = Σ n:nat. prime n /\ n > x
let prime_post (x:nat) (n:nat) = prime n /\ n > x
val next_prime : Verified nat (fun _ -> nat) prime_post

type PrimeCtx = Ctx nat (fun _ -> nat) prime_post
val certify_gap : Work PrimeCtx (fun c ->
  Σ k:nat. prime k /\ k > mid c)
val two_primes : Work nat (fun x ->
  Σ n:nat. Σ p:prime n /\ n>x.
  Σ k:nat. prime k /\ k>n)
  = then_keep next_prime certify_gap
```

`PrimeAfter x` makes value type depend on concrete `x`; witness is proof-carrying refinement. For serialization, encode `n`, decode under `x`, then run a proved primality checker and `n>x` check. Never serialize F* proof object unless extracted proof representation is explicitly stable.

### Static-analysis encoding

```fstar
type Source = BlobTree
type AnalyzerRaw = { report:Bytes; outputs:BlobTree }
type Parsed = { diagnostics:list Diagnostic; outputs:BlobTree }
type Findings = { diagnostics:list VerifiedFinding; outputs:BlobTree }
let analyzer_input_ok (_:Source) (_:AnalyzerRaw) = True
type AnalyzeCtx = Ctx Source (fun _ -> AnalyzerRaw) analyzer_input_ok
type ParseCtx = Ctx AnalyzeCtx (fun _ -> Parsed) ParseOk
type StaticRun (s:Source) =
  Σ raw:AnalyzerRaw. Σ raw_ok:analyzer_input_ok s raw.
  Σ parsed:Parsed. Σ parse_ok:ParseOk (s,raw,raw_ok) parsed.
  Σ findings:Findings. Sound ((s,raw,raw_ok),parsed,parse_ok) findings

val analyze : Verified Source (fun _ -> AnalyzerRaw) analyzer_input_ok
// External driver adds Rejected/Failed/Unknown states around validated success.
val parse : Verified AnalyzeCtx (fun _ -> Parsed) ParseOk
val check : Verified ParseCtx (fun _ -> Findings) Sound
val static_analysis : Work Source StaticRun
  = then_keep analyze (then_keep parse check)
```

`StaticRun` shows preserved intermediate values and evidence; a typed projection can expose `Findings` while preserving `Sound`. Spelling above abbreviates composition through packed context. `analyze` does not claim semantic soundness: it materializes files, runs pinned CLI, collects declared outputs, stores durable bytes; malformed output or process ambiguity remains `Rejected`/`Failed`/`Unknown`. `parse` claims syntax only. `check` proves finding property from source plus parsed report, or output must remain parsed-but-unverified. Adapter obligations remain external to F* type alone.

### Durable identity and ergonomics

`it` is pure and effect-free, but if represented as work node it needs stable constructor/code tag and version; if erased as evaluator optimization, manifest and occurrence identity still need canonical semantics. `keep` can be derived from `fan it f`, but that creates a node/slot for `it`; direct `keep` avoids that tree noise while still requiring its own stable manifest constructor or a canonical desugaring rule. `fan` branches get separate stable path slots; pending branch does not invalidate identity of completed sibling.

Codec for dependent result is indexed: `encode : x:I -> O x -> Bytes`; `decode : x:I -> Bytes -> option (Σ y:O x. P x y)`. Persist input/schema family identity, family-code version, and value codec version. Type family itself is not a wire schema. Resolve the same pinned family implementation on restore; migration must be explicit. Every request capture is separately encoded/versioned. Proof evidence is rebuilt by checker.

### Strongest objection

**Conjecture:** `Work I (fun x -> Σ y. P x y)` has clean theorem boundary, but F* inference and serialization become awkward when outputs are nested dependent `Σ`s. Family equality across serialized contexts may need explicit transport lemmas; ergonomic signatures can conceal substantial annotation burden. No weakening follows: prove or expose these transports.

## Design B — indexed output families, ordinary composition via static context workflow

This design makes dependence primary and treats proof as part of selected output type, rather than separate `Verified` wrapper. It exposes fewer special proof combinators, but authors build the continuation context explicitly.

### Core surface

```fstar
type Work (I:Type0) (O:I -> Type0)

val map : (forall x. A x -> B x) -> Work I A -> Work I B
val fan : Work I A -> Work I B -> Work I (fun x -> A x & B x)
val keep : Work I A -> Work I (fun x -> I & A x)
val then_ctx : Work I M
            -> Work (Σ x:I. M x) N
            -> Work I (fun x -> Σ m:M x. N (x,m))
```

Last line is intentionally a semantic shortcut: second argument gets context `(x,m)`. A complete F* declaration must name result family with an explicit dependent pair, e.g. output `Σ m:M x. N x m`; if stage-one result carries `P`, context is `Σ x. Σ m:M x. P x m`, exactly as in A. This design does not let ordinary `then_flow : Work I M -> Work M N -> Work I N` express value-indexed continuation without context transformation.

### Laws and prime example

Use same `PrimeAfter x` family, but node returns family directly. Build context consumer directly:

```fstar
val next_prime_B : Work nat (fun x -> PrimeAfter x)
val successor : Work (Σ x:nat. PrimeAfter x)
  (fun c -> PrimeAfter (fst (snd c)))
val twice : Work nat (fun x -> Σ m:PrimeAfter x. PrimeAfter (fst m))
  = then_ctx next_prime_B successor
```

Proof is inherent in `PrimeAfter`; a separate proof argument can be included in `M x` if downstream computation needs it explicitly. Static-analysis similarly uses context types `Σ source:Source. AnalyzerRaw` then `Σ source. Σ raw. Parsed`; every stage schema states precisely which prior outputs it consumes.

### Input retention and projection

`keep` or `fan it f` retains `x`; ordinary pair projections become `map fst` / `map snd`. Composition may keep accumulating context: `Σ x. Σ m. Σ n...`. A library can define named records and projection functions to avoid tuple-index paths. No path language needed. This is typed, but context grows unless a proved `map` removes unneeded values.

### Durable identity and codecs

Node identities and codecs match A. Crucial added obligation: every context serialization preserves indices. For `c=(x,m)`, decode `x` first, then decode `m` using schema indexed by `x`; a context codec cannot be a plain product codec when second component type varies. Persist family/type constructor ID plus version and index codec identity. Restore must resolve pinned decoder/checker. `then_ctx` itself gets a stable manifest constructor or canonical lowering whose slot mapping is fixed.

### Strongest objection

**Derivation:** mathematically direct indexed typing does not by itself yield ergonomic sequencing. If library hides context packing, it recreates `then_keep`; if it does not, every stage author repeats dependent pair construction, transports, and tuple projections. Chaining accumulates historical values. This may be acceptable with generated named contexts, but not yet simpler than A.

## Design C — fixed result carrier plus input-indexed contract

This design separates runtime carrier from theorem. It offers conventional workflow I/O types, with contracts attached to node. Useful when a stable output schema matters more than a refined output type.

### Core surface

```fstar
noeq type Flow (I B:Type0) (P:I -> B -> Type0) = {
  work:Work I (fun x -> Σ b:B. P x b)
}
type Checked (I B:Type0) (P:I -> B -> Type0) = Flow I B P

val fan : Flow I A PA -> Flow I B PB -> Flow I (A & B) (pair_contract PA PB)
val keep : Flow I B P -> Flow I (I & B) (fun x r -> P x (snd r) /\ fst r=x)

val then_checked : Checked I B P
                -> Work (Ctx I (fun _ -> B) P)
                     (fun c -> Σ d:C. Q (root c) (mid c) (evidence c) d)
                -> Checked I (B & C)
                     (fun x pair -> Σ p:P x (fst pair).
                       Q x (fst pair) p (snd pair))
```

The carrier component is fixed `B`; contract varies with input value. After extraction, proof may erase, but recovery must re-establish it before constructing `Checked`. `Flow`/`Checked` differ by whether result is accepted as validated for downstream use, not by carrier schema. Sequential composition may produce existential contract `R x y = exists m. P x m /\ Q x m y`; but existential output claim alone may be too weak for later node needing `m` or its proof. Keep intermediate package or provide a checker that reconstructs it.

### Prime example

```fstar
val prime_candidate : Flow nat nat (fun x n -> prime n /\ n>x)
val prime_candidate_checked : Checked nat nat (fun x n -> prime n /\ n>x)

val successor : Work (Σ x:nat. Σ n:nat. prime n /\ n>x)
  (fun c -> Σ k:nat. prime k /\ k > mid c)
val twice : Work nat (fun x -> Σ n:nat. Σ p:prime n /\ n>x.
                                  Σ k:nat. prime k /\ k>n)
  = then_checked prime_candidate_checked successor
```

Runtime carrier remains `nat`; postcondition index carries input value. Codec is simpler for carrier, but recovery must re-establish `P x n` with checker. `Flow` without `Checked` cannot safely feed semantic claims downstream.

### Static-analysis example

```fstar
val cli : External Source AnalyzerRaw
val parse : Checked (Source & AnalyzerRaw) Parsed ParseOk
val verify : Checked (Source & Parsed) Findings Sound
val pipeline : Work Source (Source & AnalyzerRaw & Parsed & Findings)
  = keep cli |> then_checked parse |> then_checked verify
```

`ParseOk` can mean report grammar valid; `Sound` means each emitted finding meets proved source predicate. If no verifier/certificate exists, set output type to `UnverifiedFinding` and contract only says parser succeeded. `AnalyzerRaw` includes exact report bytes plus collected `BlobTree`; typed resource adapter handles safe materialization/collection under filesystem assumptions.

### Durable identity and ergonomics

Carrier codec/tag remains fixed (`nat`, bytes, record); input codec needed to rerun indexed validator. Contract ID/version and checker ID/version must be in manifest alongside carrier schema. A decoder returning `B` is insufficient: revalidate `(x,b)` before constructing `Checked`. Preserve contract proof via recomputation, certificate verification, or explicit named trust assumption. Workflow code version must pin checker semantics; silently swapping checker under same contract tag is invalid.

### Strongest objection

**Derivation:** fixed carrier makes schemas and generic adapters easier, but splits result type from guarantee. Untyped `B` is easy to accidentally consume; every trusted path must carry `Σ b. P x b`. Chained existential guarantees can obscure intermediate evidence. This is viable only if unchecked `Flow` cannot masquerade as `Checked` and checkers are durable, named nodes.

## Comparison

| Criterion | A: verified dependent output | B: indexed family + explicit context | C: fixed carrier + contract |
|---|---|---|---|
| Input-specific result type | Direct | Direct | Contract only |
| Input retention | `keep` / `fan it` | `keep` / `fan it` | `keep` plus contract law |
| Proof-aware sequencing | `then_keep` packages context | Author context explicitly or wrap helper | `then_checked` packages value and evidence |
| Intermediate proof available downstream | Yes, explicit | Yes, if included in family | Yes only through `Checked` |
| Wire schema | Indexed family codec | Indexed family/context codec | Fixed carrier codec, indexed recheck |
| Likely author ergonomics | Good if helper hides pack | Most annotation/projection burden | Familiar data types; contract burden |
| Main cost | Indexed codec and transport proofs | Context growth and repeated dependent plumbing | Proof can be dropped unless API prevents it |

All three need same durable execution theorem and adapter contract. Choice does not solve exactly-once external effects. Durable completion still means validated result/artifact refs/terminal status atomically committed; unknown outcomes stay explicit per draft §6.1.

## Comparative recommendation

**Decision:** adopt **A as public library surface**, with **B as kernel model** and a restricted **C adapter convenience layer**.

Reason: B is most honest core representation: a dependent workflow is a family and a stage consumes statically typed context. A adds one derived `then_keep` plus `Verified` alias to make proof transport explicit, avoids runtime-selected closures, and turns a verbose dependent pair context into reusable helper. C remains useful for stable carrier codecs, but only when exposed as `Checked` after revalidation; do not make unverified carrier flows satisfy verified postconditions.

**Conjecture:** `it` should be structural/pure with stable canonical manifest treatment; expose `keep` as ergonomic helper. Whether `it` is separately persisted depends on occurrence identity policy. Best default: canonicalize `keep f` as one structural node with fixed `Keep` tag, or desugar to `fan it f` before manifest construction, and freeze that lowering/version. Do not let refactor-only desugaring change occurrence paths under an existing plan version.

This recommendation does not assume proofs too hard. It assumes dependent codec and context transport proof interfaces are buildable and all extraction boundaries receive separate refinement proof.

## Durable identity, codec, and recovery obligations common to all designs

1. **Node identity:** persist plan constructor tag/version, stable code or operation ID/version, capture codec tag/version plus encoded capture, input/output schema IDs/versions, adapter ID/version, immutable config fingerprint, and effect/budget contract version. Never serialize closures, `F*` function values, process handles, paths to temporary workspaces, or unpinned checker implementations.
2. **Occurrence identity:** run ID plus stable node slot/path. Pair branches have ordered distinct slots. Sequence stages have stable slots. Named `keep`, `then_keep`, and canonical lowering need specified slot semantics. Persist workflow/build identity and reject incompatible restore visibly. Schema migration must map old IDs and paths deliberately; structural refactor can otherwise alias, orphan, or rerun prior work.
3. **Codec laws:** require round-trip `decode (encode x)=Some x`, plus soundness: any accepted wire decodes to a value satisfying schema and semantic invariants. For indexed codecs, state laws for every index `x`; decode receives/reconstructs `x`, then verifies contract. Current prototype's `codec.roundtrip` alone is insufficient for untrusted/external bytes.
4. **Evidence:** proof terms can stay ghost only if restoration invokes proved decoder/checker/certificate verifier. If checker depends on source, both source identity/content digest and checker version are inputs. Otherwise declare named trust assumption; never infer soundness from parse success.
5. **Effects:** construction pure. Intent/reservation committed before dispatch; raw response not downstream-visible until correlation, validation, artifact durability, and completion commit. Lost reply yields reconciliation or durable `Unknown`; fresh attempt prohibited absent authenticated non-application or same-key deduplicated continuation. Retain budget reservation for unresolved outcome. External result claims conditional on adapter/backend assumptions.
6. **Extraction:** prove or explicitly assume extracted OCaml preserves F* node semantics, codec checks, manifest pinning, sequencing, proof validation, and store atomicity. Tests witness cases; do not replace all-traces/crash-cut proof.

## Unresolved obligations

- Typecheck realistic encodings of `Ctx`, family-indexed codecs, and `then_keep`; record needed `FStar.Pervasives`/universe annotations and equality transports.
- Prove composition preserves contracts under nested dependent `Σ`; include failure, pending, `Unknown`, and branch projection semantics.
- Decide whether result contract proof is stored as certificate, recomputed, or trusted per domain; quantify checker input identity.
- Define typed external fallible sum. `Verified | Rejected | Failed | Unknown` must not let parse/decoder imply semantic verification.
- Define deterministic schema IDs for type families, record evolution, code pinning, and migration. Type identity alone is not durable identity.
- Formalize `keep` and context routing in manifest/path algebra. Prove same node slot after restart and define compatibility across graph refactor.
- Complete OS refinement for safe file materialization, symlink/path policy, output collection, content persistence, and process restart. These remain trust/OS facts absent host proof.
- Define all-cut proof of “durably completed work not rerun,” reducer validity, adapter correlation, scheduler fairness, and local/remote budget distinction.

## Next investigation

1. Write a minimal F* scratch module with Design A aliases, `PrimeAfter`, `Ctx`, one `then_keep`, and indexed decode/recheck; compile and inspect inferred universes/equality obligations.
2. Model context packing and `keep` manifest/path mapping against current `MThen`/`MFork` occurrence paths. Prove constructor stability and crash-resume identity.
3. Encode static-analysis records with typed `Source`, `AnalyzerRaw`, `Parsed`, `Findings`; specify parser and checker postconditions separately. Add a real CLI adapter contract only after pure typed chain checks.
4. Compare `then_keep` API against simple helper derivation from `fan`, product mapping, and projection. Measure author annotation burden using both examples; do not optimize for proof length.
5. State scheduler/store/extraction simulation theorem and adapter assumptions independently from API selection.
