# S2-10 P14 audit — conditional termination under concurrency

**Result: PASS with explicit fairness and service premises.** The review
checked P14 against the serial journaler, multi-inflight adapter, P7 retry
contract, P8/P9 ledgers/resources, and P15 controller interleavings.

The assumptions are compositional and do not require concurrent journal
writes. Local/generator work and distinct external keys may complete in any
order; each validated candidate enters the single serial append path. The
finite adapter capacity is compatible with progress when completed responses
are consumed fairly, freeing slots, and P7 ensures each admitted key reaches
one terminal receipt or definitive reconciliation under fair retry/query.
Artifact resolution progress is needed only for a workflow action that
resolves a resource. Store progress and append fencing remain serial P10/P13
obligations. P11 gives an enabled logical action, P12 prevents infinite
successful append sequences, and P13 refines the fairness/service rules in a
concrete runtime.

Two scope ambiguities were corrected: P14 begins only after an accepted
`RunStarted`, and its weak-fairness premises now specify continuously enabled
claims, returning local/generator results, appending completed candidates,
stale-head reauthorization, response consumption, and capacity release. This
also separates semantic termination (`Tot`) from the concrete executor's
obligation to return the result to the controller. P7 retains fair retry/query
and eventual terminal outcome/reconciliation per admitted key; P14 requires
finitely many process exits and any needed artifact-store resolution progress.

Reviewer: `/root/s208_combined_audit`; follow-up on P11/P14 scope and fairness
was accepted. `/root/s208_charge_ledger` separately confirmed the updated P11
separation and P14 scope; its executor-return precision suggestion was added
to the spec and this report. No concurrency contradiction or need for a
parallel journaler was found. No F* source, implementation, verifier, or tests
were touched.
