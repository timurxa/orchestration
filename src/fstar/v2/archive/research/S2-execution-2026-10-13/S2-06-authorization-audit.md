# S2-06 authorization and executor audit

Read-only audit of current S2-05/P15 boundary, `implementation_spec.md` §§4.1–4.3, theorem guide, and S2-06 acceptance. No F* or tests. Findings concern theorem targets; no source theorem is discharged.

## Verdict

S2-05/P15 boundary is now coherent in principle: `append_authorized` requires `AppendPermit` with `AuthorizedEvent(C,S,e)`, while `apply`/`StateWF` establish only structural validity. This avoids deriving semantic provenance from replay. P15 may assume a semantically well-formed starting prefix for an induction step, but must separately identify authorized `RunStarted` as base and prove closure for every executor transition. No circularity is necessary.

**S2-06 acceptance remains open.** The prose describes the right cases but still lacks a formal controller state and step relation over which “every permitted schedule” can be proved. In particular, “claims are distinct” is currently scheduler precondition, not an inductive uniqueness result; exact input/result bindings need claim-token semantics; and “not rerun after commit” needs a precise distinction between no new scheduling from replay and a task already dispatched before commit that returns late.

## Authorization chain, end to end

Required chain for local/generator action:

1. `S = replay_C(J)`; occurrence belongs to committed root/child graph and is pending in `S`.
2. Readiness depends only on committed referenced outputs. Reconstruct typed input `x` from those outputs and root/constants; load occurrence-local allocation `a` from replayed plan/ledger.
3. Claim binds `(occurrence, pinned identity, x, a, claim incarnation)`; executor receives those exact arguments. Its proof-bearing contract returns `CodeRef.run(x)` or `GeneratorRef.generate_graph(x,a)` result.
4. On result, reload/replay latest prefix. Check occurrence still pending and exact identity/input/allocation still match; encode result canonically. Construct `AuthorizedEvent(C,S',e)` at this current state, not from the old claim head alone.
5. Submit exactly `(prefix,e,AppendPermit)` to sole serial `append_authorized`. Commit point makes event and result visible; `Stale` changes nothing and forces reload/reconstruction/reauthorization.
6. Replay derives completion or child graph from committed event. New frontier excludes completed local work and committed generator. On crash, volatile claims/results disappear; P10 loads committed prefix; frontier derives from replay, not from old process flags.

This chain supports local/generator provenance if service return laws are proof-bearing assumptions and `AuthorizedEvent` equality is tied to exact pinned function, exact current input/allocation, exact event payload, and canonical codec. A mere worker assertion that it ran the right function is insufficient. P13 must later show concrete executor/controller and private raw journal path refine these laws.

External operations follow same append discipline but different origin: `CallIntent` must commit before dispatch; `CallOutcome` must match that durable key/request and validator at exact reconstructed input. Adapter retry/effect safety is P7, not inferred from P15. P15 must keep this distinction: intent persists across crash; uncommitted reply is invisible; committed outcome is reused without redispatch.

## Adversarial schedules and obligations

| Schedule | Correct result | Required proof not yet explicit in P15 model |
|---|---|---|
| Two claim attempts for same ready occurrence at same replay head | One atomic claim wins; second rejected. | Define controller claim transition/linearization and prove map uniqueness inductively. “Scheduler chooses distinct claims” only constrains valid schedules; it does not model racing scheduler attempts. State scope: one abstract controller, or cross-controller fencing/lease. Journal CAS alone fences appends, not claims. |
| Two different ready occurrences claimed; later unrelated event commits first | Candidate may be reused only after reload/replay and full reauthorization at new head. | Prove frame lemma: unrelated append cannot change this occurrence's graph/ref, referenced committed outputs, reconstructed input, pinned identity, or occurrence allocation. If it did change any, discard/recompute. Updating head only is invalid. |
| Candidate's producer was uncommitted at claim time | Such candidate cannot be a ready action. | Prove frontier iff every referenced output is committed; `ReadyInputAgreement` must quantify over all full legal `PortEnv`s agreeing on sparse refs and include constants/root input and child graph boundary index. |
| Claimed local result returns after same occurrence committed by another controller/old attempt | Result cannot append or become visible; no new execution should have been scheduled from committed replay. | Bind result to unique claim incarnation and check current pending status. Define how late callbacks after crash/restart are handled. Same occurrence key is not a unique attempt token. |
| Crash after result, before commit | Restart may recompute pure local/generator work; no dependents consumed candidate. | Crash transition clears volatile state and leaves journal unchanged if commit point not passed. Prove all visibility derives from replay. Duplicate physical pure computation before commit is allowed. |
| Crash after commit, before acknowledgement | Restart sees new prefix and must reuse committed local result/graph; blind retry cannot append/execute again. | Compose commit linearization with P10 cut law. Recovery/frontier must ignore stale volatile “pending” status. |
| Candidate has stale old-head `AppendPermit` | Stale append leaves store unchanged; witness cannot be retargeted. | Current `AppendPermit` indexing handles this; P15 still must prove reload, reconstruction, and fresh authorization transition, not assume successful append from stale candidate. |
| Generator A commits while distinct generator B computes | A's child nodes appear after A commit; B can commit only with same exact current input/allocation/result and injective child occurrence. | Compose P4 splice/lift with disjoint-append frame theorem; prove B's allocation is occurrence-local and not altered/consumed by A. |

