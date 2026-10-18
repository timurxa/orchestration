# F* v2 proof-work state

**Active objective:** build and machine-check the full abstract workflow system
specified in [`../implementation_spec.md`](implementation_spec.md),
including its contracts, operational semantics, abstract theorem results, and
generic P13 refinement-transfer theorem. Concrete host-specific P13 instances
remain later work. The result will let later implementations inherit system
guarantees by proving their components refine these contracts.

**Execution status:** paused by the user at the A05c checkpoint. Resume from
the canonical DAG; completed nodes and source checkpoint are unchanged.
Synchronized pause-state commit: `750cb33`.

**Active DAG:** [`work_dag.md`](../../state/work_dag.md). It is the authoritative work
graph. A00, C0, A01, A02, A03, A05a, and A05b are complete; A05c is
`in_progress`; A05d–A05f, A05 integration acceptance, and all other nodes are
`not_started`.

## Current execution checkpoint — A05c

The verified codec and syntax-scope portion is closed as A05a. A05b closes
the exact base package interface: manifest owner identities select typed
packages with argument telescopes, carriers, codecs, indexes, and finite
equation declarations. Rule packages are a typed sum of Constructor and
IndexCall variants; the AST form must match. The law token is a checked
projection field, not a lookup key. The token and package shape do not prove
semantic adequacy. The staged law boundary and DAG revision are committed as
`28e23f3`. A05c defines canonical interpretation and typed judgments,
and must use exact matchers and lookups. A05d supplies an adequacy wrapper over
that same exact package map, including checked binder, result, equation, and
codec laws. Only the wrapper may flow into A05e/A05f and A06/A07/P0. A05e
proves semantic weakening/substitution; A05f establishes `LegalEnv` prefix
semantics. A06 remains blocked until A05 integration acceptance.

The first A05c source increment is in `WorkflowV2.SchemaJudgments.fst`. It
proves dependent argument-list alignment between AST declarations, actual
syntax expressions, a carrier telescope, and an explicitly indexed value
tuple; it also centralizes exact family/rule package selection and proves the
nullary-Atom matcher consequence. The full 13-module cache-off verifier passes
for this increment. This is verified scaffolding only: the value judgment is
still a parameter and its small example uses a placeholder relation. The
integrated source has no canonical interpretation or `JType`/`JValue`/
`JPredicate`; a paired context exists only in scratch. A05c remains active and
no downstream node may start. Commit and verifier evidence are recorded in
the latest run-log entry.
The partial source checkpoint is `9ba432b`; scratch evidence and limitations
are indexed in `research/A05-2026-10-14/typed_jvalue_scratch.md`.

At pause, root also independently cache-off verified
`/tmp/A05cContextLookup.fst`: carrier-indexed Bound lookup and Root/Port/
Constant/Pair plus equality/conjunction fragments pass. The base resolver is
arbitrary and does not establish declared-context typing, graph edge equality,
codec membership, Sigma/Refine, or package-backed semantics. A GADT context
storing each declaration's `JType` alongside its value is a candidate next
proof shape, not yet checked. A05c remains `in_progress`; project source is
unchanged since `202ab1e`, and the DAG remains authoritative and unchanged.

The latest scratch proof extends the carrier-only prototype: under a small
structural Nat/Vec relation, it checks paired syntax/runtime lookup for a
dependent `vec 4`/`nat` context and verifies built-in type/value rules for
unit, booleans, naturals, integers, products, sums, lists, and options (value
rules only for unit/bool/nat/int/products). This does not prove that a context
declaration's AST type matches its carrier, and it omits Sigma/Refine,
predicates, package-selected families/rules, and root/port/constants. It is
scratch-only; no A05c source acceptance or status changed. Exact command and
boundaries are in the research note and run log.

A second paired-context scratch, `ContextJValuePaired.fst`, stores each
declaration-prefix `JType` and value witness and derives the same-index
runtime bound path; its `Vec n`/`Nat` example verifies. A companion specialized
proof checks `Sigma Nat (Vec Bound(0))`. These do not prove general dependent
weakening: the selected type proof remains at the declaration prefix. The
general bridge is still A05e, and package-selected interpretations remain
open in A05c.

