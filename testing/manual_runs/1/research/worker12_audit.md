# Worker 12 — archive and reproducibility audit

Date: 2026-08-28

Scope: the exact operator contract in `AGENTS.md`, `README.md`,
`bench/README.md`, `Makefile`, the current `src/dht_asym.c`, and every report
currently under `research/` (including Workers 7, 8, 15, and the Worker 1
follow-up). No files under `src/` or `bench/` were edited.

## Audit conclusion

There is no archive-level certification of an arbitrary binary64 complex
vector at `N=65536`. The leading `(terms=12, z0=18, ratio=4)` profile is
rejected: the independent MPFR residual-sign tests fail the normalized-L2
gate at full small sizes, and the high-`N` selected-row tests also exceed the
gate. `(12,21,4)`, `(12,24,4)`, `(10,40,4)`, and `(8,48,4)` are screening
survivors only. Worker 15 adds useful one-thread scaling data, but it does not
add an accuracy certification.

The current reproducibility record is incomplete: `research/archive.csv`
stops at H9, `research/log.md` does not index the later reports, and
`bench/results.csv` currently contains only its header. The source also moved
again during this audit: `src/dht_asym.c` is newer than the checked-in build
objects and executables, so direct invocations of `build/*` are stale.

## Exact contract used for this audit

The required operator is

```text
y[m] = sum(n=0..N-1) x[n] J0(2*pi*m*n/N),  m=0..N-1,
```

with binary64 complex input and output. Acceptance is against an independent
multiprecision reference:

```text
normalized L2 <= 1e-13
scaled Linf  <= 1e-12
```

The primary benchmark is deterministic complex `N=65536`, with powers-of-two
scaling. Timed work is input-dependent transform work only; reusable setup and
memory must be reported separately.

## 1. Missing literature and implementation accounting

The literature review covers Townsend/DLMF asymptotics, NUFHT, FFTLog/QDHT/
CGFHT, butterfly methods, FINUFFT, radial/projection-slice ideas, and
hierarchical low-rank methods. The reports correctly reject or qualify the
indirect-grid, radial, generic butterfly, and conventional FMM routes for the
exact finite matrix. The following items remain missing or incomplete:

- There is no final source artifact in `best/`; the only target-faithful C
  implementation identified is the experimental blocked asymptotic/FFT plus
  direct-correction code in `src/dht_asym.c`.
- No target-faithful Townsend geometric port, exact-grid NUFHT adapter,
  production butterfly factorization, radial FFT implementation, or FMM/H2
  implementation was archived. These are literature accounting, not
  implementation baselines.
- Worker 7's adversarial driver and CSV are referenced in
  `/private/tmp/worker7_adversarial.c` and
  `/private/tmp/worker7_adversarial.csv`; they are not preserved in the
  research archive. Its conclusions are reviewable from the report but not
  independently replayable from the repository.
- Reports exist through Worker 15, but `research/archive.csv` has only H1–H9.
  Worker 10, Worker 1's optimization follow-up, Worker 7, Worker 8, Worker
  11, and Worker 15 need archive rows with profile, source/build identity,
  command, metrics, and status.
- Additional unreported Worker 13, 14, and 16 source/binary artifacts are
  present. They have no retained result report/CSV sufficient to establish
  status; Worker 16 is a research-only batched-FFT prototype, not an
  integrated `src/`/`bench/` implementation.
- Worker 11's real/complex FFT split is documented and should remain a
  rejected optimization experiment: its higher-repetition default result was
  2.1% slower, while its candidate-profile difference changed sign between
  runs. It does not provide a promotion-quality speed result.
- `bench/results.csv` has no timing rows. The worker-specific timing tables
  therefore cannot be treated as the common-harness record.
- The report set contains no full arbitrary-input MPFR result for every output
  row at `N=65536`. The full large-`N` checks are restricted to delta controls;
  random, alternating, dynamic, and residual-sign cases use selected rows.

## 2. Consistency checks

### Complexity and FFT accounting

For the current full-length-FFT implementation, let `t=terms`, `B` be the
number of active row bands, and `D` be the positive-positive direct-entry
counter. The apply work is consistent with

