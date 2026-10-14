# S2-09 P16 semantic recovery audit

Read-only review of the P16 composition in `implementation_spec.md` and
`key_correctness_theorems.md`. No F* source or tests were changed.

## Result

Pass after making one predicate trace-indexed. Replay state alone cannot
establish a historical no-redispatch property, so P16 now separates
`NoPostCommitExecution(tau)` from the state-local fact that committed work is
absent from the recovered frontier.

## Composition checked

1. P10 loads the exact latest committed prefix at the post-exit recovery-load
   barrier. P15 discards volatile claims/candidates and starts scheduling only
   after that barrier.
2. `SemWF` carries the append-time `AuthorizedEvent` witnesses as ghost
   history. P10 chooses a prefix of that same authorized history; P16
   transports its provenance without serializing witnesses or rerunning work.
3. P1/P2 resolve root and committed generated graphs through the same pinned
   schema and establish universal dependent edge typing. P4 proves each
   generated graph's result and allocation at its exact input; P5 reuses the
   committed descriptor and lifted plan.
4. P6/P7 establish exact local/external result provenance. P15 proves
   dispatch/claim safety over every controller schedule. P16 includes exact
   completed values and topology at every cut.
5. A pending intent already present at the cut retries under the exact
   committed operation/key/request/resume binding and P7's one-effect
   reconciliation law. Liveness remains P14, not part of safety.
6. P9 remains optional for base workflow correctness and extends the claim to
   physical immutable resource identity when supplied.

The formerly state-indexed no-redispatch wording was corrected to a
trace-indexed predicate, with `CommittedOccurrencesAbsentFromFrontier(S_c)`
as a separate replay-state corollary. `PendingIntentRetryBoundAtCut(tau,c,J_c)`
quantifies only over intents pending in `J_c`; later calls are handled by the
full-trace P15 invariant and cannot be incorrectly required to occur in an
earlier cut prefix.

## Reviewer provenance

- `/root/s208_artifact_contract` found the initial state/trace scope mismatch
  and verified the corrected predicates, exact pending-call binding, and
  P10/P15 composition.
- `/root/s208_combined_audit` checked the corrected cut scope and found no
  remaining mismatch or counterexample.
