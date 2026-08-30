# Worker 8 — bounded performance study

Date: 2026-08-28

## Decision

For this MacBook Pro (10 logical CPUs, Apple arm64, Apple clang 21, FFTW
3.3.10), the changes worth carrying forward are operational:

- Keep `FFTW_MEASURE` for reusable plans.  Use 8–10 FFTW threads for the
  `N=65536` workload on this host; 10 was the best measured median, but 8 was
  effectively tied.
- Keep the current contiguous, coefficient-major FFTW batch layout.
- Consider prefix-only scratch clearing as a small, target-dependent cleanup,
  but do not claim a stable win from this study.  Its end-to-end medians moved
  with host noise.

Reject for integration from this bounded study:

- the scalar output-pruned radix-2 prototype;
- strided/m-major FFT storage, a second m-major scale table, and axis fusion;
- `-mcpu=apple-m1` and `-ffp-contract=fast` as performance changes; and
- `-Ofast`/`-ffast-math` for an accuracy-gated build.

No `src/` or `bench/` file was modified.  All study source and binaries are
under `research/worker8_*`.

## Scope and protocol

The production path is the existing blocked asymptotic implementation:

```text
N=65536, tol=1e-13, terms=10, z0=64, block ratio=2,
deterministic complex random input, FFTW_BACKWARD, FFTW_MEASURE.
```

Apply timing includes the current input-dependent zero/fill, all FFTs, output
assembly, and direct correction rows.  Plan construction is timed separately.
Unless noted otherwise, runs used one process at a time, monotonic-clock
timing, warmups, and medians.  The source's `dht_plan_bytes()` accounting is
reported as reusable-array memory; it excludes FFTW's internal plan allocation
and the caller's input/output arrays.

The host reported Darwin arm64, 10 logical CPUs, Apple clang 21.0.0, and
Homebrew FFTW 3.3.10.  The default production compile is `-O3 -DNDEBUG` with
the Makefile's warning flags.

## Production baseline

At `N=65536`, the current profile has 12 active row bands, 120 full complex
FFTs per apply (`12 bands × 10 terms`), 8,957,697 precomputed direct entries,
and 93,681,880 reported plan bytes (89.34 MiB).

### Thread count

`worker8_plan_bench`, 11 repetitions and 3 warmups, `FFTW_MEASURE`:

| FFTW threads | setup (s) | median apply (s) | speedup vs 1 thread | plan bytes |
|---:|---:|---:|---:|---:|
| 1 | 0.725015 | 0.085169 | 1.00x | 93,681,880 |
| 2 | 0.718357 | 0.062162 | 1.37x | 93,681,880 |
| 4 | 0.732713 | 0.053385 | 1.60x | 93,681,880 |
| 8 | 0.732799 | 0.050776 | 1.68x | 93,681,880 |
| 10 | 0.720863 | 0.049891 | 1.71x | 93,681,880 |

The direct-row pass remains serial, so scaling flattens after four threads.
The setup and reusable-array memory are essentially thread-independent.

### Scaling at powers of two

Ten threads, 9 repetitions and 2 warmups:

| N | setup (s) | median apply (s) | direct entries | plan bytes |
|---:|---:|---:|---:|---:|
| 8,192 | 0.366055 | 0.005531 | 869,377 | 9,707,736 (9.26 MiB) |
| 16,384 | 0.455963 | 0.010796 | 1,905,649 | 20,750,424 (19.79 MiB) |
| 32,768 | 0.760950 | 0.024479 | 4,145,073 | 44,170,840 (42.12 MiB) |
| 65,536 | 0.716846 | 0.051348 | 8,957,697 | 93,681,880 (89.34 MiB) |

The non-monotone setup values are FFTW planning noise; the reusable data size
and direct region grow as expected.

### Apply phase costs

The instrumented current path at `N=65536` gave these approximate phase
medians.  Phase timings are independently clocked and therefore do not sum
exactly to the separately measured whole-apply median.

| phase | 1 thread (s) | 10 threads (s) |
|---|---:|---:|
| axes and output initialization | 0.000273 | 0.000272 |
| scratch clear and weighted input fill | 0.005496 | 0.006086 |
| FFTW transforms | 0.048813 | 0.011018 |
| conjugate-partner reduction | 0.001923 | 0.001794 |
| direct Kahan correction rows | 0.029784 | 0.029484 |
| whole apply | 0.085931 | 0.049266 |