```text
Theta(t*B*N*log N + t*B*N + D + N),
```

with direct rows parallelized in the current source. For fixed ratio `r`,
`B=Theta(log_r N)` and the direct portion is approximately
`O(z0*N*log_r N)`, so the simple full-FFT form is
`O(t*N*(log N)^2 + N*log N)` at fixed `r`, `z0`, and `t`.

The exact complex-DFT sign accounting is important. If
`Fq[m] = sum_n x[n] wq[n] exp(+2*pi*i*m*n/N)`, then
`Fq[N-m] = sum_n x[n] wq[n] exp(-2*pi*i*m*n/N)` for any complex `x`.
Therefore the negative phase is obtained from the partner bin; complex input
does not require a second FFT for the opposite sign. The current
`(12,18,4)` profile has seven active bands and 84 full-length FFTs (12 per
band), not 168. If `K=12` instead means orders `q=0..12`, the count is 13
per band, not 26. A notation such as “2M FFTs” is valid only when `M` counts
even/odd order pairs, not when it purports to count complex phase signs.

Incorrect or misleading claims to fix:

- H3 in `research/archive.csv` gives
  `O(K*N*log N/log 4 + N*log N)`. The full FFT factor is missing. It should
  include `log N * log_4 N` (plus direct work), or be stated as the fixed-r
  `O(K*N*(log N)^2)` bound.
- Worker 2's “26 length-N FFTs” and Worker 6 Stability's
  `2*(K+1)` signed-FFT model double-count the two phase signs. Worker 2's
  “3.43 million direct entries” and “13.6 million butterfly units” also mix
  strict product counts with masked row-band work; they are not complete
  apply-work counts.
- Worker 3's `2M` wording needs the order-pair qualification above. Its
  “below gate” wording is not justified where only maximum absolute error,
  rather than the project scaled-Linf metric, is reported.

### Memory accounting

`dht_plan_bytes()` accounts for the plan struct/metadata, positive-positive
direct kernel doubles, weights/scales, coefficients, and `terms*N` complex
scratch. It excludes FFTW internal plan allocations and caller-owned input
and output arrays; it is reusable-plan storage, not peak RSS or total resident
memory.

For `N=65536`, `(12,18,4)` reports 4,104,957 direct entries and
59,054,280 accounted bytes (56.32 MiB). The `(10,64,2)` profile with 120 FFTs,
8,957,697 direct entries, and 93,681,880 accounted bytes (89.34 MiB) is a
historical default used by Workers 8 and 11, not the current source default.
The current on-disk source selects `(11,23,4)` at tolerance `1e-13`, with
seven active bands and 77 FFTs. Its current plan metadata has not been
archived. Worker 15's plan-size scaling is internally consistent with its
explicit profiles, but remains a local benchmark result.

Worker 6's plan table is eight bytes below the current source's reported value
for its `(8,34,2)` check (58,030,272 versus 58,030,280). Reconcile the stale
binary/struct accounting before quoting that table. Do not present any of
these figures as peak memory without a separate RSS measurement.

Worker 16's research-only batched prototype allocates `B*t*N` complex scratch
(`B` bands), rather than the current implementation's `t*N`. Its timing and
memory cannot inherit the current plan figures; report its extra batch scratch
and FFT-plan storage separately if it is ever compared.

### Timing and verification accounting

- `make verify` and `make benchmark` use whatever default is in the current
  source; they do not exercise the explicit `(12,18,4)` or later finalist
  profiles. Historical reports call `(10,64,2)` the default, while the
  current source selects `(11,23,4)`. A final report must print all profile
  arguments rather than call the default target a finalist benchmark.
- `bench/run_winner.sh` currently labels `(12,18,4)` as the winner even though
  Worker 10 and Worker 7 reject it. It also overwrites `bench/results.csv`;
  rename/repoint it after a certified profile is selected.
- Worker 7, Worker 8, and Worker 1 follow-up timings are not rows in the
  common CSV. Worker 15 is a useful one-host, one-thread, random-input sweep,
  but its five-repetition crossover at `N=65536` is explicitly outlier
  sensitive and is not a durable universal speed claim. Worker 15 also
  predates the latest source change, despite reporting its executable as
  current at the time.
