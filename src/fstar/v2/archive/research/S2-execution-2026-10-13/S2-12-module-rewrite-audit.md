# S2-12 module rewrite audit

**Verdict: FAIL.** Prior P2/P4 ownership gaps are fixed. One P4/P8 dependency back-edge remains.

## Confirmed

- **P2:** `GraphInterpretation` now owns composition of GraphCodec, GraphResolve, and Bundle; dependency direction is acyclic and meets typed roundtrip requirement ([packet lines 231–233](../../schema_era_2026-10-14/implementation_packet.md#3-required-source-module-architecture); [spec P2](../../schema_era_2026-10-14/implementation_spec.md#6-required-proofs)).
- **Generator admission:** `GeneratorAdmission` sits below Builder, supplies `GeneratorMember`, and avoids Builder/Generation cycle ([packet lines 235–237, 258–259](../../schema_era_2026-10-14/implementation_packet.md#3-required-source-module-architecture)).
- **P4/P5/P16 split:** `GraphCommitProof` owns complete P4; `GraphRecovery` owns P5 without P15; `Recovery` composes P16 with ControllerSafety/P15 ([packet lines 245–248, 263–265](../../schema_era_2026-10-14/implementation_packet.md#3-required-source-module-architecture)). P5 therefore avoids unnecessary P15 dependency, consistent with spec dependencies.
- No other definite cycle found in listed edges. Services/Journaling/Provenance direction and optional Artifacts boundary are explicitly constrained ([packet lines 238–243, 259–267](../../schema_era_2026-10-14/implementation_packet.md#3-required-source-module-architecture)).

## Blocker: P4 imports P8 before P8 can depend on P4

`GraphCommitProof` owns P4 and imports `ControllerModel` ([packet line 245](../../schema_era_2026-10-14/implementation_packet.md#3-required-source-module-architecture)). `ControllerModel` imports `BudgetProof` ([line 244]), which owns P8 ([line 242]). Yet normative P8 depends on P4 ([spec line 2676](../../schema_era_2026-10-14/implementation_spec.md#6-required-proofs)), and packet proof order puts P4 before P8 ([lines 337–339](../../schema_era_2026-10-14/implementation_packet.md#5-proof-order-and-dependency-spine)). Current module path therefore makes P4's proof module depend on the P8 module while P8's theorem depends on P4: module/proof order conflicts.

**Fix:** move budget state types, transition equations, and projections needed by ControllerModel into a lower `BudgetModel`/`LedgerKernel` module. Make ControllerModel import that model, not theorem-bearing `BudgetProof`; keep P8 in later `BudgetProof` after P4. Alternatively split P4's generation-only premise and explicitly state which sublemma P8 uses, while preserving normative P4/P8 theorem dependencies and avoiding a back-edge.

**Strongest objection:** proof order says P4 unlocks P8, but P4's owner imports the module that owns P8. Without separating budget model from P8 theorem, required order cannot be implemented cleanly.