At 10 threads the serial direct correction is about 60% of apply time.  This
limits the benefit of optimizing only the FFT stage.

## FFTW planning choices

The plan-flag wrapper substituted the requested flag for the source's
`FFTW_MEASURE` call without changing the rest of the implementation.  Results
at `N=65536`, one thread, 7 repetitions and 2 warmups:

| flag | setup (s) | median apply (s) | observation |
|---|---:|---:|---|
| `FFTW_ESTIMATE` | 0.289301 | 0.093222 | fastest setup, slower apply |
| `FFTW_MEASURE` | 0.734014 | 0.087473 | good default |
| `FFTW_PATIENT` | 14.827209 | 0.083676 | modest extra apply gain |

The plan-byte accounting is unchanged by the flag.  Relative to `MEASURE`, the
indicative break-even is roughly 80 applies for `ESTIMATE` versus `MEASURE`,
and roughly 3,700 applies for `PATIENT` versus `MEASURE`; these are based on
one bounded run and should be treated as order-of-magnitude decisions.  A
long-lived plan used thousands of times may justify `PATIENT`; it is not a
general default.  `FFTW_EXHAUSTIVE` was not run because it was outside the
bounded setup budget.

## Data layout, clearing, and fusion

### FFTW batch layout

This is an FFT-only test of ten length-`N` transforms, not a whole apply.  It
used `N=65536`, `terms=10`, `FFTW_MEASURE`, 11 repetitions and 3 warmups.

| layout | setup 1 thread (s) | FFT median 1 thread (s) | setup 10 threads (s) | FFT median 10 threads (s) |
|---|---:|---:|---:|---:|
| coefficient-major contiguous (`idist=N`) | 0.551774 | 0.003925 | 0.561521 | 0.000857 |
| m-major strided (`istride=terms`) | 0.600833 | 0.007352 | 0.581053 | 0.002855 |
| ten individual plans | 0.527355 | 0.003986 | 0.483946 | 0.002488 |

The current contiguous batch is about 1.9x faster than the strided layout at
one thread and 3.3x faster at 10 threads.  Individual plans do not beat the
current batched plan and scale worse with threads.

### Whole-apply variants

The scratch harness tested a mechanically safe prefix-only clear, a transposed
m-major copy of `scales`, and fusion of the axis initialization with the
`m=0` Kahan sum.  The first screen used 11 repetitions and 3 warmups:

| variant | median 1 thread (s) | median 10 threads (s) | extra setup (s) | extra memory |
|---|---:|---:|---:|---:|
| current | 0.085975 | 0.049306 | 0 | 0 |
| prefix-only clear | 0.086397 | 0.052143 | 0 | 0 |
| m-major scales | 0.086771 | 0.051849 | 0.000843 | 5.00 MiB |
| prefix + m-major scales | 0.084315 | 0.047960 | 0.001164 | 5.00 MiB |
| fused axes | 0.088019 | 0.051118 | 0 | 0 |
| prefix + fused axes | 0.084673 | 0.050116 | 0 | 0 |

A longer 21-repetition/5-warmup repeat showed host variation rather than a
stable isolated effect.  For example, at 10 threads current/prefix medians
were `0.053724/0.047549`, `0.055035/0.052140`, and `0.049741/0.050341` in
three paired runs; at one thread they were `0.086745/0.085278`.  The combined
prefix+m-major variant was `0.048933` at 10 threads but `0.088064` at one
thread.  The scale-table copy and fusion do not earn their memory/complexity;
prefix-only clearing is safe but not promoted as a demonstrated net win.

The source's weighted fill loop is not vectorized at `-O3`.  A scratch version
with split real/imag temporaries and `#pragma clang loop vectorize(enable)`
still received a “loop not vectorized (Force=true)” remark and was slower in a
fill-only test:

| N=65536 fill test | current | split/hinted | ratio |
|---|---:|---:|---:|
| 1 thread | 0.004492 | 0.005590 | 1.24x |
| 10 threads | 0.004512 | 0.005536 | 1.23x |

## Compiler and vectorization screening

The benchmark binaries were rebuilt from the unchanged `src/dht_asym.c` and
`bench/benchmark.c`, with 11 repetitions and 3 warmups at `N=65536`, 10
threads:

