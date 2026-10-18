# S2-10 P11 audit — enabled frontier and no-stuck

**Result: PASS, conditional on P14 service premises for progress.** This is a
read-only review of the S2-10 acceptance rule against `implementation_spec.md`
§§2.1, 4.2, and 5.

The logical frontier cases match the durable state:

- ready unexpanded local occurrence: `RunLocal`;
- ready unexpanded generator: `GenerateGraph`;
- ready external occurrence with no intent: `BeginExternal`;
- committed pending intent: same-key `ResumeCall`.

Committed completion/expansion removes an occurrence from the frontier.
Dependency-local readiness is valid under `ReadyInputAgreement`; a finite DAG
with unfinished vertices has a ready vertex. Empty or constant-output root
graphs are terminal once their root input is committed and their output wire
is derived. Disconnected/dead vertices are still required to complete because
terminality is based on the declared root result, not reachability pruning.

Adapter capacity does not belong in logical frontier membership. A full
in-flight bound can delay `BeginExternal` physically while the logical action
exists; fair consumption of any completed response and eventual key outcome
are P14 premises. A permanently nonterminating request can therefore prevent
termination without falsifying P11.

The first review found one wording issue: §5 appeared to make store and adapter
progress part of P11. It is now explicit that P11 proves legal continuation
existence only. Eventual service is P14. The exact constructor-wise action
definition was already present in §4.2, so no additional abstraction or DAG
change was needed.

Reviewed by `/root/s208_charge_ledger`; no counterexample found. No F* source,
implementation, verifier, or tests were touched.