Latest source refinement: the argument-scaffold relation now returns an
evidence type in `Type`, and its comment explicitly says it has no context
parameter; the example is still a placeholder, so this does not instantiate a
canonical judgment. The full 13-module cache-off verifier passes. Scratch
research found a structurally recursive `JType`/`JValue` family that proves a
Nat/Sigma fragment using the existing `dtuple2` carrier. Inductive Sigma
constructors with quantified recursive premises fail F* universe checking.
Type-valued judgment evidence is not automatically a `prop`; native
`Refine` therefore needs a separate proposition-valued predicate denotation
and a sound bridge from typed values. No full context, package, or predicate
semantics is integrated; A05c remains active. Exact commands and boundaries
are in the newest run-log entry and
`research/A05-2026-10-14/typed_jvalue_scratch.md`.
The source and synchronized proof-state checkpoint is commit `8c0dcc7`;
A05c remains in progress.

The canonicality requirement is settled. The selected integration route is
the dependent existential `a:Type0 & shape rho t a`: the witness is indexed
by its exact carrier, with no separate equality field. It imports production
`SchemaSemantics.hlist`, verifies Nat/Sigma construction and elimination, and
passes a separate abstract `.fsti` client. The package family uses `Type
u#1`, while its carrier remains `Type0`; raising the package family from the
smaller universe avoids an earlier universe error. A private JValue GADT,
exposed as an abstract `Type u#1` family via a `let` alias, plus smart
carrier builders and eliminators, verifies a separate client for Sigma and
`SchemaRefine ... SchemaTrue`. Exposing the GADT directly as an abstract
`val` fails Error 197. Shape-only toy Sigma/Refine and client fragments
also verify, but the Kernel-AST Refine probe with a locally modeled dependent
context fails to expose its native subset carrier. This does not weaken
Refine or the exact-package invariant. A newer production-context scratch
proves one nontrivial dependent refinement: in a Sigma pair, the second
component is `{x:nat | x == n}`, and a specialized AST evaluator proves the
two bound expressions compare equal for inhabitants of that carrier. A
separate actual-Kernel shape/JValue scratch covers Unit, Bool, Nat, Int,
Product, Sum, List, and Option, but does not interpret package-selected
constructors or prove general soundness. These results do not yet establish
the generic predicate evaluator or a canonical source module. The direct recursive
`TypeDenote : AST -> Type` route remains rejected. Other verified scratch
includes Nat/Sigma/VecBound0, Nat/Refine introduction/elimination, and
selected-codec injectivity at one exact package/index. None is integrated
source or proves package-selected dependent VecBound0 through the public interface, generic Refine
predicates, full AST/package cases, general predicate soundness, or all AST
constructors. A05c remains active. Details,
commands, and limitations are synchronized in the DAG, node summary, run log,
and A05 scratch note.

A separate equality probe verifies plain and indexed codec reflection when
both operands share one exact package/carrier and exact index. A further
probe uses the exact `schema_family_package.family_codec` and proves its
indexed roundtrip reflection; a package lookup helper threads one selected
family object through one continuation. The remaining integration obligation
is to derive that same package and argument index from the `SchemaFamily` AST,
then share that existential across both operand judgments. Latest synchronized
research checkpoint: `6cee517`.

### Latest A05c proof-shape findings

Cache-off scratch proofs confirm two implementation choices. First, the
native `Refine` subset predicate must be defined independently from the
mutually indexed `JValue`/`JPredicate` evidence families; defining the subset
carrier from the evidence family triggers F* strict positivity. The separate
proposition-valued predicate route verifies for builtins and `SchemaTrue`,
and a separate Nat-literal `Equal`/`And` GADT proves fragment-level predicate
soundness; generic AST predicate semantics and its soundness bridge remain
open. Second, family binder/carrier alignment is a recursive package-level
adequacy law: each binder is typed at its prefix and every later binder under
extension by each value of the exact carrier. A Nat `SchemaBound 0` example
derives the exact dependent family index. An import-order audit found that
A05c cannot consume this proof because A05d depends on A05c. The DAG now
separates the alignment-law interface in A05c, proof-bearing exact-map law
fields in A05d, semantic substitution in A05e, and automatic call-site
derivation in A05g. This alignment requirement applies to family,
constructor, and index-call arguments. The wrapper also carries constructor
AST-result-index equality and exact codec schema/carrier coherence: without
them a constructor callback can return a value indexed differently from the
AST result, and registry membership/roundtrip alone does not tie codec
schemas to carriers. Raw package fields and tokens alone cannot imply these
laws; the wrapper carries these proved contracts. No
per-use author proof is added. A05f follows the closed judgments. These are
scratch proofs only; A05c remains `in_progress`. Exact commands, limitations,
and failed attempts are synchronized in the DAG, run log, node summary, and
A05 research note. No project source changed. The previous synchronized
research checkpoint is `e21a9f2`; the DAG correction is committed as
`3d11410` (`docs(fstar): correct schema adequacy proof order`), and the
result-index/codec coherence refinement as `cec8cd6`. A first conditional
family-type judgment is now integrated and full-build verified; it still uses
the placeholder value relation and requires call-site evidence, so A05c stays
active. Source/evidence commit `202ab1e` is pinned below.

