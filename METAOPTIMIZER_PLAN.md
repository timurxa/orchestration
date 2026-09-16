# Orchestration Metaoptimizer Plan and State

Status: frozen; final optimizer launch pending

## Objective

Implement first bounded linear metaoptimizer `M`.

`M` creates candidate orchestration programs `B`. Each `B` uses a physical copy of
`src/api`, compiles, runs, creates rigidbody simulator `A`, verifies and benchmarks
`A`, inspects its own artifacts, then emits mutation evidence.

Final action: freeze and verify `M`, run optimizer once, record results, stop all
work. No edits or commands after optimizer run.

## Frozen budgets

- Per `B` run: `50.0` Vecherinka budget units.
- `M` budget: `500.0` units.
- Maximum candidate runs: `8` with 10-unit inspector reservation per run;
  total remains `<= 500.0`.
- Search: linear incumbent/frontier search; one mutation per candidate.

If implementation separates model budget from execution slots, retain both hard
limits. Never exceed either limit.

## Frozen benchmark contract

- Scene: `5 x 5 x 100 = 2500` cuboids.
- Static geometry: infinite plane `z = 0`.
- Seed independently generates dimensions with fixed SplitMix64-style draws.
- Initial poses are fixed grid poses; initial velocities and rotations are zero.
- Dimensions: `[0.8, 1.2]`; grid gap: `0.03`.
- Gravity: `(0, 0, -9.81)`.
- Density: `1000`; static friction: `0.6`; dynamic friction: `0.5`.
- Restitution: `0.05`; timestep: `1/240 s`; duration: `20 s`.
- Candidate may choose internal algorithm and representation, not scene or physics.
- Because every cuboid starts axis-aligned, laterally separated, and with zero
  lateral velocity/rotation, the reference collision problem is exactly 100
  independent vertical contact columns (25 columns, each 100 high) plus a plane. The harness rejects any
  lateral motion; this makes the specialized reduction auditable rather than a
  hidden relaxation of the benchmark.
- `A` emits final state, one final-window checkpoint, friction calibration distance,
  checksum, and exact step count. Full contact telemetry deferred.

## Validity and stability

Harness owns all checks. Candidate-reported score is informational only.

Reject on nonfinite state, wrong body count/order, altered mass/dimensions, plane
penetration, same-column overlap, failed deterministic replay, friction calibration
failure, or insufficient settling.

Use bounded metric:

```text
error = clamp(max(
  residual_velocity / 1e-3,
  final_window_drift / 1e-3,
  penetration / 1e-4) - 1, 0, 1)
stability = 1 - error
```

Require `stability >= 0.99`. Full-scene invariant checks run on all 2500 bodies.
Friction remains mandatory through fixed plane-slide calibration using dynamic
`mu = 0.5`: expected stopping distance is `v^2/(2*mu*g)` within 5% at hidden
probe velocities.

## Candidate run layout

```text
runs/<meta-run>/
  api/
  benchmark/
  candidates/b-000/
    orchestrator.nim
    manifest.json
    build/
    nested-runs/
    evidence/
  archive.jsonl
  reflections.jsonl
  final/
```

Copy API files physically. Compile candidate with `--path:<candidate>/api`.
Execute with candidate directory as current directory. Inspect nested
`run-* /vecherinka_provenance.sqlite3` using `openProvenance`.

## `B0` shape

Each generated `B` receives one architecture, intelligence policy, and model
profile mutation. It uses its copied API to ask the model for `A` plus proposal
evidence, then compiles, runs, friction-tests, stability-tests, and benchmarks
`A` under the 50-unit budget. Invalid model output gets a compiled baseline
only as diagnostic evidence; it cannot become valid without nested provenance
and harness gates.

M reserves 10 units for an artifact inspector. The inspector writes evidence
paths, wasted budget, failed assumptions, and a targeted mutation. The next B
consumes that reflection and changes architecture as well as intelligence and
profile. Archive is bounded by the 8-candidate / 500-unit M schedule.

## M search schedule

1. Evaluate the first architecture/intelligence/profile tuple.
2. Inspect artifacts, nested provenance, runtime gates, and budget waste.
3. Apply reflection-driven architecture plus intelligence/profile mutation.
4. Continue linearly for at most 8 candidates, spending 60 units per
   candidate including inspection, never exceeding 500 units.
5. Publish the fastest valid generated `A` and its evidence.

Inspector output fields: category, severity, evidence paths, wasted budget,
failed assumption, mutation target. Scalar runtime never forms sole learning
signal.

## Safety

Monitor run tree after material writes and long commands. Runaway trigger:
`runs/` exceeds `1 GiB`, exceeds `100000` files, or uncontrolled child process
growth. On trigger: immediately stop commands, kill Codex app-server processes,
and execute authorized `git reset --hard`. Do not continue afterward.

## State checklist

- [x] Read API, provenance runner, bootstrap rationale.
- [x] Create goal and this state file.
- [x] Obtain parallel subagent metric reviews.
- [x] Freeze minimal validity/stability metric.
- [x] Implement benchmark and harness.
- [x] Implement recursive child runner and `B0`.
- [x] Implement bounded `M` and inspector/mutations.
- [x] Verify/freeze `M` with subagent after blocker fixes (Jason: PASS).
- [ ] Run metaoptimizer as final action; no tool calls after completion.
- [ ] Stop; no post-run work.
