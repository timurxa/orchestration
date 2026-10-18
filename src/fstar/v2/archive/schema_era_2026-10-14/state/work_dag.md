# V2 abstract-system proof DAG

**Status: paused at the user's request after A05c scratch verification.** This replaces the prior S2 specification-planning DAG
as the active plan. A00, C0, A01, A02, A03, A05a, and A05b are complete; A05c
is in progress; later nodes remain `not_started`.
The synchronized pause-state commit is `750cb33`.

## Objective and authority

Build the **fully proved abstract F* workflow system** specified in
[`implementation_spec.md`](../implementation_spec.md), with
[`key_correctness_theorems.md`](../key_correctness_theorems.md) as the guide
to the semantic graph and recovery burdens. Prove all abstract-system theorem
targets and the generic P13 refinement-transfer theorem. A host-specific P13
instance remains later work. The
[`implementation_packet.md`](../implementation_packet.md) proposes module
ownership and proof ordering but is subordinate to the specification.

The result is an abstract system parameterized by constructed,
proof-bearing contracts for pinned work/codecs, the serial journaler, the
possibly concurrent local/generator executor, and the multi-inflight adapter.
It proves the abstract system's safety, durability, graph typing, recovery,
and conditional liveness theorems. It does not implement SQLite/filesystem,
process/network adapters, an extracted runner, or a concrete scheduler.
Instead it defines the refinement interface and proves the generic transfer
theorem that a future implementation can instantiate with its own simulation
proofs. A later concrete implementation task must prove those instances.

The three executable work forms are total pure local `Work`, fallible and
possibly nondeterministic external `Work`, and pure runtime graph generation.
Root and generated graphs share the same supported graph language, resolver,
typed-edge theorem, journal events, and recovery. Independent ready local and
generator work may execute concurrently; distinct adapter calls may be
in-flight together; journal append remains serial under one run coordinator.
Committed local results and graph descriptions are reused after recovery.

**Proof rule:** every applicable P0–P16 result must be a checked F* theorem
from definitions and explicit contract records whose laws are themselves
proof fields. No theorem path may use `assume`, `admit`, a sampled execution,
or a test as a proof. Conditional host/remote laws remain explicit premises.
Examples are proof-bearing constructions and do not replace the generic
theorems.

**Schema AST clarification:** this is the workflow's own restricted,
manifest-pinned schema-expression AST, with an F* datatype encoding,
denotation, and proved equality/checking calculus. It is not the F* compiler
AST, quotation, arbitrary `Type0` reflection, or an unchecked SMT callback.
P1/P2 completeness is exactly for `SchemaSupported`. A direct edge is
accepted only when its producer/consumer types agree in every legal graph
environment from static declarations. Thus unconstrained `vector n` cannot
feed `vector 3` merely because one run produced length 3.

## DAG operating rules

1. This table is the sole execution authority. An edge `A -> B` means B
   cannot start until A is complete. Mermaid is a high-level view; every edge
   in the detailed table binds even when omitted from that diagram.
2. Once execution is explicitly started, proceed autonomously through the
   graph. The C0–C6 nodes are commit checkpoints, not human-review gates; they
   do not wait for a user response. Preserve the former review points as
   inspectable Git commits so the user can review or revert a coherent state
   later.
3. At each C node, ensure the completed milestone is covered by a scoped Git
   commit before starting its dependents; if safe per-node commits already
   cover it, record those hashes instead of creating an empty commit. Also
   commit a completed serial node sooner when its outputs are coherent and no
   parallel node has uncommitted work that could be swept into that commit.
   Let independent nodes run in parallel; when their work shares the Git index
   or a working tree, wait for the relevant join and commit the complete group
   together. Before replacing a coherent approach with a substantial redesign,
   preserve the old artifacts and decision evidence in a scoped commit when
   safe. Record each commit hash in the node summary and run log. Stage only
   intended project files; do not include generated artifacts, secrets, or
   unrelated user changes.
4. If work reveals ambiguity, a failed proof approach, or a mismatch between
   the DAG and the actual proof dependencies, investigate alternatives and
   continue while the project intention can be preserved. Update the DAG
   before proceeding on affected dependents; keep its objective, theorem
   strength, and core contracts aligned with the implementation spec. Record
   the reason, evidence, changed dependencies/acceptance, and commit hash in
   `run_log.md` and `node_summaries.md`. Do not silently weaken a theorem or
   hide an unresolved premise. If the intention cannot be determined
   faithfully from the spec and project history, isolate that branch, continue
   independent work, and ask the user only about the irreducible decision.
5. The first node is a read-only inventory of existing v2 source and the
   precise refactor map. Existing declarations/examples are not credited as
   P0–P16 proofs without checking their theorem path.
6. A theorem node completes only when its F* declaration/proof is in the
   source, its project-owned proof path has no `assume`, `admit`, unchecked
   application declaration, or helper theorem whose implementation uses an
   admission, the project full-check command passes, and evidence is recorded
   in `node_summaries.md`. The F* checker, logical prelude, and SMT solver are
   the explicit trusted base. Audit imported proof helpers by source and
   call-path; `--report_assumes` alone is not an acceptance oracle because its
   cache-off mode reports the F* core admission even for a trivial lemma, and
   its cached mode did not flag the old Classical/Squash path.
   Proof-interface stubs do not count as completion.
7. Contract nodes define explicit records and law fields. The abstract
   theorems must be proved generically from those fields; a contract is not a
   hidden axiom. Concrete instances of journaler, adapter, executor, compiler,
   extraction, or artifact store are outside this DAG.
8. Safety never assumes fairness. P10 (journaler prefix law) is distinct from
   P15 (abstract authorization across schedules); `StateWF` is distinct from
   semantic-origin `SemWF`; P16 explicitly consumes P5 exact graph recovery.
9. The final verifier run checks the complete module set. Do not add a test
   suite as a substitute for proof; the examples are F* proof witnesses.

## High-level proof spine

