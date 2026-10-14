# S2-06 crash and interleaving audit

Scope: adversarial read-only review of `implementation_spec.md` §§4.2–4.3, P15, and S2-06 acceptance row. No normative/source edits.

## Status and core boundary

**Target:** every abstract schedule preserves authorized journal history, typed `StateWF`, exact claim bindings, ledger invariants, commit-before-visibility, and recovery; P13 later proves concrete refinement.

**Established:** spec states these as contracts/theorems; S2-00 evidence ledger says P15 is absent from current source: no controller state, claims, interleaving relation, stale-head reauthorization, committed-only visibility, or all-schedule proof. The following is theorem design/audit, not discharged proof.

Durable state at each instant is `S = replay(J)` for latest committed prefix `J`. Volatile controller state is claims, in-flight adapter keys, candidates/results, append request. A crash discards all volatile state; P10 defines durable prefix selected at cut. Candidate results, worker progress, reservations not represented by committed events, and append requests are never recoverable workflow state.

## Exact visibility points

Visibility means workflow authority: usable to reconstruct inputs, enable dependents, or return as run output. It does not mean an external service cannot observe its own side effect.

| Item | Before commit | After commit/recovery |
|---|---|---|
| `RunStarted` | no run/root graph is authorized | root input, graph, plans, and budget become replay state |
| local result / `NodeCompleted` | worker candidate stays volatile; consumers cannot read it | typed output becomes committed; occurrence is absorbing/reused, never rerun |
| generator result / `GraphCommitted` | candidate descriptor/plan stays volatile; child graph/nodes/actions do not exist in state | exact committed graph bytes and lifted child plan become state; children may become ready; generator never chooses replacement topology |
| external `CallIntent` | adapter must not submit; no durable retry key exists | same keyed operation may be submitted/resumed; intent itself is durable, but no output is visible |
| external reply / `CallOutcome` | reply/evidence/charge/artifact refs stay candidate/unreferenced; consumers cannot read result | validated typed output and settlement become state; committed outcome reused, no redispatch |
| artifact backing | may be physically published before event; journal reference remains absent/unusable | reference visible only with containing authorized event; P9 needed to claim durable backing/same-object recovery |
| terminal output | not derived from uncommitted candidates | exposed only when root wire evaluates from committed values |

Commit point, not append invocation or acknowledgement, defines visibility. Crash after commit but before acknowledgement may recover new event; controller must reload. Before commit, artifacts may become orphaned; P15 without P9 gives no backing identity/reclamation claim. External effects may precede `CallOutcome`; P7 same-key effect-safe resumption handles retry, not journal invisibility of the physical effect.

## Adversarial schedules

1. **Dependency consumes volatile predecessor.** `A` ready; worker computes `a`, no `NodeCompleted` yet. Scheduler starts dependent `B` from candidate `a`; crash occurs. Journal lacks `a`, restart cannot reconstruct it, yet any downstream committed result would depend on uncommitted provenance. Rule: dependent readiness reads only committed outputs; `B` cannot be claimed before `A` event commits. `ReadyInputAgreement` must prove reconstructed input equals full graph evaluation for all environments agreeing on referenced committed ports, regardless of unrelated missing ports.

2. **Crash after local calculation, before append.** Worker returns `v`; crash before successful append linearization. Recovery sees old prefix, no completion. Recompute is permitted, including physical duplicate pure computation. No dependent ran on `v`; no claim of exactly-once physical computation. If append had committed before crash, P10 returns new prefix and occurrence must be reused without dispatch/recompute.

3. **Crash during generator before graph commit.** Generator returns `(d,plan)`; crash before `GraphCommitted`. Recovery has pending generator and no child graph/actions. Pure deterministic generator may recompute at committed input/allocation. Child cannot be observed or execute. If graph commit crossed linearization, recovery uses exact committed `d` and lifted plan; it must not call generator to replace either.

4. **Reverse completion order, stale head.** Independent `A,B` are both ready and claimed at `J0`. `B` returns/commits first, advancing to `J1`. `A` candidate arrives with auth proof indexed by `J0`; append at old head rejects. Coordinator reloads/replays `J1`, verifies `A` still pending, reconstructs same exact identity/input/allocation, and reauthorizes. If all match, pure result may be reused; else discard/recompute. Updating expected sequence alone is unsound. Then append `A` at `J1`. No order restriction beyond serial commit.

5. **Duplicate/stale worker response.** Old claim for occurrence `A` returns after its completion committed, or after claim was released/reissued. A pending-only check rejects after completion, but before completion a delayed old callback can collide with new claim. Model needs claim token/incarnation and claim ownership check, or must define claim as authorization-independent candidate and safely discard duplicates. Claim token cannot authorize append by itself; exact current-state reauthorization still required.

6. **Intent/dispatch crash window.** Dispatch before `CallIntent` commit can cause an effect with no durable key; restart may submit another. Forbidden: commit intent first, then dispatch only that committed intent. Crash after intent commit but before dispatch yields pending intent retried with same key. Crash after service effect/reply but before `CallOutcome` commit leaves output invisible and intent pending; same-key adapter resume/dedupe/query returns same logical operation outcome under P7. Physical exactly-once delivery is not P15's claim.

