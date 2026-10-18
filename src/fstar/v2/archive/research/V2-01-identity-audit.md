# V2-01 identity registry and P0 audit

> **Historical snapshot — pre-implementation.** Its inventory describes the
> earlier kernel. Current identity declarations and remaining P0 gaps are in
> `V2-01-02-simplification.md`, `V2-01-implementation-addendum.md`, and the
> normative implementation spec.

**Status:** independent design audit; recommendations below are not implementation evidence. No implementation `.fst` files were changed.

## Finding

The V2-01 target is sound in intent, but P0 cannot currently be discharged. `Kernel.fst` declares identity records and records carrying codec laws, but no registry, no resolver, no refinement between `work_ref` and `work`, no graph-codec implementation, and no journal/action types. The current kernel therefore does not prove that a durable identity selects the same executable definition after restart.

The smallest proof-friendly route is to make durable identities structural keys into a closed, immutable, typed registry; make every executable package constructible only together with its derived durable reference; and prove lookup/canonical decoding properties by induction over that registry. Use full structural identity equality for correctness. A digest may be an index, never the equality witness. Keep the code-extraction/runtime claim explicit: F* can prove resolution to the registered F* value, while equality of that value to a separately compiled host function requires an extraction/refinement proof.

## Repository facts (verified by inspection)

- `src/fstar/v2/src/WorkflowV2/Kernel.fst:6-7` defines `bytes = list nat` and `digest = bytes`; no hash function or collision law exists.
- Identity records contain name/version/build at `Kernel.fst:9-37`. These are data only; no uniqueness, immutability, or semantic binding follows from their declarations.
- `codec` and `indexed_codec` carry roundtrip and canonicality proofs at `Kernel.fst:43-61`. Those proofs apply to each supplied record only; there is no identity-indexed codec registry.
- `code_ref`, `op_ref`, and `generator_ref` put an identity beside executable fields at `Kernel.fst:63-80,98-108`. Nothing proves the identity determines `run`, `validate_reply`, or `generate_graph`.
- `work_ref` and `work_package` at `Kernel.fst:126-137` permit an arbitrary executable `work` to be paired with an unrelated durable `work_ref`. Recovery may therefore resolve a different function than the one run before restart.
- `graph_desc` is payload bytes only at `Kernel.fst:83-88`; the kernel has no `GraphCodec` value or event/action vocabulary. The sole source module is `Kernel.fst` (`rg --files src/fstar/v2/src`).
- The normative target explicitly requires exact resolution and canonical indexed decoding in P0 (`implementation_spec.md:913-914`), and allows a digest only as an index unless collision resistance is supplied (`:91-97`). It leaves the concrete registry representation open (`:317-334`).
- The spec's durable event families and identity commitments are defined at `implementation_spec.md:577-625`; in particular, `GraphCommitted` resolves its exact generator from the committed parent (`:587-600`), and `CallIntent` binds an adapter occurrence, request, operation, and reservation (`:606-624`).
- The only configured F* target is `make -C src/fstar/v2 verify`, which checks `WorkflowV2/Kernel` (`Makefile`). I attempted it; this environment reports `fstar.exe: command not found` (exit 127). Thus this audit has no new F* verification result.

## Recommended minimal representation

### 1. Separate identity from implementation; package by construction

Keep the existing identity variants, but define identity equality structurally over *all* identity fields. Add a canonical manifest identity for each registered definition, containing the exact registry namespace/release, kind, declared name/version, and a build artifact identifier. If `*_build` remains a digest, it is only a lookup accelerator. The registry key comparison and proof use full identity fields plus manifest bytes (or a formally defined collision-free artifact identifier), never `digest_equal ==> same_code`.

Use a closed heterogeneous registry. Schematic F* shapes:

```fstar
type packed_codec : Type1 = a:Type0 & codec a
type packed_code : Type1 = c:Type0 & i:Type0 &
  (o:i -> Type0 & code_ref c i o)
type packed_operation : Type1 = c:Type0 & i:Type0 &
  (o:i -> Type0 & op_ref c i o)
type packed_generator : Type1 = c:Type0 & i:Type0 &
  (o:i -> Type0 & generator_ref c i o)

type registry = {
  codecs:list packed_codec;
  codes:list packed_code;
  operations:list packed_operation;
  generators:list packed_generator;
  graph_codecs:list packed_graph_codec;
  registry_manifest:bytes
}
```