~~~mermaid
flowchart TD
  A00["A00 Source audit"] --> C0["C0 Commit source audit"] --> A01["A01 Module/API boundary"]
  A01 --> A02["A02 Kernel signatures"]
  A02 --> A03["A03 Manifest core"]
  A03 --> A05a["A05a Codec and scope laws"]
  A05a --> A05b["A05b Exact package interfaces"]
  A05b --> A05c["A05c Canonical denotation and judgments"]
  A05c --> A05d["A05d Package adequacy"]
  A05a --> A05e["A05e Semantic weakening/substitution"]
  A05d --> A05e
  A05d --> A05g["A05g Schema call-site closure"]
  A05e --> A05g
  A05g --> A05f["A05f LegalEnv prefix semantics"]
  A05a --> A05["A05 Integration acceptance"]
  A05b --> A05
  A05c --> A05
  A05d --> A05
  A05e --> A05
  A05f --> A05
  A05g --> A05
  A05 --> A06["A06 Equality calculus"]
  A06 --> A07["A07 Resolver/edge theorem"]
  A07 --> A15["A15 Allocation model"]
  A15 --> A16["A16 Generator package law"]
  A16 --> A04["A04 Bundle coherence: P0"]
  A03 --> A04
  A04 --> C1["C1 Commit identity/contracts"]
  C1 --> A08["A08 Builder completeness: P1"]
  A16 --> A08["A08 Builder completeness: P1"]
  A07 --> A08
  C1 --> A09["A09 Graph syntax codec"]
  A08 --> A10["A10 Typed decode: P2"]
  A09 --> A10
  A10 --> C2["C2 Commit typed graph"]
  C2 --> A11["A11 Journal transition model"]
  A11 --> A12["A12 Event/journal codecs"]
  A12 --> A13["A13 Replay/WF: P3"]
  A13 --> C3["C3 Commit replay model"]
  C3 --> A14["A14 Semantic witnesses"]
  C3 --> A20["A20 Adapter keyed contract"]
  C3 --> A23["A23 Optional resource identity: P9"]
  C3 --> A24["A24 Serial journaler contract"]
  A16 --> A17["A17 Typed splice"]
  A17 --> A18["A18 Authorized graph commit: P4"]
  A14 --> A18
  A13 --> A19["A19 Local provenance: P6"]
  A14 --> A19
  A20 --> A21["A21 Adapter theorem: P7"]
  A18 --> A22["A22 Ledgers: P8"]
  A21 --> A22
  A24 --> A25["A25 Every-cut durability: P10"]
  A18 --> A26["A26 Exact generated recovery: P5"]
  A25 --> A26
  A18 --> C4["C4 Commit provenance/durability"]
  A19 --> C4
  A21 --> C4
  A22 --> C4
  A23 --> C4
  A25 --> C4
  A26 --> C4
  C4 --> A27["A27 Abstract services/controller"]
  A19 --> A27
  A21 --> A27
  A22 --> A27
  A27 --> A28["A28 Ready input/claim lemmas"]
  A28 --> A29["A29 All-schedule safety: P15"]
  A29 --> A30["A30 Frontier: P11"]
  A29 --> C5["C5 Commit safety/progress"]
  A30 --> C5
  A31 --> C5
  C5 --> A32["A32 Recovered semantics: P16"]
  C5 --> A33["A33 Generic refinement: P13"]
  A22 --> A31["A31 Rank: P12"]
  A19 --> A31
  A26 --> A30
  A26 --> A31
  A26 --> A32
  A19 --> A32
  A21 --> A32
  A22 --> A32
  A23 -. "only if persistent resource identity claimed" .-> A29
  A23 -. "only if persistent resource identity claimed" .-> A32
  A33 --> A34["A34 Conditional termination: P14"]
  A32 --> A35["A35 Proof-bearing workflows"]
  A34 --> A35
  A35 --> A36["A36 Integrated proof/trust audit"]
  A36 --> C6["C6 Commit verified abstract system"]
~~~

The detailed table is authoritative for all inputs, including shared P0/P1/P2
prerequisites omitted from the compact diagram. Dashed P9 edges are conditional
extensions, not prerequisites for the opaque-reference base theorem.

## Detailed nodes

Statuses are per row: A00, C0, A01, A02, A03, A05a, and A05b are `complete`;
A05c is `in_progress`; A05d–A05g, A05 integration acceptance, and all
remaining nodes are `not_started`. `P` labels identify theorem
targets from the normative spec; a node may prepare definitions before its
theorem is proved.

Current A05b source checkpoint: `e70c0ce01dfb8006c6386cb39a559023bd99d547`
adds the package interface and passes the full 12-module cache-off verifier.
A05b is closed as the base-data interface stage. A05c must enforce the exact
package matchers and lookup path; A05d must wrap the exact map in checked
semantic adequacy laws. Law-token equality alone is not semantic evidence.

A05c has a verified but explicitly partial source increment in
`WorkflowV2.SchemaJudgments.fst`: dependent argument-list/telescope alignment,
exact family/rule selection helpers, and the nullary-Atom matcher consequence.
The full 13-module cache-off verifier passes. The argument relation still
accepts a placeholder value-judgment family and is not canonical
`JType`/`JValue`/`JPredicate`; it does not close A05c. See the latest run-log
entry and node summary for exact evidence, including verified scratch context
and tuple-representation alternatives. Scratch establishes only paired
de-Bruijn lookup and a small builtin fragment; it does not yet relate every
context declaration to its carrier under arbitrary weakening, or interpret
package-backed nodes. A second scratch path indexes a declaration-prefix
`JType` witness and same-index bound path for `Vec n`/`Nat`; general weakening
still belongs to A05e. The coherent source increment is
committed as `9ba432b`.

Latest independently rerun scratch, `/tmp/A05cContextLookup.fst`, verifies
carrier-indexed de-Bruijn lookup and `Bound`, plus Root/Port/Constant plumbing,
Pair, and equality/conjunction evidence. Its base resolver chooses arbitrary
typed port/constant carriers and values, so this is not graph-edge, codec,
root-schema, or canonical-context soundness. A proposed context GADT that
stores each declaration's `JType` beside its value could make Bound inherit
the exact declared AST type; this is a design hypothesis, not verified yet.
No DAG acceptance or theorem boundary changes: A05c still needs the full
AST-indexed context, Sigma/Refine, package-backed calls, and soundness.