## Circularity check

Safe induction shape:

```text
Base: authorized RunStarted append from initial_state(C), with SemWF.
Step: SemWF(C,T,J,S) plus one controller transition.
  volatile-only step: J/T unchanged; preserve claim/candidate invariants.
  successful append: current-state AppendPermit supplies AuthorizedEvent;
    append appends exactly its event; extend T and SemWF by one witness.
  stale append: journal unchanged; discard/re-authorize candidate; no trace event.
  crash/restart: P10 selects prefix of T; clear volatile controller state;
    recover by replay; restrict existing witnesses to prefix.
```

This is non-circular if `AuthorizedEvent` is proved by pinned functions/codecs and executor/validator contracts plus current-state checks, and append contract only commits the supplied permitted event. It is circular if P15 assumes “every result is authorized” as an executor service premise rather than deriving it from exact argument/result binding, or assumes its own closure as the allowed-schedule definition. Service contracts may establish that a worker return equals `CodeRef.run(x)`; P15 must still show worker `x` is the current reconstructed input and the event bytes encode that returned value. Likewise, `SemWF` is a starting-prefix induction hypothesis, not a substitute for proving the initial event and all transition cases.

## No-rerun-after-commit: exact claim

P15 can prove **no new dispatch/claim of a committed local occurrence or committed generator** because each schedule step selects from frontier of current replay state, and `StateWF` makes completion/graph commitment absorbing. It cannot mean “no physical task can finish after the commit”: a task might have been launched before commit through another controller or an old process surviving a crash. That late result must be non-authoritative and fail pending/current-claim revalidation. Exactly-once precommit physical local computation is explicitly not promised.

Choose one model boundary: either one controller owns each run and crash terminates all its workers, or multiple/restarted controllers may overlap and claim incarnations/epochs make old results unclaimable. If duplicate pure calculation is allowed, state no-rerun as no new replay-derived scheduling after commit and prove stale results cannot append. External duplicate physical effects remain subject to P7 stable-key contract.

## Minimal proof contracts to close S2-06

1. Define abstract controller state and labeled atomic steps: `claim`, local/generator return, intent dispatch, adapter return, `append_authorized` success/stale, crash/restart. Define volatile candidate/result storage and single append slot.
2. State claim scope and prove unique live claims from transitions; include claim incarnation/token to distinguish a retry/late result from same occurrence's new attempt.
3. Prove `ReadyInputAgreement` with exact quantifiers and a dependency-local frame theorem. Readiness is only referenced committed outputs, not topological prefix completion.
4. Prove result reauthorization on latest replay head: pending status; same pinned work; same reconstructed input; same allocation; canonical event encodes exact service return. Stale head forces these checks again; no witness retargeting.
5. Prove current-head `AppendPermit` plus append success extends `SemWF`; stale append/rejection is journal no-op. Only commit linearization exposes result or generated children.
6. Crash clears volatile claims/candidates; P10 supplies exact prefix; frontier rebuilt from it. A committed `NodeCompleted`/`GraphCommitted` is reused, never scheduled; pending pure work may recompute. Define treatment of late responses if old workers can outlive controller.
7. Keep P7 adapter effect safety, P8 allocation conservation, P9 physical artifact identity, P10 physical store cuts, and P13 host refinement as named dependencies. P15 alone cannot prove those host properties.

## Acceptance and evidence

Against S2-06 DAG row, current normative prose satisfies design intent for readiness, exact bindings, current-head reauthorization, serial append, committed-only visibility, arbitrary completion order, and crash reset. It does not yet define enough operational semantics to derive uniqueness, all-schedule closure, or post-commit non-dispatch formally. Verdict: **acceptance conditional on controller step model and claim/restart scope above**. This is design feedback only; P15 remains a target. Current S2-00 evidence ledger records no source controller, claims, transition relation, or P15 proof. No F* theorem has been established by this audit.
