# S2-10 P12 audit — strict progress rank

**Result: PASS after a theorem-guide correction.** Reviewed against the P4
allocation rules and P8 ledgers in `implementation_spec.md` §§2.1, 4.3, and 5.

Use lexicographic rank `(G,U,W)` over naturals. `G` is the sum of assigned
fuel for unexpanded generators; `U` is their count; `W` sums local/external
phase ranks (local pending 1, external pending 2, intent 1, complete 0).

- For a generator with parent fuel `b > 0`, P4 assigns nested generator fuel
  with sum `F < b`. Replacing the parent allocation by these children strictly
  lowers `G` regardless of the finite number of ordinary nodes produced.
- For `b = 0`, P4 still requires every nested generator to receive positive
  fuel, so there can be no child generators. `G` stays equal and `U` drops by
  one, regardless of added ordinary nodes.
- Root generators may have zero fuel; nested generators may not.
- `NodeCompleted`, `CallIntent`, and `CallOutcome` preserve `G,U` and each
  lower `W` by one.

Each committed event is serialized by the single journaler, so the argument
holds in any order of concurrent task completions. Stale append attempts are
not state transitions. Finiteness of each graph and natural allocations gives
a finite rank at every finite prefix; the initial started graph therefore
has a finite rank. P12 excludes infinite successful journal-append traces,
not executor stutter or adapter nontermination; P14 supplies service and
fairness assumptions.

The theorem guide previously claimed zero-fuel child generators needed no
restriction. That contradicted P4's positive nested-fuel rule and broke the
`b = 0` case. It now states the root/child distinction and agrees with the
normative spec. `/root/s208_artifact_contract` independently re-reviewed the
correction and confirmed no remaining rank counterexample. No DAG scope or
topology changed. No F* source, implementation, verifier, or tests were
touched.