Focused A05c probes now establish a positivity-safe refinement shape: the
native predicate denotation must be a separate proposition-valued function,
not defined from the mutually recursive evidence GADTs. Builtins/True-only
and Nat-literal equality/conjunction scratches using production `hlist` pass
strict cache-off verification; the latter also proves its fragment-level
predicate-evidence soundness. Neither establishes generic predicate semantics
or source integration. A second scratch
verifies the recursive family binder-alignment law: every argument binder is
typed at its declaration prefix, and later binders are typed under extension
by every inhabitant of the exact earlier carrier. A Nat `SchemaBound 0`
argument derives the package-telescope index. The initial reading was that
this matched A05d's adequacy boundary; the import-order audit below corrects
where the proof is consumed. A05c cannot import A05d, so A05g uses that law
after semantic substitution to build call-specific derivations and share the
selected package/index with denotation, codec, and equality operands. Full
package construction and arbitrary predicate soundness remain open. Exact
commands and limitations are in the latest
`run_log.md` entry and `research/A05-2026-10-14/typed_jvalue_scratch.md`.

A later import-order audit found that A05c cannot consume a proof produced
by A05d because A05d depends on A05c. The earlier scratch conclusion that no
DAG revision was needed is superseded. A05c declares the generic alignment-law
types and may define family/rule judgments conditional on explicit argument
derivations; A05d's exact-map wrapper carries proof-bearing alignment fields
for family, constructor, and index-call signatures; A05e proves substitution;
A05g combines these into closed call-site judgments; A05f then proves prefix
`LegalEnv`. A05d cannot derive alignment from raw package fields or tokens. A further
contract audit makes constructor AST-result-index equality and exact codec
schema/carrier coherence explicit; these laws connect callback outputs to the
syntax-selected result family. This clarifies package adequacy without
changing theorem strength or user API. Synchronized correction commit:
`3d11410`; result-index/codec coherence clarification: `cec8cd6`.

The latest A05c source refinement changes the argument relation's evidence
sort from `Type0` to `Type` and corrects its comment: the relation currently
has no context/environment parameter and the example remains a placeholder.
This is a proof-boundary correction, not canonical JValue evidence. The full
13-module cache-off verifier passes after this refinement. Independent
scratch found a structural-recursive (rather than inductive) JType/JValue
route that handles a dependent Sigma with the existing `dtuple2` carrier;
it currently covers only Nat/Sigma and does not establish context
well-formedness or weakening. A separate universe probe shows a `Type0`
JValue derivation is not itself a `prop`; `Refine` needs a
proposition-valued predicate denotation and a sound bridge from same-carrier
typed values. A05c remains open. Exact evidence is in the latest
`run_log.md` entry and
`research/A05-2026-10-14/typed_jvalue_scratch.md`.
This verified scaffold clarification is committed as `8c0dcc7`; it does not
close A05c.

A05c representation constraint: interpretation yields one sealed,
AST-and-context-indexed canonical package; all judgments reuse that exact
package and dependent Sigma witness. Do not store an independently chosen
carrier plus an unrelated witness/equality. The current integration route is
the dependent existential `a:Type0 & shape rho t a`: the carrier is the
witness's type index, and the shape is indexed by that exact carrier. It
imports production `SchemaSemantics.hlist`, verifies Nat/Sigma package
construction and elimination, and passes a separate client through an
abstract `.fsti`. This is an exact tie, not a second carrier plus an equality
field. An earlier carrier-indexed record constrained to the smaller package
universe hit universe errors. The successful dependent existential raises the
package family to `Type u#1` while its carrier remains `Type0`; keep this
universe assignment explicit. The
shape-only package verifies toy Sigma/Refine and a separate client, but its
Kernel-AST Refine probe with a locally modeled dependent context fails at
subset introduction because its projected carrier does not reduce to the
native subset. It has not yet imported production `SchemaSemantics.hlist`.
That is an encoding/elimination failure, not a reason to weaken Refine. Direct
recursive `TypeDenote` remains rejected. Same-exact-package Nat/Refine and
selected-codec injectivity fragments verify. A new production-context scratch
proves one Sigma with a dependent subset codomain and that its bound-variable
equality AST evaluates true for every represented candidate. A separate
actual-Kernel fragment proves builtin shape/JValue cases for Unit, Bool, Nat,
Int, Product, Sum, List, and Option. These remain specialized scratch proofs;
generic predicate evaluation, selected constructors, and soundness remain
open. In particular, package-selected dependent VecBound0 through the sealed
interface, full AST/package semantics, deriving one exact family package/index from the `SchemaFamily` AST and
sharing it across both equality operands, all-constructor soundness, and
context alignment remain open. A05c
stays `in_progress`; see the latest run log and A05 scratch note. Research
commits: `d8a3f4f`, `c02cf22`, `4252024`, `c42b948`, and `6cee517`.

Latest A05c evidence: production-context scratch now combines dependent
Sigma, a `Vec n`-shaped family at `Bound 0`, and native subset refinement
`{x:nat | x == n}` with an AST bound-equality proof; cache-off verification
discharges every VC. The family identity and interpretation are hardcoded,
so exact package selection and codec linkage remain open. Root also reran the
full 13-module current-source verifier cache-off before integration; all VCs
pass. This is baseline evidence, not A05c closure. An independent source audit
recommends one private canonical package family, one exact package lookup
threaded through denotation/JValue/JPredicate/codec, explicit opaque-interface
builders, context alignment first, then builtins, Sigma, package-backed
families/rules, Refine, and all-constructor soundness. AST-derived dependent
indices, full predicate semantics, constructor/index-call adequacy,
structural termination, and source integration remain blockers. Evidence:
latest run-log entry and `state/research/A05-2026-10-14/typed_jvalue_scratch.md`.
Latest preceding state commit `5b42a90`; A05c remains `in_progress`.
Combined-shape evidence is committed as `7428189` and recorded by this
follow-up state synchronization.

