# Adversarial review: user guide for F* workflow v2

## Scope and verdict

Reviewed current normative spec, packet, theorem guide, graph/recovery guide, active state/DAG, source audit, theorem-DAG audit, registry, and `.fst` evidence. Read-only; no source edits or DAG execution. This review assesses what a standalone guide must say to avoid overstating implementation or proof status.

A guide can explain the proposed abstract system. It must label the proposal as normative semantics plus planned proofs, not as a verified workflow runtime. The current state/DAG are unambiguous: A00–H5 are planned and unstarted, no F* verification was run ([state.md](../../schema_era_2026-10-14/state_summary.md#L10), [state.md](../../schema_era_2026-10-14/state_summary.md#L83), [work_dag.md](../../schema_era_2026-10-14/state/work_dag.md#L1)). Existing source is partial evidence with admitted builder proofs and no replay/recovery/controller implementation ([source_audit.md](../implementation_dag_2026-10-13/source_audit.md#L3), [source_audit.md](../implementation_dag_2026-10-13/source_audit.md#L31)).

## Strongest objections and required clarifications

### 1. “Original implementation spec” has no safe single referent

Current `implementation_spec.md` is the normative abstract-system contract, expressly not an implementation; it claims no source theorem discharged ([implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L1)). Its predecessor in project history appears to be the paused V2-03 implementation effort and source baseline, preserved in `legacy_v2_work_dag.md`; S2-00–12 then revised specification/architecture, and the active A00–H5 DAG now plans future implementation ([registry.md](../registry.md#L3), [registry.md](../registry.md#L14), [registry.md](../../schema_era_2026-10-14/research_registry.md#L104), [work_dag.md](../../schema_era_2026-10-14/state/work_dag.md#L3)). Avoid saying “the original implementation spec” unless guide identifies exact filename, revision, and date. Better wording: “The predecessor was the earlier V2 implementation plan/source effort, paused at V2-03. The current `implementation_spec.md` is the normative abstract contract created in the later S2 design pass.” If comparing technical semantics, cite the exact predecessor artifacts; do not reconstruct them from stale summaries.

### 2. Current authority/status documents conflict

`state.md` and `work_dag.md` make A00–H5 the active DAG, all `not_started` ([state.md](../../schema_era_2026-10-14/state_summary.md#L10), [work_dag.md](../../schema_era_2026-10-14/state/work_dag.md#L1)). But theorem guide still says S2-00–12 complete and active plan stopped at S2-HUMAN ([key_correctness_theorems.md](../../schema_era_2026-10-14/key_correctness_theorems.md#L364)); registry header likewise says S2 is active and awaiting review ([registry.md](../registry.md#L3)). This is stale status, not merely historical lineage. A user guide must cite state/DAG as current authority and avoid repeating S2-HUMAN as current. Recommend flagging this contradiction for doc cleanup; do not silently claim all project docs agree.

### 3. Distinguish four artifact classes

- **Spec:** normative mathematical target, definitions, explicit contract laws, theorem statements; schematic F* declarations do not constitute source proofs ([implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L27), [implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L830)).
- **Packet:** subordinate architecture/module ownership, proposed signatures and proof order; no P0–P16 result is proved there ([implementation_packet.md](../../schema_era_2026-10-14/implementation_packet.md#L1), [implementation_packet.md](../../schema_era_2026-10-14/implementation_packet.md#L344)).
- **Theorem/graph guides:** explanatory reading aids and target maps, not independent authorities or implementation evidence ([key_correctness_theorems.md](../../schema_era_2026-10-14/key_correctness_theorems.md#L1), [graph_and_recovery_guide.md](../../schema_era_2026-10-14/graph_and_recovery_guide.md#L1)).
- **Source:** existing seven `.fst` modules contain partial definitions/example proofs; they do not implement the spec. Graph builder spine uses `admit()` ([Graph.fst](../../current_implementation/src/WorkflowV2.Graph.fst#L906)); `Journal.fst` explicitly defers replay ([Journal.fst](../../current_implementation/src/WorkflowV2.Journal.fst#L101)); source audit says no controller, replay, durable store, or recovery model ([source_audit.md](../implementation_dag_2026-10-13/source_audit.md#L5)).

Do not use “verified v2 system” for this state. Say “existing source has some checked proof-shaped substrate, but full-check status was not established by this audit; the P0–P16 targets remain unimplemented/unverified.” The source audit explicitly did not run F* ([source_audit.md](../implementation_dag_2026-10-13/source_audit.md#L21)).

### 4. AST scope must be explicit

“AST” can mean two unrelated objects here: (1) first-order serialized `GraphDesc`/wire syntax; (2) custom, manifest-pinned schema-language AST used to prove type equality. Neither is F* compiler AST, quotation/reflection, arbitrary `Type0` reification, nor general SMT. Completeness is only for `SchemaSupported`; unknown equations reject ([implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L815), [implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L899), [source_audit.md](../implementation_dag_2026-10-13/source_audit.md#L23)). State this near first use, and call them “graph descriptor syntax” and “schema AST” consistently.

Accurate short wording: “The design supports arbitrary finite topology over the manifest-declared schema language. It does not reify arbitrary F* types or prove arbitrary type equalities.”

### 5. “Dynamic graph” does not mean arbitrary runtime topology or arbitrary types

Generator is intended as total pure function of exact input, pinned charge metric, and allocation. It returns a finite descriptor and aligned child plan. Its universal admission proof must establish graph/plan validity for every legal input/allocation; one sample generator result is insufficient. Root and generated graphs share resolver, graph language, journal, and recovery. Children become actionable only after exact graph/plan commit ([implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L489), [implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L1328), [implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L2672)).

Avoid phrasing like “the workflow can generate any graph at runtime.” Prefer: “A pinned generator may choose input-dependent finite topology; every result must lie in the supported schema language and satisfy universal admission/plan laws.” Topology expressivity is broad; type-language expressivity is bounded.

### 6. Dependent edge rule is static and universal

A producer output family may depend on its input. Consumer compatibility must be derivable from declared signatures and static graph constraints for every legal environment, including every member of an external node’s full declared result family. A runtime value, validator postcondition, edge proof payload, canonical codec, or observed sample cannot rescue a bad edge. Example: unconstrained `vector n` output cannot feed `vector 3` consumer; constrain `n` statically, change consumer interface to accept a package, or add explicit typed validation work ([implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L854), [key_correctness_theorems.md](../../schema_era_2026-10-14/key_correctness_theorems.md#L354)).

Guide must separate (a) node result has its indexed F* type, (b) edge is valid for all graph environments, and (c) committed value has correct origin. None implies the others alone ([key_correctness_theorems.md](../../schema_era_2026-10-14/key_correctness_theorems.md#L1)).

### 7. Contracts are strong assumptions about services, not guarantees delivered by pure F* model

Spec treats service law records as theorem parameters with proof fields, not unchecked `assume`; abstract theorems prove consequences conditional on those records ([implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L18)). This is a sensible proof boundary but can be misread as proving a real filesystem, adapter, or host. P10 is only an abstract exact-prefix/fencing theorem until a concrete journaler refines it; P13 is the later concrete simulation obligation. Strongest objection in independent audit: if P10’s exactness/monotonicity/fencing laws are simply supplied without a concrete proof, “durability proved” overclaims ([theorem_dag_audit.md](../implementation_dag_2026-10-13/theorem_dag_audit.md#L71)).

Use “under the stated journaler contract” every time discussing abstract crash-cut durability. State explicitly: no SQLite/filesystem journaler, extracted runner, scheduler, or real adapter is included in current plan ([state.md](../../schema_era_2026-10-14/state_summary.md#L25)).

### 8. External nondeterminism and exactly-once language need precision

Different logical call keys may return different accepted outputs, even for identical requests. Same-key retry/overlap/restart safety requires stable binding and a real adapter law (dedupe/status lookup or idempotent/reconciled operation). An untyped reply proves nothing. Liveness depends on adapter progress; impossible-to-reconcile remote effects are outside model. Journal gives one committed outcome per key, not general exactly-once physical execution ([implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L330), [implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L348), [implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L359)).

Avoid “exactly-once external calls.” Say: “The abstract contract preserves one logical effect/terminal receipt per committed key, conditional on adapter’s effect-safe resumption law; distinct keys remain nondeterministic.” P6 also permits pure local/generator recomputation before commit after crash, though committed result/graph is reused ([implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L2674), [implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L2673)).

### 9. Theorem status and P13 wording

P0–P16 are theorem targets, not completed results. Current active DAG’s acceptance demands actual machine-checked source proof and full-check evidence, with no `assume`/`admit` in theorem path ([work_dag.md](../../schema_era_2026-10-14/state/work_dag.md#L1), [implementation_packet.md](../../schema_era_2026-10-14/implementation_packet.md#L373)). P13 naming is especially easy to overstate: active objective includes a **generic refinement-transfer theorem**, but no concrete runtime instance; state says host-specific P13 remains later work ([state.md](../../schema_era_2026-10-14/state_summary.md#L3), [work_dag.md](../../schema_era_2026-10-14/state/work_dag.md#L14)). The spec’s P13 row describes implementation obligations for a chosen runtime, whereas A33 plans generic interface/transfer schema. Explain both meanings; do not say P13 is proven or “the system refines a runtime.”

P14 termination is conditional on fairness, service/callback progress, finite fuel, finitely many crashes and related premises. Frontier/action existence (P11) is not eventual completion. P15 safety requires no fairness ([implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L2679), [implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L2682)).

### 10. Artifact/resource safety is optional extension

P9 applies only when promising durable backing-object identity. Base references may be typed opaque values; durable publication, immutable versions, and same logical object after restart require separate artifact-store contract ([implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L2677), [implementation_spec.md](../../schema_era_2026-10-14/implementation_spec.md#L2683)). Avoid describing every artifact reference as already durable or recoverable.

### 11. Examples are shapes, not completed examples

Packet lists six proof-bearing examples for future construction; examples must be actual F* proofs after core theorems exist and cannot replace generic proofs ([implementation_packet.md](../../schema_era_2026-10-14/implementation_packet.md#L530)). Current source has a chain example, not arbitrary joins/fan-out, nested dynamic graph families, multi-key out-of-order adapter, or recovery proof ([source_audit.md](../implementation_dag_2026-10-13/source_audit.md#L18), [work_dag.md](../../schema_era_2026-10-14/state/work_dag.md#L230)). A guide may include schematic examples, but label as illustrative/pseudocode unless linked to current checked source. The `vector n` example is a counterexample/explanation, not an implemented workflow.

## Recommended reading order for a user guide

1. Start with status and scope: `state/state.md` plus active `state/work_dag.md`; explain current source baseline from `source_audit.md`.
2. Read `implementation_spec.md` for normative semantics: API, contracts, schema/graph rules, journal/execution/recovery; use §6 P0–P16 as target index.
3. Read `key_correctness_theorems.md` for why dependent typing, provenance, authorization, and recovery are separate.
4. Read `graph_and_recovery_guide.md` for graph construction and restart walkthrough; mark all theorem descriptions as targets.
5. Read `implementation_packet.md` for proposed module boundaries, proof order, acceptance checklist, and example shapes. It is subordinate to spec, not an alternate semantics source.
6. Read `source_audit.md` last to compare target with current `.fst` evidence; check exact source and DAG status before making “implemented,” “proved,” or “verified” claims.

## Suggested guide wording

> This repository contains a normative abstract F* workflow specification, a proposed implementation/proof packet, explanatory theorem and graph guides, and an older partial F* source skeleton. The specification describes intended guarantees conditional on explicit service contracts; it is not itself a verified implementation. The current A00–H5 DAG is planned and unstarted. Existing source includes useful typed graph/codec examples, but generic resolver/builder proofs, replay, controller, journal durability, recovery, and P0–P16 theorem results remain open. No concrete host/runtime instance is planned here.

Before publication, resolve or explicitly note stale S2-active wording in theorem guide and registry. A lineage section should distinguish old V2 implementation DAG/source work, S2 specification/packet design, and current A00–H5 proof DAG; avoid calling any one “the original spec” without exact artifact/date.