Predicate research has a viable partial representation: a Type-valued
`PTrue`/`PEqual`/`PAnd` evidence GADT, wrapped once as
`PredDenote = squash predicate_evidence`. The equality constructor carries
both typed operands at one shared carrier. Nat equality and conjunction
verify, but the scratch uses native equality rather than the exact
manifest-selected codec and does not prove codec equality reflection. The
direct recursive `TypeDenote` projection still fails to convert
`SchemaRefine` to its native subset carrier. However, a separate
canonical-package Nat/Refine fragment verifies subset introduction and
elimination when `JRefine` consumes the exact package also used by its base
`JValue`; this resolves the fragment, not general predicate soundness. An
AST-indexed abstract `.fsti` package with a private `noeq` implementation
also verifies. An unindexed handle is insufficient. The dependent-existential
package type family now verifies with production context and a separate
client for Nat/Sigma, but general Refine, AST-derived exact package codecs in the judgment, all AST
cases, and general soundness remain open; A05c stays in progress.
Evidence and commands are in the A05c research note and latest run log.

Latest A05c evidence: root independently verified a combined production-context
Sigma/`Vec n`/subset-refinement fragment under `SchemaSemantics.hlist`, then
reran the full 13-module source verifier cache-off before integration. Both
checks discharge all VCs. The scratch hardcodes family semantics and does not
select the exact family package or codec; the baseline checks existing source
only. A source audit recommends one exact package shared across AST
denotation, judgments, and codec reflection, with explicit carrier builders
and eliminators behind an abstract `.fsti`. A05c remains open: context
alignment, AST-derived package/index selection, full predicate semantics,
constructor/index-call adequacy, all AST constructors, structural termination,
and generic soundness must be proved in source. Latest synchronized research
checkpoint starts at `5b42a90`.
The latest combined-shape evidence commit is `7428189`; this hash is pinned
by the current state-record update.

`WorkflowV2.SchemaPackages.fst` now defines the first source package-map
interface. Packages project exact family/rule owner rows and their law tokens,
use an arity-indexed dependent carrier telescope, expose a typed
Constructor/IndexCall sum, and carry membership for their exact indexed codec
object in the shared codec registry. `SchemaAtom` is restricted to an empty
argument telescope; `SchemaFamily` uses the same declared arity, including
zero. Constructor application is routed through the exact `family_at` result.
Manifest bytes remain unchanged; A04/P0 binds the shared codec registry and
the package map to the exact canonical manifest and restart-stable lookup.
This verified source increment is committed as
`e70c0ce01dfb8006c6386cb39a559023bd99d547`; A05b is complete as the base
interface stage.

The full configured cache-off verifier passed after this increment:
`opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05b-codec-membership-final
FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'`. All 12
modules verified and all VCs discharged; pre-existing GraphCodec warning 328
remains. This interface increment does not yet prove binder-by-binder
AST/carrier typing, package denotation/equation adequacy, semantic
substitution, or `LegalEnv`. Those are A05c–A05f; A05b is closed as the base
interface stage after the final audit. Scratch-only prototypes do not count as
source theorems.

This current checkpoint supersedes older progress paragraphs below whenever
they describe an earlier codec or semantics status. Those entries remain as
provenance, not as the current source-of-truth status.

## Intention and boundaries

The abstract system provides total pure local work, nondeterministic external
operations, and pure generation of arbitrary finite typed node DAGs. The
canonical journal is durable state; replay recovers its exact committed
prefix. The abstract executor may run independent ready local/generator nodes
concurrently, the adapter may keep distinct calls in flight, and the journaler
remains serial. The proofs cover static dependent edge compatibility,
provenance, authorization, all permitted schedules, every crash cut, reuse of
committed work, and conditional progress.