- The current source uses dispatch parallelism for direct rows. Worker 8's
  statement that the direct-row pass is serial is stale, and any timing made
  before the latest source update is not a timing of the current source.
  Worker 10, Worker 7, and Worker 15 artifacts predate that update; the
  current `build/dht_asym.o`, `build/dht_benchmark`, and `build/dht_accuracy`
  are also older than `src/dht_asym.c`. Rebuild and rerun the accepted profile
  after the source and executable are frozen.
- `bench/README.md` says the large-`N` harness includes adversarial checks,
  but `bench/accuracy.c` actually covers fixed selected rows and full delta
  columns; the residual-sign adversarial driver is separate. Correct the
  README or integrate/archive the adversarial test.
- Worker 4's “scaled Linf” uses
  `max(error)/max(1,max(abs(yref)))`, not the project's `maxerr/maxref`.
  Worker 1 and Worker 3 also report non-gate max-error variants in places.
  Relabel those results or recompute the exact metrics before using PASS.
- Worker 6's `0.0288 s` screening threshold is worker-local, not specified by
  `AGENTS.md`, `README.md`, or `bench/README.md`; it must not be presented as
  an acceptance requirement. Normalize the Townsend journal/year citation,
  which differs between `sources.md`/Worker 1 and Worker 5's follow-up.
- The current source comment calls `(11,23,4)` the fastest retained profile,
  but no archived full `N=65536` arbitrary-vector gate supports that claim.
  Treat it as an unverified default selection until Worker 13/other artifacts
  are archived and the full gate is rerun against the frozen source.

## 3. Copy-ready final-report caveat for `N=65536`

> At `N=65536`, this implementation is not certified for the required
> arbitrary binary64 complex input vector. Independent MPFR testing provides
> full-vector results for the delta controls and selected-row results for the
> other large-`N` inputs; it does not evaluate every output row for an
> arbitrary residual-sign, random, or dynamic vector. For `(12,18,4)`, the
> full residual-sign test fails the normalized-L2 gate at small sizes (for
> example, `3.193e-13` at `N=64`), and the selected-row `N=65536` tests report
> normalized L2 of `3.753e-13` (Worker 10's 18-row run) and `3.237e-13`
> (Worker 7's 23-row run), both above `1e-13`; the corresponding scaled-Linf
> values are about `5.19e-13`. The full delta-column controls pass, but they
> are not a substitute for full arbitrary-vector certification. Profiles
> `(12,21,4)`, `(12,24,4)`, `(10,40,4)`, and `(8,48,4)` pass the tested
> screening cases only. Their `N=65536` results, timing, and memory must be
> labeled provisional until a frozen-source run compares a deterministic
> arbitrary complex vector against an independent multiprecision reference
> over all `m` and both acceptance metrics. The current source default
> `(11,23,4)` is likewise unverified at this full-vector boundary; its source
> comment is not an accuracy certificate.

## 4. Concise reproducibility checklist

1. Freeze the exact source tree, compiler, flags, FFTW/MPFR/GMP versions,
   platform, and thread count; record a source/build hash.
2. Build with `make all`; verify that the executable timestamp/hash matches
   the source used for every accuracy and timing result.
3. Run explicit profile arguments (`N`, reps, warmups, tolerance, threads,
   `terms`, `z0`, ratio, and input case); do not rely on Makefile defaults.
4. Use deterministic inputs and record their generation/seed. Include random,
   structured, dynamic, residual-sign, and delta controls.
5. For small powers of two, compare every output against an independent MPFR
   dense reference. At `N=65536`, compare every output row for at least one
   arbitrary complex vector and report normalized L2 and exact scaled-Linf.
6. Record setup time separately from repeated, warmed apply medians; retain
   raw samples, checksums, profile metadata, accounted plan bytes, and peak
   RSS separately.
7. Archive every custom validation driver, reference/input generator, command
   line, raw CSV/log, and the final source/build identity under `research/`.
8. Add the accepted profile and all final rows to `research/archive.csv` and
   `bench/results.csv`; only then label a profile certified or a winner.