Every entry must carry a key equality proof against the implementation's own identity, and a structural `NoDuplicateKeys` proof. Prefer an inductive `Registry` (`Empty | AddCodec ... | AddCode ...`) so uniqueness and lookup soundness/completeness are proved once by constructor induction. A flat record of arbitrary lists plus Boolean callbacks merely relocates P0 into opaque callbacks.

Resolve by identity and return an existential package *with an equality witness*:

```fstar
val resolve_codec : r:Registry -> id:CodecIdentity ->
  Tot (option (a:Type0 & c:codec a & c.codec_id == id))
val resolve_code : r:Registry -> id:CodeIdentity ->
  Tot (option (c:Type0 & i:Type0 & o:(i -> Type0) &
    f:code_ref c i o & f.code_ref_id == id))
val resolve_operation : r:Registry -> id:OperationIdentity ->
  Tot (option (c:Type0 & i:Type0 & o:(i -> Type0) &
    f:op_ref c i o & f.operation_ref_id == id))
val resolve_generator : r:Registry -> id:GeneratorIdentity ->
  Tot (option (c:Type0 & i:Type0 & o:(i -> Type0) &
    f:generator_ref c i o & f.generator_ref_id == id))
```

`==` here means full structural equality of keys, not equality of a digest or extensional equality of functions. The packages returned are the registry's actual values. A durable descriptor contains only keys, schema/type identities, and canonical capture/config bytes; it never contains the existential package, closure, or runtime handle.

### 2. Make `WorkRef` a refinement, not a neighboring record

Do not expose the current unrestricted `{ executable_work; durable_work_ref }` constructor. Derive the durable reference from the executable package and canonical capture bytes, and keep the equality proof in the package:

```fstar
val ref_of_work : w:Work i o -> canonical_capture:Bytes ->
  Tot (WorkRef i o)

noeq type pinned_work (i:Type0) (o:i -> Type0) = {
  semantics:Work i o;
  durable_ref:WorkRef i o;
  ref_exact:durable_ref == ref_of_work semantics durable_ref.canonical_capture
}

val resolve_work : r:Registry -> ref:WorkRef i o ->
  Tot (option (w:pinned_work i o & w.durable_ref == ref))
```

The implementation should avoid comparing `Work` function values. The proof is that the resolver returns the package stored under the exact key and that its derived ref equals the requested ref. For local code, registry entry construction ties `CodeIdentity` to the `CodeRef` record; for operations it ties the identity to the validator and operation contract; for generators it ties the identity to the generator and graph-codec identity. Capture bytes must decode with the package's exact capture codec and re-encode canonically. Do not accept an independently supplied capture value plus unrelated bytes.

`WorkRef`'s type indices (`input`, dependent `output`) are not themselves serialized evidence. A graph decoder that reads existential node references needs schema identities resolved through a schema/type registry and a transport/equality witness showing the resolved input/output types are the expected ones. The spec says persisted refs include codec and schema identities (`implementation_spec.md:325-334`) but this missing typed existential-resolution mechanism is an open design point, not solved by `PackedWorkRef` alone.

### 3. State the codec theorem over registry lookup

The local fields in `codec`/`indexed_codec` already express suitable laws. P0 additionally needs a theorem tying those laws to durable lookup and canonical accepted bytes:

```fstar
val codec_resolve_exact : r:Registry -> id:CodecIdentity ->
  c:codec a -> Lemma
    (resolve_codec r id == Some (a, c, _) ==> c.codec_id == id)

val decode_resolved_indexed_exact : r:Registry ->
  id:CodecIdentity -> c:indexed_codec i o -> x:i -> b:Bytes -> y:o x ->
  Lemma (resolve_indexed_codec r id == Some (i, o, c, _) /\
         c.decode_indexed x b == Some y ==>
         b == c.encode_indexed x y)
```

Prove this by lookup soundness plus projection of `canonical_indexed`; indexed decode must be performed at the reconstructed, exact input `x`. Provide the analogous non-indexed codec theorem. `roundtrip` gives encode/decode for an inhabitant; `canonical` gives uniqueness of accepted encoding, not semantic authenticity of arbitrary external bytes. For external replies, authenticity comes from the pinned validator constructing `o x`, not from a codec accepting bytes.

Graph codecs must be registered as actual values, not just identities. Their resolver must tie identity to the indexed encode/decode implementation and its graph-reference resolver; the laws in `implementation_spec.md:292-302` must be proved for this selected value. The current `generator_ref` stores only `generator_output_codec:graph_codec_identity` (`Kernel.fst:103-107`), so it cannot itself establish this.

## Minimal lemmas sufficient for P0