The plan is for the abstract verified system and a generic concrete-refinement
interface/theorem. It does not include a SQLite/filesystem journaler, a real
CLI/network adapter, an extracted runner, or a concrete scheduler instance.
Those implementations will have a later DAG and will need to prove their
service instances satisfy the contracts here.

Proofs are required, not a burden to evade. No system theorem may rely on
`assume`/`admit`; contract inputs are explicit records carrying laws. Proof
examples support expressibility but do not replace generic theorems or run as
a test-only substitute.

**A03 proof status:** complete in commit `09ed6ea`. Constructive
insertion sort proves sortedness/count preservation, unique sorted
representatives, permutation invariance, and canonicalization idempotence. The
older `38f8e62` snapshot used Classical/Squash to build `total_order`, so it was
preserved as provenance but replaced. `--report_assumes` is diagnostic only:
cache-off fails even for a trivial lemma at `Prims.admit`, while cached strict
reporting passes both old and new source. The scoped Kernel/ManifestCore trust
audit checked imported List.Tot helper bodies and found no project-owned
admission, unchecked declaration, or admitted helper in this path. Identity
tokens are represented as `bytes = list nat`; the kernel promises no host
text, Unicode, UTF-8, or octet encoding. Artifact reference-codec schema
equality is part of manifest canonicality. Contract-slot/package binding is
A04/P0, and schema AST parsing/canonicality is A05. No P0 claim is made.

The graph typing boundary is the manifest-pinned `SchemaSupported` language.
Its schema AST is an F* datatype encoding of the workflow's own restricted
schema DSL, not the F* compiler AST or arbitrary `Type0` reflection. Edge
equality is proved from declared types and static graph constraints for every
legal environment; runtime outputs never rescue an ill-typed edge.

**A05 clarification:** independent review found that schema `Refine(T,P)`
lacked an explicit candidate-value binder even though its intended meaning is
a subset of `T`. The normative spec and A05 contract now state that `P` is
checked under the exact candidate binder, parallel to `Sigma`'s codomain
binder. This changes no AST constructor or universal graph-edge quantifier.
The decision and preserved claims are in
[`research/A05-2026-10-14/refinement_binder_resolution.md`](../research/A05-2026-10-14/refinement_binder_resolution.md).
The contract clarification is committed as `b947175`; A05 remains
`in_progress`.
The implementation packet now splits A05 into codec, scope, and semantics
modules so the proof responsibilities remain separate and import direction is
clear. `WorkflowV2.SchemaScope.fst` is now integrated into the configured
Makefile and verifies scope, lifting, and capture-avoiding substitution
preservation for values, argument lists, predicates, and types. It includes
the singleton-refinement, free-bound rejection, and nested Sigma/Refine
substitution examples. The partial source milestone is committed as `0ace03d`.
It now also proves pointwise substitution congruence, identity, composition,
and lift/substitution commutation across values, predicates, and types,
including both binders. Full configured verification passed again. A05 remains
in progress. The codec currently has all-constructor encoders/parsers and
guarded accepted-byte canonicality, but generic roundtrip/injectivity remain
open. Denotation, exact manifest packages, and `LegalEnv` also remain open. See
the A05 progress entry in
[`node_summaries.md`](../history/node_summaries.md) and the latest [`run_log.md`](../history/run_log.md)
entry. The codec and syntax-law follow-up is committed as `1cc76f4`
(`feat(fstar): add schema codec and substitution laws`).

Further A05 scratch research is recorded in
[`research/A05-2026-10-14/semantic_model_prototype_audit.md`](../research/A05-2026-10-14/semantic_model_prototype_audit.md).
The relational semantics direction verifies in scratch, including a corrected
constructor result indexed into its exact parent family and a closed
Sigma/Refine transport example. These prototypes are not integrated: manifest
row provenance, typed `Bound` context, root/port/constant semantics, general
substitution, context-fact generation, and `LegalEnv` remain open. Codec
framing is also only an active comparison; the committed source still lacks
generic AST roundtrip and injectivity. A05 remains `in_progress`, with no
downstream work started. The synchronized research-state checkpoint is
committed as `2abdf9a`; it changes no F* source. Its hash-recording follow-up
is `aa0e076`. The framed codec scratch has not verified: its recursive fuel
equation triggers an F* internal `</labels>` parse failure; a case-split
rewrite leaves a failed postcondition. A claimed module-shaped-path success
was invalid because it did not load the matching module. See
[`research/A05-2026-10-14/codec_proof_attempts.md`](../research/A05-2026-10-14/codec_proof_attempts.md).
The scratch worker also verified local child/int/pair lemmas and a fixed-fuel
root suffix case; these do not prove symbolic recursive decoding.
The correction and exact scratch evidence are committed as `91f3e47`.
The next codec approach verifies a mutual suffix grammar for every Kernel
schema AST constructor, but has not yet been linked to the executable
encoders/decoders. Its proof route and open obligations are in
[`research/A05-2026-10-14/codec_proof_attempts.md`](../research/A05-2026-10-14/codec_proof_attempts.md).
The synchronized grammar research checkpoint is `6e0020c`.

