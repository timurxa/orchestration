# A01 adversarial boundary review

## Verdict

Most module edges form an acyclic graph. One blocking ownership/ordering ambiguity remains: `GeneratorMember` is owned by `GeneratorAdmission`, which depends on `Bundle`, while packet semantics require the pinned generator entry/Bundle to carry that proof and P0 to bind it. DAG places P0 at A04 and only defines generator admission at A16. Resolve this before A02/A04 signatures freeze.

No theorem is proved by this review. Current-source examples below show hazards, not evidence against the proposed design itself.

## Blocker: generator admission law has no acyclic owner

- Packet assigns `GeneratorMember` type and package membership to `GeneratorAdmission`, importing `Bundle + GraphResolve + Allocation` (`implementation_packet.md:247-250`). It also says the universal proof is supplied with the pinned generator entry and P0 binds it to the exact identity (`:190-200`).
- If the entry/Bundle stores that proof, its field type must be available before Bundle is defined. But `GeneratorAdmission` imports Bundle, so Bundle cannot import the owning module. If Bundle omits the proof, current wording “supplied with the pinned generator entry” and “P0 proves it is the exact law attached” lack a representation/lookup path.
- Active DAG sharpens the order conflict: A04 proves P0 before A16 defines `GeneratorMember`; A16 depends on A04 (`state/work_dag.md:193,199`). A04 cannot bind a law whose contract type is first introduced at A16 unless an earlier interface reserves its type. Moving A16 before A04 would create a dependency cycle because A16 consumes the pinned bundle.

**Required decision:** separate the lower-level universal generator-law type from `GeneratorAdmission` and define it before Bundle using only graph/schema/allocation-level predicates; Bundle can then store exact proof-bearing generator entries, while a later module derives `WorkMember`. Or narrow P0 to exact identity/package binding and make A16 provide a separately indexed `(bundle, generator)` admission witness consumed by P2/P4, explicitly removing the claim that P0 binds that law. State where proof lives and which theorem verifies exact association. Do not leave this to `.fsti` opacity.

## P1 theorem ownership overlaps

`GraphResolve` “owns P1 soundness/completeness” (`implementation_packet.md:245`), while `GraphBuilder` also “owns ... graph completeness” (`:251`). DAG separates A07 resolver/universal edge judgment, A16 admission, and A08 public builder soundness/completeness (`state/work_dag.md:197-201`). These can be acyclic, but “completeness” names two different results and can obscure whether A07 is expected to prove executable builder completeness.

**Clarify:** A07 proves soundness/completeness of the declarative schema resolver for exactly `SchemaSupported`; A08 proves public constructor soundness/completeness relative to that judgment. P1 is the composition. Make theorem-interface ownership explicit; no duplicate P1 theorem/axiom in both modules.

## `.fsti` trust boundary still underspecified

Packet says to expose caller-facing laws in `.fsti` during implementation (`implementation_packet.md:234-238`) and says contracts are proof-bearing (`:190-200,347-350`), but does not define how interface declarations acquire checked bodies or how bodyless `val`/abstract declarations are audited. A `.fsti` can hide a missing implementation boundary from a consumer reading imports; a full build and transitive trust audit are necessary. Active DAG A36 requires transitive `assume`/`admit`/axiom checks (`state/work_dag.md:230`), but that is final audit, not an A01 interface policy.

**Policy needed in A01 design:** every public theorem/value declaration has a checked `.fst` implementation in the complete build; every intentional abstract contract enters as an explicit value parameter with named law fields and is listed as a theorem premise/trust-ledger item. Reject `assume`, `admit`, new/unreviewed axioms, and unmatched declarations in all transitive dependencies. Build/check each `.fsti` with its paired `.fst`, then audit the full dependency closure. This preserves explicit conditional contracts without smuggling them in as global axioms.

## Source-of-truth risks to lock down

- `ManifestCore` owns schema rules and exact projections (`implementation_packet.md:243`); `Bundle` also owns executable tables, “manifest projection and resolver coherence” (`:247`). This is sound only if ManifestCore defines canonical row syntax/encoding once and Bundle proves the package-to-row relation against it. Do not implement a second projection function in Bundle. DAG A03/A04 has the right intended split (`state/work_dag.md:192-193`); preserve it in signatures.
- Kernel owns graph syntax interfaces while GraphCodec owns their canonical encode/decode (`implementation_packet.md:242,246`). Keep syntax datatype/identity in Kernel and codec implementation/laws in GraphCodec; do not shadow descriptor fields or codec identities. Current source already has separate global codec registry and package-embedded codecs (`Identity.fst:185-207,288-292`), documented as a drift risk (`A00-2026-10-13/source_refactor_map.md:51-61`).
- Allocation owns “ledger projections” (`implementation_packet.md:248`), while Journal owns `State` and ControllerModel has ledger data/projections (`:253,259`). Clarify that Allocation defines plan/path-derived projection functions; Journal owns the sole replayed ledger state. Otherwise two computed/serialized budget ledgers could drift.

## Minimality / layering

No other definite import cycle found in the listed edges: Journal stays below Services/provenance/Controller; EventAuthority contains witness definitions only; P4/P8 and P5/P16 are split to avoid back-edges (`implementation_packet.md:253-290`). However, `GraphInterpretation` imports both `GraphResolve` and `Bundle` although Bundle itself contains resolver coherence (`:247,250,271-280`). Keep this only if GraphInterpretation needs resolver theorem definitions unavailable through Bundle; otherwise expose one resolver interface through Bundle to avoid duplicate API dependency. This is optional cleanup, not a correctness blocker.

`Services` combines journaler, executor, adapter, scheduler, and optional store contracts (`implementation_packet.md:254`). They are independent contracts, but shared journal event types give one-way Journal-to-Services dependency. Keep this combined module only if it avoids actual cycles and does not make every theorem import unrelated contracts; splitting contract records is optional and must not split their law ownership from the API they constrain.

## Current-source evidence

The existing `Graph.fst` exposes assumed builder type/API (`src/fstar/v2/src/WorkflowV2.Graph.fst:417-424,523-526`) and admitted construction/completeness laws (`:906-956`). `Identity.fst` documents its pinned bundle as not yet binding identity to contents (`src/fstar/v2/src/WorkflowV2.Identity.fst:284-292`). These support the planned split and trust rule; none should be carried forward as axioms. A00 likewise calls current files partial evidence (`src/fstar/v2/implementation_packet.md:234-238`).