Prove these as ordinary lemmas from the registry constructors and codec fields; do not put them in a top-level `assume`/opaque contract:

1. `identity_eqb_sound_complete`: structural identity comparison is equivalent to fieldwise identity equality.
2. `registry_unique`: every identity has at most one entry of its kind; constructors preserve uniqueness.
3. `resolve_sound`: successful lookup returns an entry whose complete key equals the requested key.
4. `resolve_complete`: every registered key resolves to its own entry; useful for graph decoding and registry extension.
5. `resolve_deterministic`: two successful lookups for the same key return the same registry entry (structural entry identity, not extensional function equality).
6. `capture_decode_exact`: resolved capture codec decodes the durable canonical capture bytes to the package capture, and canonicality makes those bytes unique.
7. `work_refinement`: resolving a `WorkRef i o` yields a `Work i o` of the exact input/output indices, work kind, identity, codec identities, and capture.
8. `indexed_codec_exact`: for that resolved codec and reconstructed input, accepted output bytes decode to the exact `o x`; canonicality follows from its codec proof.
9. `graph_codec_resolve_exact`: same result for graph bytes, with every embedded existential node/constant resolved through the same registry snapshot.
10. `identity_codec_canonical` (P0): combine 3–9. Do not state P0 by assuming it as a field of `Registry`.

The strongest modular shape is to let a user supply a *proved extension* `Registry n -> Registry (n+1)` and discharge its uniqueness/key/canonical-codec obligations at the extension site. Then P0 is proved once for the empty registry and preserved by extension induction. A library may add codecs and operations without changing kernel semantics.

## Equality and pinning pitfalls

| Risk | Why current shape is insufficient | Required rule |
|---|---|---|
| Digest collision | `digest = bytes` and no hash theorem (`Kernel.fst:6-7`). Equal digest does not imply equal code/codec. | Full structural key/manifest equality is semantic equality. Digest is only a bucket/index; on a hit, compare full key. If a digest is used as semantic equality, explicitly prove/assume collision resistance at the low-level host boundary and do not call P0 unconditional. |
| Same identity, two functions | Identity fields are adjacent to unconstrained functions (`Kernel.fst:43-80`). | Closed registry rejects duplicate structural keys; identity denotes the unique registry entry. Do not claim extensional function equality is decidable. |
| Wrong executable/durable pairing | `work_package` accepts any pair (`Kernel.fst:134-137`). | Remove free pairing; construct pinned package through `pin_work`, deriving its ref, or require a `ref_exact` proof. Resolver returns that package only. |
| Codec law versus codec selection | `roundtrip`/`canonical` prove facts about one record, not the codec named by journal bytes. | Resolve full codec identity first, obtain equality witness, then project law for that exact codec. |
| Dependent output | An output codec must decode `o x`, where `x` is the committed input, not just some output type with matching name. | Index resolver and decoder by the reconstructed `x`; journal replay checks the input binding before decoding. |
| Schema identity does not identify an F* type | Runtime bytes cannot carry F* type variables. | Add schema/type registry with typed existential package and equality transport, or choose a graph wire format that statically fixes node types. Prove the choice. |
| Executable versus durable ref | Functions, validators, generator closures, codecs and file/socket handles are not durable bytes. | Journal only first-order identity + canonical capture/config bytes + schema/codec IDs. Resolve after load under the same immutable registry snapshot. |
| Registry changes between restarts | Same textual name/version may point to new code. | `RunStarted` pins an immutable registry release/manifest; recovery must load that exact release or fail closed. Store/runtime preservation is a boundary obligation. |
| F* semantics versus extracted host code | Proving lookup returns an F* `run` value says nothing by itself about separately compiled OCaml/native code. | Add a concrete extraction/refinement theorem, or explicitly leave host execution as a named runtime premise. Do not hide it in “identity”. |
| Operation identity scope | `OpRef` identity currently sits beside `validate_reply`, but spec says it binds adapter, validator, configuration and schemas (`implementation_spec.md:111-123`). | Resolve one registered operation package containing request codec, validator, resume behavior/contract, capture/config, maximum charge and schema IDs. Stable `CallIntent` names that package. |

One subtlety: structural key equality alone does not prevent someone from registering two different functions under the same key. The *registry construction invariant* must reject duplicates and the registry must be immutable. This proves key-to-entry uniqueness. It still does not prove a claimed `code_build` matches source bytes unless the manifest/build process is itself verified; that is a separate extraction/pinning boundary.

## Event and action vocabulary for V2-01