**Historical A05 source foundation:** `WorkflowV2.SchemaSemantics.fst` was added to
the configured Makefile. It proves canonical-manifest family-row selection
and uniqueness facts, exact schema-row AST/law extraction, root-indexed
constant carriers, and a generic full-output-family prefix kernel. These
helpers compile, but they are not yet the AST-linked `Bound`/`Sigma`/`Refine`
semantics or graph `LegalEnv`. A reviewer found that a carrier-only context
does not itself establish that its carriers denote the declared schema ASTs;
the source comments/API now mark this boundary explicitly. Independent scratch
research produced a single indexed-derivation design that ties context slots
to declared schemas and supports dependent type families; it is under review
before source integration. See the current A05 entries in
[`node_summaries.md`](../history/node_summaries.md) and [`run_log.md`](../history/run_log.md).
The complete configured verifier now checks eleven modules, including this
partial module; the full cache-off build passes all VCs. The partial source
foundation is preserved in commit `d8b6f006ecceb37f2de5f2bb50e169a4a8f4ca5b`
(`feat(fstar): add schema semantics foundation`). This is a progress
checkpoint, not A05 completion. No A05 or downstream theorem is claimed
complete.

**A05 row-selection extension:** family and rule rows now share one
owner-tagged schema parser; rule rows have the same exact selection,
uniqueness, expression and law projections as family rows. This progress is
committed as `c0696b8f16b0ce1ea74d861e9e534afefe08fd19`. The full eleven-module
cache-off verifier passes after this change; evidence is in `run_log.md`.

**Earlier semantic counterexample:** a prototype with caller-supplied
predicate evaluation made `SchemaFalse` an inhabited refinement, and its type
judgments did not require context well-formedness. Do not use that prototype.
The latest scratch replaces the oracle with bounded structural evaluation and
`context_wf`; it verifies only a subset, as summarized below. Exact manifest
packages, full AST denotation, context admissibility, completeness, and
`LegalEnv` remain open. The research audit records the counterexample and the
corrected architecture.

**Historical codec integration failure — superseded:** an earlier attempt to
integrate the unframed codec proof failed under the flat module path and was
removed. The later callback-free parser and all-constructor roundtrip proofs
were integrated and verified in commit `115fd0bf057f403c32ceeeba57c615b1385de381`.
The failed attempts remain useful provenance in `run_log.md` and
`research/A05-2026-10-14/codec_proof_attempts.md`; they do not describe the
current source.

Latest synchronized A05 evidence correction is committed as
`e34c425` (`docs(fstar): correct A05 proof integration status`). This is a
documentation checkpoint only; A05 remains in progress and the full source
baseline described above is unchanged.

**Current A05 increment:** `SchemaSemantics.fst` now proves that a selected
family row's decoded schema AST and denotation-law token are projections of
the same exact manifest row. The configured cache-off verifier passed all
eleven modules under F* 2026.03.24 / Z3 4.13.3; only the pre-existing unused
recursive `GraphCodec.nodes_decode_encoding` warning remains. This is a
partial row-coherence fact, not a package-token lookup, carrier-denotation,
`LegalEnv`, or graph-semantic theorem. A scratch token-indexed package bridge
also verifies, but admits a vacuous `False` carrier, demonstrating that exact
token linkage and soundness alone do not establish denotation adequacy.