| ID | Depends on | Planned source result and acceptance condition | Status |
|---|---|---|---|
| **A00** | — | **Read-only source/build inventory.** Map every current `WorkflowV2.*.fst`, the Makefile, existing assumptions/admissions, current verified lemmas, and missing P0–P16 obligations. Decide which declarations are reusable, split, or replaced; record module-cycle risks and exact locations. Check configured F*/Z3 versions and run the full Makefile verification. Current findings: seven modules typecheck, but `Graph.fst` contains admitted/assumed builder laws; `GraphCodec.fst` proves syntax roundtrip only; `Journal.fst` declares events but defers replay; chain files are examples, not generic P1/P4. | complete |
| **C0** | A00 | **Commit source audit.** Preserve the inventory and refactor map in a scoped Git commit. Commit `62b5a5f`; hash and evidence are recorded in the summary and run log. This is an immediate, nonblocking checkpoint, not a user-review gate. | complete |
| **A01** | C0 | **Proof/module boundary.** Define the acyclic module import graph, public `.fsti` boundary policy, implementation/proof split, build order, and trust-audit convention. A01 creates documentation only; each `.fsti` begins alongside its owning API and checked `.fst` implementation. Resolve import-order conflicts before A02. Synthesize `state/research/A01-2026-10-13/module_boundary_design.md`; no theorem is discharged here. Commit `34e1021`. | complete |
| **A02** | A01 | **Kernel signatures.** Define typed identities, plain/indexed codecs, `CodeRef`, nondeterministic `OpRef`/validator, generator callback signature, the three `Work` forms, first-order `Wire`/`GraphDesc`, schema-expression syntax/identities, artifact-reference syntax, and run charge metric. Specify package lookup so builders consume the exact returned work/generator package plus membership evidence; do not duplicate closures or require function extensionality. Keep dependent/refinement guarantees at the callee in `CodeRef`'s output family (e.g. `Work nat (fun n -> Prime n)`); do not add a separate lemma field for a property already stated by that type. Remove competing signature sources; include the metric consistently in run budget and generator/operation contracts. Codec values must carry checked roundtrip/canonicality witnesses. Completed with all seven configured modules verified under F* 2026.03.24/Z3 4.13.3. No P0–P16 claim; legacy Graph admissions remain. Commit `bb4d8ae` (source); audit checkpoint `edf0b0f`. | complete |
| **A03** | A02 | **ManifestCore.** Represent identity names, manifest labels, and durable run/artifact names as no-text `identity_token = bytes` values (`bytes = list nat` in this abstract Kernel); make no UTF-8, host-text, or octet-level claim and avoid unchecked `FStar.String`/`FStar.Char` laws. Define the 12 disjoint top-level tagged identity domains and canonical first-order rows. Reject duplicate IDs, malformed rows, wrong-tag/missing top-level identity references, and noncanonical manifest bytes. Prove identity/value/entry/list/manifest codec roundtrips and injectivity, exact top-level lookup uniqueness, canonical ordering, order-independent canonicalization, idempotence, and syntax-level projection shape. Check artifact logical schema equals its reference-codec schema. Schema-expression payloads are opaque syntax bytes here; A05 proves parseability/canonical AST form before P0. Contract IDs are typed owner-row slots, not top-level identity rows: A03 checks exact position/kind, while A04/P0 binds each slot to the exact proof-bearing package field. Keep this distinction explicit; do not duplicate contract tables. Make the registry-identity constructor require a canonical manifest. No closures or proof terms enter bytes. Audit imported proof helper call paths; use no project-owned admission or admitted helper. Full verifier and source/trust report required. A03: `09ed6ea`; earlier evidence `94e6a62`, `e88e1b8`, `528eeb2`; rejected Classical/Squash snapshot `38f8e62`. Final full check: eight modules pass, all VCs discharged, F* 2026.03.24/Z3 4.13.3; scoped trust audit recorded in `state/research/A03-2026-10-14/`. | complete |
| **A04 (P0)** | A03, A07, A15, A16 | **Pinned Bundle.** Store the exact executable packages and proof-bearing generator packages beside their canonical manifest. Prove full identity uniqueness and exact package coherence; codec/schema/type agreement, including artifact reference codecs; root-entry constructor linkage; run metric coherence; exact projection in both directions; and restart-stable identity-to-package lookup. For every typed contract slot in a manifest row, prove the token resolves to exactly the corresponding validator, adapter/configuration, allocation, codec-version, denotation, interpretation, projection, or other law-bearing field of the uniquely selected package, and that this exact object is the one used by execution. Generator proof packages include the callback token and admission law. Do not compare duplicate function closures. P0 cannot be discharged by comparing only durable refs. | not_started |
| **C1** | A04 | **Commit identity/API contract.** Commit the completed P0 plus kernel, manifest, schema/resolver, allocation, and generator-package contract boundary. Record theorem evidence and unresolved questions; this checkpoint is after schema work and before public graph construction. Do not wait for human review. | not_started |
| **A05a** | A03 | **Codec and syntax scope laws — complete.** `SchemaCodec` proves callback-free suffix/public roundtrip, injectivity, and trailing-byte rejection for every Value/Predicate/Type AST constructor while preserving the unframed encoders. `SchemaScope` proves scope, lifting, substitution, identity/composition, and binder laws for `Sigma`/`Refine`. This is syntax-only support: it proves no denotation, semantic substitution, or `LegalEnv` theorem. Source evidence: codec commit `115fd0bf057f403c32ceeeba57c615b1385de381`; scope commits `0ace03d` and `1cc76f4`; full verifier details in the A05 summary and run log. | complete |
| **A05b** | A05a | **Exact schema-package base interface — complete.** Add the minimal manifest-indexed package map with exact owner-row, expression, and law-token projections; typed dependent carrier telescopes; exact codec objects with membership in the shared registry; constructor/index-call variant; and exact parent lookup helper. Telescope arity equals declared AST arity. `SchemaAtom` is nullary; `SchemaFamily` matches the same arity, including zero. The source is verified in `e70c0ce01dfb8006c6386cb39a559023bd99d547`; final independent audit found no need to reorder the DAG. The clarified acceptance boundary is committed as `28e23f3`. This stage supplies package data, not semantic adequacy: scope/arity, codec membership, exact token equality, and lookup do not prove binder typing, denotation, result-index laws, or equation soundness. A05c/A05d own those burdens. | complete |
| **A05c** | A05b | **Canonical denotation and typed judgments.** Define the one canonical interpretation of each supported schema type/value/predicate AST under the exact base package map. Use one sealed AST-and-context-indexed package, reused by `JType`, `JValue`, and `JPredicate`; do not duplicate an independently chosen carrier and equality proof. Current integration route: dependent existential `a:Type0 & shape rho t a`, with the shape indexed by the exact carrier and no equality field. The package family is `Type u#1`, while the carrier remains `Type0`; this avoids the earlier universe error from constraining a carrier-indexed record to the smaller package universe. It verifies Nat/Sigma construction and an abstract `.fsti` client using production `SchemaSemantics.hlist`; proceed with source integration on this route. A private JValue GADT, exposed as an abstract `Type u#1` family through a `let` alias, plus smart carrier constructors and eliminators, verifies a separate client for Sigma and `SchemaRefine ... SchemaTrue`. Exposing the GADT as an abstract `val` fails Error 197. Opaque package carriers require clients to use explicit carrier builders rather than raw pairs/naturals. A separate actual-context fragment verifies dependent Sigma with codomain `SchemaRefine Nat (SchemaEqual (SchemaBound 0) (SchemaBound 1))`, carrier `{x:nat | x == n}`, and a specialized evaluator proving the AST bounds agree for values in production `hlist`; this establishes expressibility of a nontrivial dependent refinement, not generic `JPredicate`. Another production-context fragment verifies dependent `SchemaFamily fid [SchemaBound 0]` at `vec n`, but hardcodes the family interpretation and has no package-linked codec/interface. Shared-package codec-reflection proofs derive equality from byte equality at one exact carrier/index. A new helper uses the exact selected `schema_family_package.family_codec` and registry lookup can pass that one package to a continuation. Deriving its package and index from a `SchemaFamily` AST and sharing the witness across both operand judgments remains open. A shape-only toy package verifies Sigma/Refine, but its locally modeled Kernel-AST Refine projection fails subset introduction (Error 189); do not weaken Refine on this basis. Direct recursive `TypeDenote` and an unindexed opaque handle are rejected. Expose explicit value builders, carrier laws, and judgment eliminators because clients cannot rely on hidden definitional reductions. Refine is the native subset with structural proposition-valued predicate evidence; equality operands use one shared exact carrier/index and selected codec reflection. Use paired AST/carrier/value contexts with explicit context well-formedness. Cover every Kernel AST constructor, including Bound, Root, prior Port, exact Constant, pairs/projections, Constructor and IndexCall. Prove structural termination and judgment soundness relative to canonical package interpretation; do not claim callback-to-schema adequacy yet. No function extensionality. Declare generic alignment-law types for family, constructor, and index-call argument signatures here, without proof inhabitants or importing A05d. A conditional family type judgment is now integrated: it binds `SchemaFamily` to the exact selected package and its dependent result carrier, while still requiring an argument derivation. Full configured verification passes; source/evidence commit `202ab1e`. A05c remains open because the value relation is still a placeholder and other constructors/soundness are not integrated. A05d's exact-map adequacy wrapper carries proof-bearing alignment fields; A05e proves semantic substitution; new A05g consumes both to derive use-site arguments and close all three package-backed AST forms. Keep one exact package/index across denotation, codec, and both equality operands; no per-use author proof fields. Package-selected dependent VecBound0 through the sealed interface, generic Refine/JPredicate semantics, full AST/package semantics, selected family/rule cases, AST-derived exact package/index selection shared by both equality operands, and all-constructor soundness remain open. Nat/Sigma, actual-context dependent Sigma/refinement/Vec, local-context dependent Sigma/VecBound0, builtin shapes, codec reflection, and hidden-client proofs are scratch architecture evidence only, not A05c closure. | in_progress |
| **A05d** | A05c | **Package adequacy and completeness boundary.** Define `AdequateSchemaPackages` (or equivalent proof-indexed wrapper) over the *same exact* base package map. Its checked law fields establish: every AST argument binder denotes its corresponding dependent carrier; family row/result expression and canonical family denotation agree; constructor AST result-index expressions, evaluated under every well-typed argument tuple, equal the selected parent's computed indices and the result inhabits that exact family; index-call application has the canonical `index_call_result` type; every exact declared equation is denotationally sound; and codec/index membership matches that same denotation. Bind each exact codec's manifest input/output schema projections to its telescope/result carriers; registry membership and codec roundtrip alone do not establish schema/carrier coherence. For family, constructor, and index-call argument telescopes, carry one recursive package alignment law: each binder is typed in the preceding AST/runtime context, and the tail law holds for every inhabitant of the exact prior carrier under the extended context. These proof fields are checked contract inputs, not consequences of raw package data or identity tokens. A05d does not import into A05c; after A05e substitution, A05g constructs the use-site derivation and shares the exact package/index across denotation, codec, and equality operands. Graph/work authors supply no per-use proof. Prove the generic consequences of these fields and make the wrapper the only semantic input for A05e/A05f and downstream A06/A07/A04. A contract token is identity/projection only, never evidence. This avoids vacuity and prevents an unrelated callback from being accepted. Prove completeness only for `SchemaSupported` and values with specified schema quotation/representation; do not claim all erased `Type0` values are reifiable. If package contracts cannot establish both soundness and this completeness boundary, revise A05 interface before downstream work. | not_started |
| **A05e** | A05a, A05d | **Semantic weakening and substitution.** Prove arbitrary-cutoff type/value/predicate weakening and semantic substitution under paired contexts, including nested `Sigma`/`Refine`, where outer declaration types lift at the correct cutoff. State substitution as a relation: each source binding maps to a target schema expression denoting the same value. Prove context admissibility and judgment preservation; syntactic substitution or equality alone is insufficient if target bindings do not inhabit their substituted declaration types. Prove judgment transport to instantiate each family, constructor, and index-call signature alignment law at actual caller arguments. Avoid function extensionality and admissions. | not_started |
| **A05g** | A05d, A05e | **Schema call-site closure.** For every supported `SchemaFamily`, `SchemaConstructorValue`, and `SchemaIndexCallValue`, select the exact package by manifest identity and AST matcher; consume its exact-package binder/carrier alignment field and A05e substitution to derive each actual argument at its substituted declared type; assemble the exact dependent argument tuple; and construct the canonical shape/value/predicate judgment. For constructors also prove the AST `constructor_result_indices` evaluate to the same dependent index returned by `constructor_parent_indices`, then consume parent-family inhabitance. For index calls consume result-typing and exact codec/equation package laws. Prove denotation and codec use the same package/index, and equality operands share one package/index. Reject wrong arity, untyped arguments, or mismatched family/rule variant. Callers provide no edge/context proof. This is the first closed AST-to-package-use theorem for every package-backed AST constructor and preserves the all-environments edge rule. | not_started |
| **A05f** | A05g | **`LegalEnv` prefix semantics.** Define the semantic graph-prefix environment without importing GraphResolve/Bundle: exact root, exact canonical constants decoded by their pinned codec at the exact index, then each prior node input evaluated in its existing prefix and every inhabitant of its full declared output family appended. Prove each prefix yields the paired well-formed context and supports the required wire/value/type/predicate derivations, including package-call closure from A05g. External outputs remain universally quantified; validator postconditions and observed executions never narrow the set. Cover empty and snoc prefixes, generated graph roots, indexed constants, and prior-only Port lookup. | not_started |
| **A05** | A05a–A05g | **Integration acceptance.** Integrate the proof modules with acyclic imports and one source of package meaning. Run the complete configured cache-off F* verification; audit the transitive project-owned proof path for `assume`, `admit`, unchecked declarations, external axioms, vacuous package contracts, and duplicated semantic sources. Check the completeness boundary against implementation spec §2.2.1. Record verified theorem/source map and explicit limits; no A06 equality calculus, A07 graph resolver, A04/P0 runtime-package projection, or P1 completeness is claimed here. A06 may start only after this rollup passes. | not_started |
| **A06** | A05 | **Equality calculus.** Define total normalization or derivation checking for exactly the finite equations in the exact schema packages selected by manifest owner rows. P0 pins each equation set through its owner row and proves restart-stable package selection. Prove termination, denotational soundness, and completeness for the declared `SchemaSupported` equality relation. Refinement equivalence is checked under the same candidate-value binder and domain. Unknown or undecidable equalities reject; no unchecked solver-success constructor, runtime observation, or extra edge-proof payload. | not_started |
| **A07** | A06, A03 | **Graph resolver / universal edge judgment.** Define typed wire judgments and the dependent port telescope over legal environments. Prove root, constants, prior outputs, pairs, and projections denote their declared families. Any refinement fact used by typing must be derived from exact declared port-family membership, never validator postconditions. Prove every direct edge's producer-output/consumer-input equality for all legal environments, with external values quantified over the entire declared output family. Explicitly reject unconstrained `Sigma n. vector n -> vector 3`. It consumes manifest/schema syntax, not the completed executable bundle. | not_started |
| **A15** | A07, A03 | **Allocation and occurrence model.** Define graph-local plans, exact node alignment, valid fuel/charge allocation from manifest metadata, deterministic path-derived occurrence lifting, run-wide charge metric and ledger projections. Prove plan lookup, uniqueness, and lift-preservation lemmas. This is data and local proof support, not yet aggregate P8. Keep plan validity independent of Bundle and the public builder so generator packages can use it acyclically. | not_started |
| **A16** | A15, A07, A02 | **Universal generator package law.** Define `GeneratorPackage manifest` containing one exact `GeneratorRef` and its universal proof that every legal input, metric, and parent allocation yields a `SchemaSupported` graph and valid aligned graph-local plan. This is an explicit checked package input, not a sample or system assumption. Do not define registry-indexed membership here; Bundle stores this whole package and P0 binds it to its exact identity. No Bundle/Builder/Generation dependency. | not_started |
| **A09** | C1 | **Graph syntax codec.** Define canonical first-order descriptor encoding/decoding, complete-input parsing, malformed/trailing-byte rejection, and prove graph syntax encode/decode roundtrip plus accepted-byte canonicality. Keep this result explicitly syntactic. Its concrete proof body satisfies the law-bearing graph codec interface pinned by P0. | not_started |
| **A08 (P1)** | C1, A07, A16, A04 | **Builder soundness and completeness.** Implement public `start_graph`, `add_node`, and `finish_graph` over one canonical finite-DAG syntax. Prove successful construction is a finite, unique-key, acyclic `SchemaSupported` graph with exact port types; prove failure/success behavior and completeness for every supported finite topology (including independent nodes, fan-out, joins, constants, and projections), up to typed graph isomorphism. Replace current `admit()` builder spine. GraphBuilder consumes the exact package/membership returned by Bundle lookup; it never accepts a duplicate callback requiring extensional equality. No topology-size restriction is introduced. | not_started |
| **A10 (P2)** | A08, A09, A04 | **Typed graph interpretation/roundtrip.** Resolve decoded root and generated descriptors through the same pinned resolver. Prove exact reconstruction/preservation of input/output indices, work package, constants, port telescope, wires, topology and derived typing witness. Prove typed isomorphism transports dependent contexts and signatures under key renaming; raw label/wire equality is insufficient. No graph closure or typing proof is serialized. | not_started |
| **C2** | A10 | **Commit typed graph contract.** Commit the schema/resolver, builder, and typed decode milestone after both graph syntax and typing branches have joined. Record the hash and the static rejection evidence for `vector n -> vector 3`; no user response gates journal work. | not_started |
| **A11** | C2 | **Canonical journal data and transition definitions.** Define the minimal five events (`RunStarted`, `GraphCommitted`, `NodeCompleted`, `CallIntent`, `CallOutcome`), canonical state as `replay(J)`, derived projections, guarded `apply`, terminal states, and event-specific expected-head conditions. Keep semantic origin separate from replay-checkable `StateWF`; do not add a durable failure state. Durable run names and artifact identities use opaque byte tokens, not F* strings. | not_started |
| **A12** | A11, A02, A10 | **Journal codecs.** Define event/journal codecs and prove roundtrip, unique accepted encoding, framing, and rejection of malformed/torn/trailing representations. Use canonical indexed value/graph bytes and exact run codec identities. Do not add an unproved F* string/host-text conversion to durable codecs. | not_started |
| **A13 (P3)** | A12, A04 | **Replay and structural WF.** Prove empty-journal base case; deterministic guarded replay; every legal transition preserves replay-checkable `StateWF`; malformed prefixes reject; terminal state is absorbing; canonical durable logical state is exactly `replay(J)`. Explicitly prove replay alone does not imply computation provenance. | not_started |
| **C3** | A13 | **Commit journal/replay model.** Commit the canonical event, codec, replay, and `StateWF` milestone before provenance, adapter, resource, or journaler branches begin. Record the hash and make the distinction from `SemWF` explicit in the summary; no user response gates dependents. | not_started |
| **A14** | C3, A04, A10 | **Semantic authority model.** Define `AuthorizedEvent`, event-origin witnesses, append-history `SemWF`, and prefix restriction/extension operations. Keep ghost witnesses out of journal bytes. State exactly how a witness is tied to the selected Work, input, output bytes, generator graph/plan, adapter receipt, and current replay head. | not_started |
| **A17** | A16, A15, A08 | **Typed dynamic splice.** Prove child-boundary substitution at the exact generator input; preserve all internal edge equalities, root result family, global DAG acyclicity, occurrence uniqueness, and exact path-lifted allocations. Prove zero-fuel cannot emit nested generators and nested generator fuel rules. Root and generated topology use the same graph judgment. | not_started |
| **A18 (P4)** | A17, A14, A13, A10 | **Authorized graph commit and visibility.** Prove only the exact admitted generator result and plan can authorize `GraphCommitted`; journal bytes are canonical exact result; successful serial append is the visibility point; no child is actionable before commit. Compose typed splice with transition and append token without depending on P10's crash theorem, P8, or P15. | not_started |
| **A19 (P6)** | A14, A13, A04, A10 | **Local result provenance and absorption.** For exact reconstructed input, prove committed canonical output bytes decode at the exact index and equal the pinned total pure `CodeRef.run`; after commit the occurrence is absent from the future frontier. A calculation interrupted before commit may be recomputed. | not_started |
| **A20** | C3, A02, A04, A11 | **External adapter contract.** Define one-intent-per-submission interface with multiple distinct outstanding keys; stable call key and exact canonical request/resume binding; receipt/evidence/charge/artifact fields; pinned validator and `persist_x`; same-key overlap/retry/restart safe-effect law; changed bindings rejected. Distinct keys may be nondeterministic and finish out of order. State per-key progress separately as a conditional law. | not_started |
| **A21 (P7)** | A20, A14, A13, A04, A10 | **Adapter provenance theorem.** Prove each authorized outcome belongs to its exact intent/key/input, validated typed output, immutable terminal receipt, evidence, charge and resources. Prove same-key retries/overlaps/restarts denote one logical effect and byte-identical terminal tuple from the contract laws; do not assume deterministic replies across distinct keys. Keep liveness conditional. | not_started |
| **A22 (P8)** | A15, A18, A21, A13 | **Charge/fuel ledgers.** Prove replay transition equations and aggregate conservation for free, allocated, reserved, and spent charge plus free/allocated/consumed fuel. Prove graph commit/intents/outcomes preserve exact occurrence projections and reserve/settle once. All charges use the one pinned run metric; do not reallocate unused root remainder dynamically. | not_started |
| **A23 (P9, conditional extension)** | C3, A02, A04, A13 | **Typed artifact identity.** Define exact typed reference/inventory projection and proof-bearing artifact-store laws; prove P9 generically from those laws: publish-before-event-commit, immutable logical version, same-object resolution after supported restart, no overwrite/delete of reachable versions, and replay performs no I/O. The API may omit a store instance and treat references as opaque; only runs supplied with this contract claim backing-object identity, and only their P15/P16 results include the P9 extension. | not_started |
| **A24** | C3, A12, A13 | **Abstract serial journaler contract.** Define compare-and-append, exact head, atomic committed-prefix visibility, monotone persistence, canonical bytes on load, arbitrary crash cuts, no external mutation, and settle/fence of old append requests before recovery load. These are proof-bearing contract fields; no concrete disk/database is implemented here. | not_started |
| **A25 (P10)** | A24, A13, A04, A10 | **Every-cut canonicity/durability.** Prove every recovery load yields exactly the latest complete committed prefix; its bytes are the unique canonical encoding; committed events persist monotonically; old appends cannot cross the recovery barrier; `replay` returns exactly that prefix's state. Keep physical implementation/refinement claims outside this abstract theorem. | not_started |
| **A26 (P5)** | A18, A25, A10, A16, A15 | **Exact generated-graph recovery.** For every recovered prefix with `GraphCommitted`, prove decode/resolution returns the exact committed graph and path-derived lifted plan. Recovery reuses these bytes and allocations and never reruns the generator to select or replace committed topology. | not_started |
| **C4** | A18, A19, A21, A22, A23, A25, A26 | **Commit provenance/durability milestone.** Join and commit the completed P4/P5/P6/P7/P8/P9-conditional/P10 work as one coherent checkpoint. Record individual theorem evidence and the hash. This replaces the former review gate and does not wait for a user. | not_started |
| **A27** | C4, A19, A21, A22, A25, A26 | **Abstract Services and ControllerModel.** Define proof-bearing local/generator executor and scheduler contracts (bounded concurrent claims, only ready inputs, result return, fresh epochs); multi-inflight adapter service; one commit coordinator; serial journal append slot; controller volatile state and atomic steps. No concrete worker pool or runtime. | not_started |
| **A28** | A27, A08, A10, A14 | **Ready-input and claim lemmas.** Prove sparse reconstruction from committed referenced outputs agrees with the full typed graph evaluator in every compatible environment. Prove unique live claim, exact input/allocation binding, fresh epoch, current-head reauthorization, stale permit/result rejection, and commit-gated visibility lemmas. | not_started |
| **A29 (P15)** | A27, A28, A18, A19, A21, A22, A25, A26 | **All-schedule abstract safety.** Induct over every permitted bounded launch, completion, adapter retry/outcome, append, crash, and recovery ordering. Prove typed graph WF, `SemWF`, exact inputs, ledger invariants, unique claims, serial reauthorization, commit-before-visible, recovery barrier safety, and no dispatch after committed completion/outcome. Safety is for arbitrary completion order and uses no fairness. If P9 is included, prove its concurrent artifact extension here as a conditional theorem. | not_started |
| **A30 (P11)** | A29, A08, A18, A19, A21, A22, A26 | **Enabled frontier/no-stuck.** Prove every started reachable nonterminal replay state has an enabled legal action or same-key resumable intent. Exclude pre-`RunStarted` bootstrap. State this as frontier existence only, not service completion. | not_started |
| **A31 (P12)** | A13, A18, A19, A21, A22, A26 | **Well-founded progress rank.** Define and prove strict decrease of `(G,U,W)` (or an equally explicit well-founded measure) on every successful post-start append under any serialization order. Show stale/rejected appends are not transitions and handle zero-fuel generators. No P15 premise is used. | not_started |
| **C5** | A29, A30, A31 | **Commit schedule-safety and progress milestone.** Commit the all-schedule safety, enabled-frontier, and progress-rank proofs together after their branches join. Record the hash before starting recovery composition or generic refinement. This is a nonblocking checkpoint. | not_started |
| **A32 (P16)** | C5, A26, A19, A21, A22, A25, A13, A14 | **Recovered semantic graph correctness.** For every authorized abstract trace and crash cut, compose P10 prefix selection, deterministic replay, `SemWF` prefix witnesses, P2/P5 graph typing/recovery, P4 exact generator provenance, P6/P7 result provenance, P8 ledger state, and P15 trace safety. Prove committed work is not rerun/replaced; pending intents resume only on exact binding. Add P9-backed object identity only under its proved contract. | not_started |
| **A33 (P13 schema)** | C5, A25 | **Generic concrete-refinement interface/theorem.** Define `ConcreteRep`, concrete steps, load/barrier mapping, and proof-bearing component simulation obligations. Prove generically that any future runtime supplied with these refinement witnesses simulates the abstract system and inherits established safety/durability results. Specify progress-preserving/finite-stuttering conditions needed to transfer P14. This proves the transfer theorem, not an instance; no OCaml/filesystem/network implementation is in this DAG. | not_started |
| **A34 (P14)** | A30, A31, A33 | **Conditional termination.** Prove the abstract run reaches its typed root output from committed `RunStarted` when explicit weak fairness, total local/generator/validator behavior, executor return, append retries, adapter terminal/reconciliation progress, resource progress if P9 is claimed, finite initial fuel, finitely many crashes, and any P13 progress-preservation obligations hold. Keep all liveness premises out of P15. A concrete runtime inherits this result only after a later P13 instance supplies the refinement proof. | not_started |
| **A35** | A32, A34, A04, A10 | **Proof-bearing API examples.** Construct and verify (1) dependent `Work nat (fun n -> Prime n)` with the callee returning its prime proof in the result; (2) local output reused after recovery; (3) static analysis over typed file/tree refs with adapter materialization, CLI result parsing in F*, and P9 if backing identity is promised; (4) input-dependent graphs with differing finite sizes, joins and fan-out; (5) inline and reusable/library API adapters with identical `OpRef`/P7 semantics; (6) deterministic event-queue adapter with concurrent keyed out-of-order completion. Examples are actual F* proofs and exercise the public API; they do not replace generic theorem proofs. | not_started |
| **A36** | A35, A23 | **Integrated theorem/trust audit and full check.** Verify all abstract P0–P12/P14–P16 targets, the generic P13 transfer theorem, and contract law owners against implementation spec; identify that no concrete P13 instance is claimed. Inspect transitive dependencies for `assume`, `admit`, unreviewed axioms, duplicate sources of truth, unproved solver boundary, or host claim hidden in an abstract theorem. Run the complete project F* check and record tool versions/command/results. No unresolved theorem may be called verified. | not_started |
| **C6** | A36 | **Final commit and completion record.** Commit the integrated, full-checked abstract system and record its hash, theorem map, contract premises, verifier command/result, and deferred concrete instances. Execution reaches this point without waiting for human review. A concrete runner/SQLite/filesystem/network P13-instantiation DAG remains separate future work. | not_started |

