# P15 provenance induction review

Read-only adversarial review of revised P15 formula and `ExecutorSafetyInvariant` against S2-05 `SemWF`/`AppendPermit` and bootstrap `RunStarted`. No F*, tests, or source changes. These are proof-target observations, not discharged results.

## Verdict

The induction is **non-circular in its intended shape**. `AppendPermit` requires current replay, `StateWF`, `EventGuard`, and event-specific `AuthorizedEvent`; append linearization extends the same history used by `SemWF`. `InitialAuthorized(C0,R)` now covers either an authorized already-started prefix or the unstarted empty journal; `ControllerStep_R` has an explicit bootstrap transition constructing the exact pinned root result. Thus `RunStarted` is not missing from the authorization cases.

One proof-carrying detail remains ambiguous: `Return/cancel` says executor/validator return carries a proof witness, but `Candidate` stores only result data. The invariant says candidates satisfy “token/argument rules,” without explicitly retaining or existentially preserving the semantic equality/validation witness needed to build the later `AppendPermit`. Make candidate validity include that witness (as a proof field or ghost invariant), or prove exact result again at prepare-append. Without one, value-only candidate can lose its provenance between return and authorization.

## Case-by-case induction check

**Base — empty/unstarted.** `replay_C([])=Ok(initial_state(C))`; `T=[]`; `SemWF(C,[],[],initial_state(C))` holds by empty prefix/vacuous witness clauses, assuming its definition does not require every `T` itself to start with `RunStarted`. `InitialAuthorized` must not demand a root witness before root event exists. Empty base is bootstrap, not a started-run progress claim.

**Bootstrap — `RunStarted`.** This is separate from `WorkAction`, allowed only from unstarted state, no node claim first. `R` supplies root input/budget/entrypoint; bootstrap computes exact `RootEntry.start` result and commits one event through `append_authorized`, so `AppendPermit` needs `AuthorizedEvent(C,initial_state,e)` covering canonical input, graph bytes, exact plan, pinned registry/entrypoint, run identity and budget. On commit, append trace becomes `[RunStarted]`; `SemWF` has the root witness and replay state has root graph. Crash before commit leaves empty journal and permits resubmission; crash after commit recovers root event, never consults R. This closes base if `InitialAuthorized`/bootstrap share one exact request and there cannot be a mismatched second request after commit.

**Claim / worker return.** Claims bind attempt ID, occurrence, pinned identity, exact reconstructed input, allocation. Readiness and `ReadyInputAgreement` connect the input to committed predecessor values. Return contract proves `result = CodeRef.run(x)` or exact generator result at `(x,a)`. Candidate must preserve this fact; a token only identifies an attempt and is not authorization. Current append preparation then replays latest head, verifies pending status and same exact bindings, builds constructor-specific `AuthorizedEvent`, and supplies `AppendPermit`.

**External events.** `CallIntent` is a separate authorized append before dispatch; its witness must bind exact ready operation, request, key, resume contract. Reply candidate must preserve P7 evidence that same keyed intent/reply passes pinned validator at exact reconstructed input. `CallOutcome` then gets fresh `AuthorizedEvent`; no output visible before commit. This event-specific chain is present in the spec, though candidate proof retention should include adapter evidence/validation as well.

**Success / stale / crash.** Successful append linearization adds exactly event and its witness to `T`; replay/apply establishes `StateWF`; hence `SemWF` extends by one. Stale append changes no journal and invalidates old permit; fresh replay and all input/allocation/provenance checks needed. Crash truncation/reload is justified by P10, which must select prefix of this same append history; ghost witnesses restrict to prefix. Do not have P15 assume P10 has proved host behavior; conditional P10 cut law is a premise, and later S2-09/P13 owns refinement.

## Potential circularity / logical seams

1. **AppendPermit is not the circular premise by itself.** If `ControllerStep` requires constructing `AppendPermit` before `append_authorized`, and local/generator/adapter service records provide value-level contract proofs, P15 proves the constructor case from those proofs and current-state bindings. Circularity would arise if the step relation defines “permitted” as “already authorized” without exposing proof construction, or P15 assumes its own SemWF-preservation conclusion.
2. **Candidate witness gap.** Current `Candidate` constructors list data only (`typed_output`; `descriptor, graph_local_plan`; validated value/evidence/charge). Return step says witness is carried, but no field/invariant says it survives into candidate. State either a `candidate_valid` proposition retaining code/generator/validator equality and attempt binding, or candidate type carrying proof. Otherwise append-preparation's fresh proof is ungrounded unless it recomputes.
3. **History/prefix identity.** `T_i` is successful linearization history; invariant has `J = latest committed prefix` and `SemWF(C,T,J,S)`. Require exact relation between `T_i` and journal prefix at each step/cut. For a live no-cut state, every linearized append should be in current prefix; after cut, P10 returns that prefix and no later linearization is retained. Prefix-only relation suffices for witness restriction only if every event skipped from `T_i` is uncommitted/after cut; specify this in P10CutLaw.
4. **Already-started initial `C0`.** `InitialAuthorized` wording handles it only if it asserts the complete `SemWF`/authorized append history for its prefix, not just a root-event witness detached from later events. Prefer require initial prefix either empty, or prefix of authorized trace whose every event carries witness. For normal induction start from empty and derive later events; started-prefix form is a convenience corollary.
5. **Bootstrap repeat/replacement.** Since `StartRequest` is read only while journal empty, state request/run identity binding and `RunStarted` absorbing guard ensure a second/mismatched request cannot replace it. `append_authorized` serial expected-prefix alone does not establish this; `EventGuard` + `AuthorizedEvent` on unstarted state do.

## Minimal repair

Add a ghost validity clause to `ExecutorSafetyInvariant`:

```text
forall candidate in C.candidates:
  exists live_claim, origin_witness.
    candidate.attempt_id = live_claim.attempt_id
    /\\ exact current/rederived occurrence identity, input, allocation match claim
    /\\ origin_witness proves candidate payload equals pinned CodeRef/GeneratorRef result
       or P7 keyed validator result at those exact arguments
```

Or place witness in `Candidate` as a dependent proof field. At append preparation, consume witness only after revalidation at current replay; derive fresh `AuthorizedEvent` from same exact payload and state. For `RunStarted`, define `InitialAuthorized` as `J=[]` or `J` plus its complete authorized `SemWF` history, and make bootstrap event proof explicitly `RootEntry.start(R.input,R.budget)` equality.

## Conclusion

No missing event authorization constructor found: root, generator, local, intent, and outcome cases are all named; `CallOutcome` remains conditional on P7, crash continuation on P10. Formula has valid empty bootstrap base and an explicit authorized `RunStarted` step. Main residual risk is provenance witness loss between worker return and append preparation, plus exact `T_i`/loaded-prefix relation at restart. P15 remains a theorem target; no proof follows from this review.
