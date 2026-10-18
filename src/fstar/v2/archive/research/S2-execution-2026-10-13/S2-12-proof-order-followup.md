# S2-12 follow-up — Packet dependency check

**PASS.** Packet’s theorem order and stated prerequisites match `implementation_spec.md` §6 and `key_correctness_theorems.md` by dependency closure. No cycle found. P12 is scheduled after P15 in packet for convenience, but has no P15 prerequisite and may be proved earlier.

## Exact dependency check

| Target | Spec / guide dependency | Packet match |
|---|---|---|
| P4 | P1–P3 | Stage D after P3; Generation module owns universal admission and typed splice. |
| P6 | P0/P3 (guide also names P2, transitively via P3) | Stage D; Provenance module owns local-origin result. |
| P7 | P0/P3 (guide also names P2, transitively via P3) | Stage D; Provenance/service contract owns keyed adapter receipt/effect law. |
| P10 | P0–P3 plus journaler contract | Stage D after P3; packet explicitly says P10 does not need P4–P8. |
| P5 | P2/P4/P10 | Stage E; Recovery module owner. Prereqs and placement correct. |
| P8 | P3/P4/P7 | Stage E; BudgetProof module owner. Prereqs and placement correct. |
| P9 | P0–P3 plus artifact-store law; optional extension to P15/P16/P13 only for persistent backing identity | Packet keeps optional theorem branch and conditional extension. Correct. |
| P11 | P1–P8/P15 | Stage G after P15; Progress module. Correct. |
| P12 | P3–P8 | Stage G; Progress module. Correct dependency; P15 ordering optional, not required. |
| P13 | P0–P8/P10–P12/P15; P9 only for resource identity | Stage H after P15/P11/P12; Refinement module. Correct. |
| P14 | P11–P13 plus fairness/service premises | Stage H after P13; Termination module. Correct. |
| P15 | P0–P8/P10 | Stage F; Controller module. Correct; P9 conditional. |
| P16 | P0–P8/P10/P15; P9 only for backing identity | Stage G after P15; Recovery module. P5 remains an explicit dependency/owner even though shorthand P0–P8 includes it. Correct. |

Packet proof order is topological: P0; P1/P2; P3; P4/P6/P7/P10; P5/P8/(optional P9); P15; P11/P12/P16; P13; P14. This satisfies spec §6. P13 and P16 are separate branches after abstract safety: P13 refines concrete runtime to P10/P15 contracts; P16 composes abstract every-cut semantics. Concrete recovered-system claim requires both.

## Generated graphs and recovery

Packet assigns P1/P2 to graph resolver/builder and canonical syntax/resolution; P4 to generator admission, exact graph/plan, and global typed splice; P5 to exact `GraphCommitted` graph/plan recovery. These match spec P1–P5 and guide’s `TypedEdges`/`CommittedGenerator` obligations. Acceptance must remain universal over every legal internal port environment, exact generator input/allocation, and all validator-accepted external outputs; sampled outputs cannot establish edge typing ([packet, lines 230–243, 326–329, 353–368](../../schema_era_2026-10-14/implementation_packet.md#L230); [spec, lines 2668–2675](../../schema_era_2026-10-14/implementation_spec.md#L2668); [guide, lines 181–230](../../schema_era_2026-10-14/key_correctness_theorems.md#L181)).

Packet separates cut facts correctly: P10 proves exact canonical loaded prefix, atomicity/monotonicity, and old-request fencing; P15 proves abstract authorization and all-interleaving safety assuming P10; P16 transports authorization/provenance and graph/result correctness through every cut. P13 proves concrete runtime, journaler, and barrier refine those contracts; it does not substitute for P15/P16 ([packet, lines 311–342, 390–406](../../schema_era_2026-10-14/implementation_packet.md#L311); [spec, lines 2301–2376, 2547–2618](../../schema_era_2026-10-14/implementation_spec.md#L2301)).

## Cycle check and strongest objection

No cycle: P15 depends on P10, not P13; P11 depends on P15; P13 then depends on P11/P12/P15; P14 is last. P16 depends on P10/P15, not P13. P9 has no mandatory edge into base P15/P16/P13. Module ownership also preserves direction: Recovery may import Controller for P16 while Controller does not import Recovery; BudgetProof owns P8 after P7/P4 inputs.

**Strongest objection:** Packet’s Stage G groups P11, P12, and P16, which can conceal prerequisite differences. P11 requires P15; P16 requires P15/P10 and P0–P8; P12 requires only P3–P8. This is legal but should not be misread as P12 depending on P15. A second safeguard: P5 must remain explicit in proof plans despite being covered by inclusive shorthand `P0–P8`; otherwise exact generated-topology recovery could be omitted accidentally. Packet already calls this out.

## Evidence anchors

- Packet proof order/dependencies: [implementation_packet.md, lines 316–406](../../schema_era_2026-10-14/implementation_packet.md#L316).
- Packet module ownership: [implementation_packet.md, lines 220–260](../../schema_era_2026-10-14/implementation_packet.md#L220).
- Normative target graph/table: [implementation_spec.md, lines 2635–2684](../../schema_era_2026-10-14/implementation_spec.md#L2635).
- Theorem guide spine and target contracts: [key_correctness_theorems.md, lines 100–177](../../schema_era_2026-10-14/key_correctness_theorems.md#L100); composition statement lines 181–250.
