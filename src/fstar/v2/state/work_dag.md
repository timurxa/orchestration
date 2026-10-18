# F* v2 theorem work DAG

**Status: previous spline, parked pending redesign.** The current working
design is the [event-driven state-machine API WIP](../theory/state_machine_api_wip.typ).
The tasks below track the earlier system specification and should not be read
as the current proof order. The former package-owned work DAG is preserved in the
[archive](../archive/2026-10-14/package_owned_work_dag.md).

## Previous proof spline

| ID | Work | Depends on | Acceptance | Status |
|---|---|---|---|---|
| S0 | Formalize the `T0` vocabulary and whole-run soundness proposition | — | F* typechecks the generic proposition over exact package bundles, journal contracts, typed roots, and all permitted finite traces. Do not export an unproved theorem declaration or use `admit`, `assume`, or an axiom for the result. | not_started |
| S1 | Formalize `SystemInvariant` and prefix indexing | S0 | Each invariant clause is independent of `T0` and implies typed successful output, exact committed prefix, and no committed redispatch. | not_started |
| S2 | Prove initial-state invariant and trace induction | S1 | Prove `T2a` and `T1`; derive all-prefix safety for arbitrary permitted schedules. | not_started |
| S3 | Define `Step` and prove one-step preservation | S2 | Each transition constructor has a visible `T2b` proof case; no case assumes its postcondition. | not_started |
| S4 | Discharge package-owned transition obligations | S3 | Prove indexed codec, code, operation, generator, graph codec, and exact package-resolution contracts used by `T3`/`T4`. | not_started |
| S5 | Discharge journal authorization and recovery obligations | S3 | Prove valid genesis, exact-head append history, complete immutable cuts, fold agreement, and writer fencing used by `T5`. | not_started |
| S6 | Prove concrete refinement and trust boundary | S4, S5 | A selected runtime refines the abstract contracts, with every trusted host premise explicit. | not_started |
| S7 | Decide and prove conditional progress | S6 | If termination remains in scope, prove `T7` only under explicit fairness, availability, finite-fuel, and finite-crash assumptions. | not_started |

## Previous working rule

Implement downward from `T0`: first make the strongest useful whole-run
statement typecheck in F*, then prove its induction and preservation
structure. Introduce a lower-level lemma only when its contract is required
by a named parent theorem. An unfinished obligation stays a goal; it does not
become an admitted fact.

Preserve earlier audits, research notes, and run history as historical
evidence. Do not copy their former P0–P16 status tables into this active plan;
the archived draft retains that mapping without maintaining a second
implementation ordering.