V2-01 should declare the typed event/action surface before V2-03+ fills replay and runner semantics. The spec's intended minimum is already listed at `implementation_spec.md:577-625`; preserve those bindings rather than introducing a generic untyped `Event(bytes)` API:

```fstar
type graph_occurrence = RootGraph RunStartedId
  | ChildGraph GraphCommittedId
type node_occurrence = { graph:graph_occurrence; key:NodeKey }

type event =
  | RunStarted : pinned_run_header -> event
  | GraphCommitted : parent:graph_occurrence -> generator:node_occurrence ->
      exact_graph_ref -> canonical_input:Bytes -> bounds_split -> event
  | NodeCompleted : at:node_occurrence -> work:WorkRef i o ->
      input:Bytes -> output:canonical_output_ref -> event
  | CallIntent : at:node_occurrence -> call_key:CallKey ->
      operation:OperationIdentity -> request:Bytes -> resume:Bytes ->
      reserved_charge:nat -> event
  | CallOutcome : key:CallKey -> output:canonical_output_ref ->
      evidence:Bytes -> charge:nat -> event

type action =
  | Commit : event -> action
  | ExecuteLocal : node_occurrence -> action
  | Generate : node_occurrence -> action
  | DispatchOrResume : node_occurrence -> CallIntent -> action
```

These are signatures, not a complete transition system. Event constructors should be first-order journal meaning; `action` is volatile scheduling intent derived from replay state and is never persisted as authority. Before P3/P13, add proof-carrying authorization functions such as `authorize_local : State -> NodeOccurrence -> option (ResolvedCodeRef, TypedInput)` and `authorize_generator : ...`; only their returned exact packages may produce appendable completion/graph-commit events. `CallIntent` is itself persisted before `DispatchOrResume`; recovered action must carry the same intent and call key. `GraphCommitted` names the exact parent generator occurrence and input, then pins the graph codec and graph bytes. `NodeCompleted`/`CallOutcome` bind the exact occurrence, input index, output codec, and output bytes.

Avoid defining `Event` with F* closures or an existential `Work` value. Define a typed in-memory event/transition layer for proofs and a canonical first-order wire encoding; decoding must resolve its identities using the run's registry snapshot. The event identity/sequence/run/schema envelope and canonical encoding obligations come from `implementation_spec.md:577-581`.

## Principal blockers / strongest objection

1. **P0 is not presently a theorem target in code.** Current kernel has no registry or resolver; P0 currently appears only in the normative table. Adding a record with law fields and a `resolve` callback would still make P0 conditional on precisely the claim it is meant to prove.
2. **The “exact definitions” boundary cannot be eliminated by key structure.** F* can prove exact selection of a closed registry entry. It cannot infer that an external binary, plugin, or post-restart process loaded that same implementation from a label or digest. The build/release/extraction refinement must either be proved or remain an explicitly owned low-level premise. Consequently “P0 without any assumptions” is only achievable for the pure F* abstract registry, not for the full host deployment.
3. **Existential type resolution is the highest design risk.** Persisted arbitrary typed DAG nodes are existential packages, but a byte parser cannot manufacture `Type0` indices from identity strings. The schema/type registry and equality-transport protocol must be designed before claiming `GraphCodec` roundtrip of exact typed graphs.
4. **Registry mutability and version selection are durability inputs.** Even a perfect lookup theorem for a registry value says nothing about using the same value after a restart. The root event must bind a stable registry manifest, and store/runtime refinement must recover that exact snapshot or reject the run.
5. **Codec proofs do not validate external reality.** They show canonical representation of typed values. For external operation replies, validator soundness against the real compiler/network/service semantics remains operation-specific; P0 only proves the typed decoding/identity piece.

## Reproducible checking implications

The current configured command is:

```sh
cd /Users/alex/areas/productive/orchestration/src/fstar/v2
make verify
```

It checks only `src/WorkflowV2/Kernel.fst` into `/tmp/fstar-v2-check`; it currently cannot run here because `fstar.exe` is absent from `PATH`. Once V2-01 is implemented, extend `MODULES` in dependency order (identities/codec laws, registry, work-refinement, journal vocabulary, kernel integration) and check with `--cache_off`. Keep a closed-world P0 theorem in an importable module and ensure no `assume`, `admit`, opaque `resolve_sound`, or top-level registry-law field stands in for it. A separate extraction/runtime refinement module should own any unavoidable host premise. The identity audit can be accepted only after the actual F* checker discharges the P0 theorem and its dependencies under the repository's declared compiler/toolchain.