7. **Two stale authorizations race.** Two candidates derive at same head; only one append is active/linearized. First event commits. Second must see changed head and reconstruct state. If same occurrence was completed, reject; if an independent occurrence remains pending, rebuild authorization for the new state. Serial journal appends do not by themselves imply unique worker claims across multiple controllers.

## P15 formulation

Model controller `C=(J,V)` where `J` is committed journal and `V` contains finite claims keyed by occurrence with unique claim token, adapter in-flight keys, candidate results, and at most one append request. Define `S=R(J)`. Each transition is one of claim-ready, executor-return, adapter-return, append-success/reject, or crash/restart. Require every transition preserve these premises/invariants:

- initial `J` is authorized and `SemWF`/`StateWF`; `V=empty`;
- claims drawn only from duplicate-free frontier over `S`; local/generator claims use exact pinned identity, reconstructed typed input, committed allocation; no duplicate live claim per occurrence **within declared controller scope**;
- worker result cannot mutate `J` or feed dependents; candidate is tied to claim token and exact input/allocation/identity;
- adapter dispatch follows committed intent and uses its exact stable key; replies correlate by that key;
- append is sole durable write, serial, current-head fenced, event-specific authorized against freshly replayed `S`; stale result forces full reauthorization; rejection is no-op;
- crash empties `V` and reloads exactly P10 prefix; pending local/generator work may restart, committed local/generator work may not; pending intent resumes same effect-safe key, committed outcome does not dispatch;
- immutable graph/manifest and pinned code/codec contracts; P0–P8, P10 service/store contracts available; P9 only for physical artifact extension.

Then for every finite schedule prefix and each crash cut: `J` is an authorized legal prefix; `StateWF(R(J))`; no uncommitted value/graph/result enables a consumer; every claimed input/allocation matches current replay state; each committed event has exact `AuthorizedEvent` witness; ledgers preserve P8; terminal state absorbs; after restart `V=empty`, state is exactly `R(J)`; committed `NodeCompleted`/`GraphCommitted` are never claimed again; no claim of unique precommit physical pure computation. For each event, append history order equals commit linearization order, not launch or completion order.

This is safety. Fair scheduling, worker termination, adapter eventual outcomes, store progress, finite crashes, and eventual retry are separate P14 liveness premises.

## Missing/ambiguous premises to close

- **Claim scope:** prose says “a live occurrence has at most one claim,” but if multiple controllers are allowed, journal fencing only serializes appends; it does not provide cross-controller claim uniqueness. Either P15 assumes one controller per run, or weaken uniqueness to per-controller and prove duplicate pure work harmless; external duplicate dispatch still requires P7 key safety. Do not infer global uniqueness from a process-local mutex.
- **Crash worker lifetime:** “crash discards volatile claims” abstracts away whether child worker processes survive parent death or return late after restart. State premise that old executors are terminated, or make all old-epoch responses unclaimable using restart epoch/token and current-state reauthorization. Safety can allow duplicate pure calculation, but must prevent stale response from bypassing claim/result validation.
- **Claim release/retry:** define when failed/timed-out claims are removed and how retries obtain fresh tokens; otherwise delayed response can match a reused occurrence key. Occurrence key identifies work, not a unique attempt.
- **Candidate reuse on stale head:** specify admissibility: candidate can be retained only after exact current-state checks for pending status, pinned identity, reconstructed input, allocation, and event provenance. If any differ, discard/recompute. Same expected head replacement is never enough.
- **Append commit ambiguity:** process may die after linearization before ack. On restart replay decides event presence; do not also blindly retry candidate without checking completion/graph state.
- **Adapter boundary:** external side effect can happen before outcome journal commit. P15 must say “workflow result invisible” rather than imply physical service effect invisible. P7 owns retry/effect safety. An intent with no outcome is durable and resumable.
- **Artifacts:** artifact bytes/object can be created before reference event; crash may orphan them. P15 only controls references/dependent workflow visibility; P9 owns durable backing, identity, cleanup if claimed.
- **Safety quantification:** “every permitted schedule” needs a defined transition relation including crash at every boundary, arbitrary result order, reject/stale append, late response, and possibly restart. Current prose describes most steps but not formal small-step relation or claim-token semantics.
- **Prefix semantics:** P15 should inherit authorized-trace invariant, not assume it for each successor. Initial `RunStarted` needs root authorization; append induction proves each next witness against exact head. P10 transports witnesses across cuts; P15 alone does not prove physical store recovery.

## Conclusion

S2-06 core rule is sound: only committed values enable graph dependents; uncommitted local/generator candidates may repeat; committed work is absorbing; intent is durable before adapter dispatch; outcomes become visible only at commit; journal order follows serial commit. Main adversarial gap is scope/identity of volatile claims across crashes and controller incarnations, plus exact candidate reauthorization after stale head. Close those in abstract schedule semantics, then P13 refines worker/process behavior. No F* proof or test was run.