| flags | setup (s) | median apply (s) | timing conclusion |
|---|---:|---:|---|
| `-O3` | 0.730232 | 0.048213 | baseline |
| `-O3 -mcpu=apple-m1` | 0.722812 | 0.050072 | no gain; within host noise |
| `-O3 -ffp-contract=fast` | 0.728281 | 0.056755 | slower |
| `-Ofast` (`-ffast-math`) | 0.741331 | 0.019878 | much faster but not accuracy-safe |

Clang's `-Rpass=loop-vectorize` confirms that `-O3` vectorizes the weight/scale
setup loops, output initialization, and the small `q` reduction loop.  It does
not vectorize the weighted complex fill or the Kahan direct/zero-row loops.
`-O3` already enables the normal vectorizer; forcing it on the complex fill did
not produce a vector loop.  `-Ofast` can reassociate or discard the Kahan
error-control structure, and Clang warned about NaN semantics under those
options.  It is therefore rejected despite the attractive timing.

## Additional priority: output-pruned radix-2 FFT

### Exact selected-output set

For a current active row band `[lo, hi)`, reduction reads only the row's
natural-frequency bins in the band and their FFT partners.  The exact set is

```text
S(lo,hi) = { m : lo <= m < hi }
          union { N-m : lo <= m < hi }.
```

There is no bin 0 in this set because active bands have `lo >= 1`.  For a
dyadic band below `N/2`, this is

```text
S = [lo, 2*lo) union [N-2*lo, N-lo),    |S| = 2*lo.
```

The terminal band `[N/2,N)` has `S={1,...,N-1}`, so it is effectively a full
FFT even though bin 0 is not consumed.

At `N=4096`, `z0=64` makes the first active band `[16,32)`.  There are eight
active bands: seven prunable bands plus the terminal near-full band.  The
table gives the exact selected count and radix-2 DIF butterfly count for one
coefficient row; a full length-4096 radix-2 FFT has 24,576 butterflies.

| band | suffix start `n0` | `|S|=k` | pruned butterflies | fraction of full |
|---|---:|---:|---:|---:|
| `[16,32)` | 2,608 | 32 | 14,240 | 0.579 |
| `[32,64)` | 1,304 | 64 | 16,288 | 0.663 |
| `[64,128)` | 652 | 128 | 18,288 | 0.744 |
| `[128,256)` | 326 | 256 | 20,216 | 0.823 |
| `[256,512)` | 163 | 512 | 22,012 | 0.896 |
| `[512,1024)` | 82 | 1,024 | 23,550 | 0.958 |
| `[1024,2048)` | 41 | 2,048 | 24,575 | 1.000 |
| `[2048,4096)` | 21 | 4,095 | 24,576 | 1.000 |

For the first seven bands, the rough `N log2(k)` estimate is

```text
4096 * (5+6+7+8+9+10+11) = 229,376
```

versus `4096 * 12 * 7 = 344,064` for seven full FFTs, or 66.7% in that
idealized work unit.  Counting the actual output-pruned DIF butterfly tree is
more conservative: `139,169` versus `172,032` butterflies, or 80.9%.  The
terminal band adds one full transform, making the all-band count
`163,745` versus `196,608` full-stage butterflies (83.3%).

The exact tree count follows

```text
B(S) = sum_{d=0..log2(N)-1} a_d * N / 2^(d+1),
a_d = number of distinct residues (k mod 2^d) for k in S.
```

This gives the expected `O(N log k + N)` behavior for a selected set of size
`k`, but the `+N` fan-in work and the increasingly full later bands matter.

### Prototype timing and memory

`research/worker8_pruned_bench.c` implements output-pruned radix-2 DIF.  It
precomputes the selected lists, bit-reversal map, and twiddles in setup, copies
the selected list per coefficient row during apply, and charges all scalar
butterflies and copies to apply time.  The prototype retains the production
FFTW plan for common setup, although it does not use it; a production pruned
backend could remove that unused internal plan.