The `SchemaCodec` subpart is now integrated and proved in the configured
source. Callback-free, fuel-bounded parsers preserve the existing unframed
wire tags and encoder clauses. For Value, Predicate, and Type ASTs, checked
lemmas establish suffix/public decode-encode roundtrip, encoder injectivity,
and rejection of nonempty trailing bytes. Full 11-module cache-off
verification with `--split_queries always` passes under F* 2026.03.24 / Z3
4.13.3. Only existing GraphCodec warning 328 remains. A05 is still
`in_progress`: typed denotation, exact package adequacy, semantic substitution,
and full-prefix `LegalEnv` remain open. No dependent node has started. Exact
commands and limits are in the A05 node summary, run log, and codec research
record. Integrated codec source and synchronized status committed as `115fd0bf057f403c32ceeeba57c615b1385de381`
(`feat(fstar): prove schema codec laws`).
This source and synchronized state increment is committed as `1f98f8a`
(`feat(fstar): prove schema row component coherence`); A05 remains open.

**Latest semantics scratch:** `/tmp/A05SoundNucleus.fst` replaces the
unconstrained predicate oracle with bounded structural evaluation and a paired
typed context, then adds Product/Sum/List/Option carrier representations and a
locally nameless substitution regression. Its supported value/predicate
evaluation and `value_typed_sound` lemmas verify. It remains incomplete: List
is rejected by `type_accepts`, Kernel has no Sum/List/Option value constructors,
and no general theorem relates carrier interpretation to AST denotation or
acceptance. No source integration or A05 acceptance is claimed. Exact command
and limits are in
[`research/A05-2026-10-14/semantic_model_prototype_audit.md`](../research/A05-2026-10-14/semantic_model_prototype_audit.md).
Verifier recheck evidence is recorded in commit `4aded38`.

**Latest A05 semantic source increment:** `SchemaSemantics.fst` now proves
plain-codec and same-index indexed-codec encoding injectivity directly from
the roundtrip contracts. The full configured 11-module cache-off verifier
passes; source/state commit is
`a3fea7abe26af6478c9f4d4b6d2b66154103a814`. Details and the exact command are in `node_summaries.md`,
`run_log.md`, and
[`research/A05-2026-10-14/codec_equality_and_typed_substitution.md`](../research/A05-2026-10-14/codec_equality_and_typed_substitution.md).
This provides a sound equality bridge only after a static derivation
establishes that both schema value expressions use the same exact carrier and
index. Current scratch designs with arbitrary `atom_view`/`family_view`
observers are unsound unless their views reflect codec equality. A relational
substitution proof handles Sigma/Refine candidate cases without function
extensionality, but the current contexts still do not prove that substituted
bindings inhabit their substituted declaration types. Exact package
semantics, typed local/graph contexts, substitution well-formedness, and
`LegalEnv` remain open; A05 remains `in_progress`.

## Normative and planning documents

- [`../implementation_spec.md`](implementation_spec.md): normative API,
  abstract execution, durability, recovery, and P0–P16 theorem contracts.
- [`../key_correctness_theorems.md`](key_correctness_theorems.md): theorem
  explanations, especially universal dependent-edge correctness and recovered
  semantic graph correctness.
- [`../implementation_packet.md`](implementation_packet.md): proposed
  source-module ownership, proof order, signatures, and acceptance checklist;
  subordinate to the spec and active DAG.
- [`work_dag.md`](../../state/work_dag.md): all future implementation/proof work,
  autonomous ambiguity handling, and required commit checkpoints.
- [`node_summaries.md`](../history/node_summaries.md): historical S2 planning records;
  new A00–C6 summaries are added only after a node actually starts.
- [`run_log.md`](../history/run_log.md): append-only history, including this
  plan-only transition.
- [`research/registry.md`](../research/registry.md): previous design provenance
  and the current DAG planning audits.
- [`research/A00-2026-10-13/source_refactor_map.md`](../research/A00-2026-10-13/source_refactor_map.md):
  integrated source disposition, architecture decisions, alternatives, and
  next proof questions from A00.
- [`research/A01-2026-10-13/task_brief.md`](../research/A01-2026-10-13/task_brief.md):
  A01 acceptance brief and assignment evidence.
- [`research/A01-2026-10-13/module_boundary_design.md`](../research/A01-2026-10-13/module_boundary_design.md):
  accepted module/trust boundary; resolves generator law ownership and updates
  A04/A16 order without weakening P0.
- [`research/A02-2026-10-14/task_brief.md`](../research/A02-2026-10-14/task_brief.md):
  current kernel API/proof acceptance and independent review assignments.
- [`research/A02-2026-10-14/approach_registry.md`](../research/A02-2026-10-14/approach_registry.md):
  delegated A02 approaches and review status.