## Theorem dependency checklist

The table above refines this normative proof order; later nodes must preserve
these dependencies and theorem meanings:

| Theorem | Required proved inputs |
|---|---|
| P0 pinned identities/codecs | Proof-bearing package, codec, manifest, root-entry, and reload laws; exact package projection. |
| P1 typed graph builder/resolver | P0; schema denotation/equality calculus; universal edge compatibility and builder completeness for exactly `SchemaSupported`. |
| P2 graph codec and typed resolution | P0/P1; canonical syntax roundtrip and exact typed witness reconstruction for both root/generated graphs. |
| P3 canonical replay | P0/P2 plus fixed journal codec laws; guarded deterministic replay, `StateWF`, terminal absorption. |
| P4 graph commit | P1–P3; universal generator admission, exact plan, typed splice/global DAG, exact authorized append before child visibility. |
| P5 graph recovery | P2/P4/P10; exact committed graph and lifted plan reused. |
| P6 local provenance | P0/P3; exact reconstructed input, result equal to pinned function, committed occurrence absorbing. |
| P7 external provenance/effect safety | P0/P3; exact key/binding, effect-safe retry, immutable receipt and output correlation; progress conditional. |
| P8 charge/fuel | P3/P4/P7; one-time settlement, exact plan projections and conservation. |
| P9 resources | P0–P3 and artifact-store contract; conditional extension to P15/P16 only when resource identity is claimed. |
| P10 every-cut durability | P0–P3 and serial journaler contract; exact latest prefix bytes, canonicality, monotonicity, stale append fencing. |
| P11 frontier | P1–P8/P15; enabled action or exact resumable intent in started nonterminal states. |
| P12 progress rank | P3–P8; strict well-founded decrease for every successful append, independent of P15. |
| P13 refinement | P0–P8/P10–P12/P15, with P9 only for promised backing identity; this DAG proves a generic transfer theorem, not a host instance. |
| P14 conditional termination | P11–P13 plus explicit fairness/service/fuel/crash assumptions. |
| P15 all-schedule safety | P0–P8/P10, plus P9 extension only if claimed; arbitrary interleavings, no fairness. |
| P16 recovered semantics | P0–P8/P10/P15, with P5 named explicitly and P9 only for backing identity; every-cut typed graph, provenance, and no-rerun theorem. |

## State and provenance protocol

- [`state.md`](../state_summary.md) names this DAG as authoritative and states the
  objective and no-execution status.
- [`node_summaries.md`](../../history/node_summaries.md) records historical S2 planning
  separately from this DAG; for A00–C6 it records no execution until nodes
  actually start.
- [`run_log.md`](../../history/run_log.md) is chronological and records this planning
  revision without claiming a DAG node ran.
- [`research/registry.md`](../../research/registry.md) tracks source, theorem-order,
  and adversarial reviews for this DAG.
- [`legacy_v2_work_dag.md`](../legacy_v2_work_dag.md) is historical only. It is
  not an alternate execution authority.

Before any future node starts, update the run log. On completion, first record
the artifact, verification evidence, commit hash (where applicable), and
remaining obligations in `node_summaries.md`; then update status in this DAG
and `state.md`. Keep the diagram, table, state hub, summaries, and log
consistent. Do not mark a node complete because earlier source resembles its
planned result.