| N | threads | current FFTW median (s) | pruned median (s) | pruned/current | context setup (s) | pruned context bytes |
|---:|---:|---:|---:|---:|---:|---:|
| 4,096 | 1 | 0.002742 | 0.004803 | 1.75x | 0.000275 | 163,888 (0.16 MiB) |
| 4,096 | 10 | 0.002373 | 0.004768 | 2.01x | 0.000273 | 163,888 (0.16 MiB) |
| 65,536 | 1 | 0.085612 | 0.130481 | 1.52x | 0.004016 | 2,621,648 (2.50 MiB) |
| 65,536 | 10 | 0.052357 | 0.132809 | 2.54x | 0.004218 | 2,621,648 (2.50 MiB) |

The scalar tree is slower despite fewer butterflies because it loses FFTW's
optimized/vectorized kernels and threading, and it pays recursive selection,
twiddle, bit-reversal, and per-row list-copy overhead.  The current direct
correction pass also remains unchanged.

**Decision: reject the prototype.**  A future pruned implementation would need
an architecture-specific, vectorized, threaded kernel and a proof that its
later nearly-full bands can be handled efficiently.  The measured scalar
prototype is not a candidate for `src/` integration.

## Accuracy evidence (separate from timing)

All statements in this section are numerical checks, not performance claims.
The MPFR checks use 256-bit `mpfr_j0` references.

For the unchanged `-O3` production path, the dense MPFR checks through
`N=512` passed; the worst printed values were `rel_l2=2.4223e-15` and
`scaled_linf=4.8200e-15`.  At `N=1024`, the large-row diagnostic was
`5.5363e-15`; full delta checks were
`rel_l2=1.6426e-16, scaled_linf=2.2204e-16` for column 1 and
`1.4281e-15, 1.0608e-15` for column `N-1`.  At `N=65536`, the row diagnostic
was `1.5514e-15`; full delta checks were

```text
at=1:       rel_l2=1.6267e-16, scaled_linf=2.7990e-16
at=N-1:     rel_l2=1.1385e-15, scaled_linf=7.9047e-16
```

Those large-`N` random-row/delta checks are diagnostics; they are not a full
`N=65536` random-vector normalized-L2 acceptance run.  The final documented
`make verify` run used the repository harness at `N=65536`, with the dense
portion through `N=512`; it reported `2.4880e-15` for the large-row diagnostic,
and the two full delta checks remained passing.

The pruned output was compared independently against MPFR and the current
FFTW path:

| check | pruned result | current result | note |
|---|---|---|---|
| `N=1024`, full random MPFR | `rel_l2=1.696977e-15`, `scaled_linf=2.630231e-15` | `1.699313e-15`, `2.630231e-15` | full reference |
| `N=4096`, 9 selected random rows | `rel_l2=1.389555e-16`, `scaled_linf=9.246950e-17` | `1.385659e-16`, `9.246950e-17` | row subset, not full L2 |
| `N=4096`, delta at 1, full output | `1.634904e-16`, `2.509593e-16` | same | full MPFR delta |

The maximum absolute pruned-minus-current difference was `1.29e-15` at
`N=1024` and `2.51e-15` for the `N=4096` random-row run.  These checks support
the selected-bin implementation; they do not overcome its timing rejection.

The compiler screening's `-O3`, `-mcpu=apple-m1`, `-ffp-contract=fast`, and
`-Ofast` builds all passed the bounded dense `N<=32` checks and the
`N=65536` row/delta diagnostics.  The `-Ofast` large-row diagnostic rose to
`1.1157e-14` versus `1.5514e-15` for `-O3`, and it changes floating-point
semantics, so it remains rejected without a complete acceptance-gate run.

## Reproduction artifacts

The source harnesses are:

```text
research/worker8_plan_bench.c          FFTW flag and thread study
research/worker8_variant_bench.c       phase/layout/fusion variants
research/worker8_fftw_layout_bench.c   contiguous/strided/individual FFTs
research/worker8_fill_vector_bench.c   safe vectorization-hint microtest
research/worker8_pruned_bench.c        output-pruned radix-2 prototype
research/worker8_pruned_accuracy.c     MPFR pruned cross-check
```

Representative commands after compiling the corresponding scratch binary are:

```sh
./research/worker8_plan_bench 65536 11 3 10 1
./research/worker8_variant_bench 65536 11 3 10 6
./research/worker8_fftw_layout_bench 65536 10 11 3 10 0 1
./research/worker8_pruned_bench 4096 11 3 10 1 1
./research/worker8_pruned_accuracy 4096 1
```