- [`research/A03-2026-10-14/task_brief.md`](../research/A03-2026-10-14/task_brief.md):
  active canonical manifest and identity proof work.
- [`research/A03-2026-10-14/approach_registry.md`](../research/A03-2026-10-14/approach_registry.md):
  independent A03 design/proof reviews and integration status.
- [`research/A03-2026-10-14/proof_feasibility_review.md`](../research/A03-2026-10-14/proof_feasibility_review.md):
  checked scratch proofs for tagged decoder inversion and sorting patterns.
- [`research/A03-2026-10-14/stdlib_axiom_audit.md`](../research/A03-2026-10-14/stdlib_axiom_audit.md):
  initial Classical/Squash proof-path audit, strict-mode experiments, and the
  accepted constructive proof/trust boundary.
- [`research/A03-2026-10-14/acceptance_audit.md`](../research/A03-2026-10-14/acceptance_audit.md):
  independent A03 completeness matrix, gaps, and their A03/A04/A05 ownership.
- [`research/A05-2026-10-14/task_brief.md`](../research/A05-2026-10-14/task_brief.md):
  active A05 contract, proof targets, and independent review assignments.
- [`research/A05-2026-10-14/approach_registry.md`](../research/A05-2026-10-14/approach_registry.md):
  delegated A05 proof approaches, reviewer findings, and integration status.
- [`research/A05-2026-10-14/refinement_binder_resolution.md`](../research/A05-2026-10-14/refinement_binder_resolution.md):
  normative resolution of the missing `Refine` candidate binder found during
  A05 contract review.
- [`legacy_v2_work_dag.md`](legacy_v2_work_dag.md): old V2 DAG retained for
  historical provenance only; it cannot authorize work.

## Current source baseline

The existing eight `.fst` modules are partial source evidence, not P0–P16
proofs. `Graph.fst` contains admitted builder laws, `GraphCodec.fst` proves
syntax encoding rather than typed reconstruction, and `Journal.fst` defines
event vocabulary without replay or durable-store semantics. The generator
chain is an example, not generic builder or generator proof. The full Makefile
verification passed in A00 under F* 2026.03.24/Z3 4.13.3; this does not
discharge the source's `assume`/`admit` boundaries. See the [source
inventory](../research/A00-2026-10-13/source_inventory.md) and [integrated refactor
map](../research/A00-2026-10-13/source_refactor_map.md).

## State protocol

Only an explicit user instruction starts execution. Once started, proceed
autonomously through all DAG nodes; C0–C6 are commit checkpoints and never wait
for human review. Before starting a node, record it in `run_log.md`; on
completion, record its artifact, verification evidence, commit hash where
applicable, and remaining obligations in `node_summaries.md`, then update the
node status here and in `work_dag.md`. At each C checkpoint, ensure the
completed milestone is committed before its dependents begin; do not create an
empty commit when safe per-node commits already cover it. Make additional
commits after serial nodes or before replacing a coherent approach when safe;
let parallel work finish and join before committing shared changes.

When implementation or proof work reveals ambiguity, difficulty, or a DAG
mismatch, research and reconcile it while the project intention and theorem
strength can be preserved. Update the DAG and this state file before affected
dependents proceed, and log the reason, evidence, changed acceptance/dependency
and commit. Do not silently weaken correctness claims. If the intended
resolution cannot be determined from the specification and project history,
isolate that branch, continue independent work, and ask only about the
irreducible decision. Keep the diagram, table, state, summaries, and run log
consistent. A plan, source resemblance, or contract declaration is not proof
completion.

**Current execution status:** A00, C0, A01, A02, A03, A05a, and A05b are
`complete`; A05c is `in_progress`; later nodes are `not_started`. C0 records A00 commit
`62b5a5f`; A01
documentation is committed as `34e1021`; the A02 audit kickoff is committed as
`edf0b0f`, and A02 source completion is committed as `bb4d8ae`. A03 kickoff
is committed as `94e6a62`; shared identity-codec migration is committed as
`e88e1b8`; proof-design evidence is committed as `528eeb2`; A03 ManifestCore
source and proofs are committed as `09ed6ea` after the final eight-module
verification. The specification and packet require exact
identity-to-generator-package reload association. A02 added checked Kernel
vocabulary and updated legacy generator call sites. A03's final eight-module
verification passes; no P0–P16 system theorem is yet claimed and legacy
admissions remain outside the A03 trust path.
