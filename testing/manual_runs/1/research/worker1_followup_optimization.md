# Worker 1 follow-up — low-level optimization of the blocked asymptotic/FFT candidate

Date: 2026-08-28

## Outcome

**PASS: a reproducible improvement larger than 10% was found without changing
the target operator or the acceptance thresholds.** The primary recommendation
is:

1. Keep the current conservative `terms=10`, `cutoff=64` profile.
2. Use geometric row `block_ratio=4` instead of 2. The lower endpoint still
   determines the cutoff, so this only moves product-safe entries from the FFT
   path to the exact direct path.
3. Parallelize the independent direct rows with a plan-owned reusable worker
   pool. Preserve the existing Kahan order inside every row.

The scratch implementation uses `dispatch_apply_f` on a reusable system queue;
a production patch should use a persistent pool owned by `dht_plan` if strict
worker-count control and lower scheduling variance are required.

No shared `src/` or `bench/` file was edited by this worker. Another worker
updated those shared files during the investigation (adding `block_ratio` and
the prefix-only scratch clear), so all decisive binaries were rebuilt from the
latest source after that change.

## End-to-end measurements at N=65536

Machine: arm64 Apple M1 Pro, 10 logical CPU cores (8 performance + 2
efficiency), macOS 26.5.2, Apple clang 21.0.0, Homebrew FFTW 3.3.10.

The input is the benchmark's deterministic random complex case. Timed work is
only `dht_apply`; setup and plan memory are shown separately. Medians use 15 or
21 repetitions after 5 warmups. The current source already contains the
prefix-only scratch clear in all rows below.

| build/profile | FFTW workers | direct entries | plan bytes | setup (s) | transform median (s) |
|---|---:|---:|---:|---:|---:|
| current default, ratio 2, 10/64 | 1 | 8,957,697 | 93,681,880 | 0.721827 | 0.084571 |
| current default, ratio 2, 10/64 | 10 | 8,957,697 | 93,681,880 | 0.715055 | 0.047758 |
| ratio 4, 10/64, direct rows serial | 1 | 12,946,977 | 125,596,120 | 0.802824 | 0.073253 |
| ratio 4, 10/64, direct rows serial | 10 | 12,946,977 | 125,596,120 | 0.789073 | 0.054127 |
| **ratio 4, 10/64, direct rows parallel** | **1** | **12,946,977** | **125,596,120** | **0.828088** | **0.070129** |
| **ratio 4, 10/64, direct rows parallel** | **10** | **12,946,977** | **125,596,120** | **0.819439** | **0.039353** |

The primary recommendation is therefore **17.08% faster at one worker and
17.60% faster at ten workers** versus the current default. Setup is reusable
and excluded from those percentages. The memory tradeoff is material:
125,596,120 bytes (119.78 MiB), or 34.07% above the current default.

An optional lower-memory/faster profile was also measured:

| profile | workers | direct entries | plan bytes | transform median |
|---|---:|---:|---:|---:|
| ratio 2, 8 terms/cutoff 48, serial direct | 1 | 6,944,505 | 73,382,024 | 0.071482 s |
| ratio 2, 8 terms/cutoff 48, serial direct | 10 | 6,944,505 | 73,382,024 | 0.038092 s |
| ratio 4, 8 terms/cutoff 48, parallel direct | 1 | 9,961,089 | 97,514,696 | 0.053433 s |
| ratio 4, 8 terms/cutoff 48, parallel direct | 10 | 9,961,089 | 97,514,696 | 0.029737 s |

The 8-term ratio-2 profile alone improves 15.48% / 20.24% at 1 / 10
workers and saves memory, so it is the simplest high-value profile change.
The ratio-4/8-term combination improves 36.82% / 37.73% but has a less
conservative asymptotic truncation and should remain optional until the full
N=65536 reference is run for the deployment input set.

## Accuracy

The conservative primary variant was tested with:

```sh
clang -O3 -DNDEBUG -std=c11 -I/opt/homebrew/include \
  bench/accuracy.c research/worker1_followup_parallel_dht.o \
  -L/opt/homebrew/lib -lmpfr -lgmp -lfftw3_threads -lfftw3 -lm \
  -o research/worker1_followup_accuracy_parallel
research/worker1_followup_accuracy_parallel 65536 1e-13 1 10 64 512 4
```

All dense cases N=32, 64, 128, 256, and 512 passed. The N=65536 selected-row
diagnostic was `max_row_rel=2.4880e-15`; both full delta cases passed:

```text
at=1      rel_l2=1.6267e-16  scaled_linf=2.7990e-16  PASS
at=N-1    rel_l2=1.1401e-15  scaled_linf=7.9047e-16  PASS
```

The same conservative variant at 10 FFTW workers passed the N<=128 dense
cases, selected rows (`1.9106e-15`), and both delta cases. Direct-row
parallelism is safe for the numerical contract because workers write disjoint
output rows and retain the existing inner-loop Kahan order.

The optional 8-term/cutoff-48 variants also passed the available N<=512 dense
and N=65536 selected-row/delta checks. Its scalar remainder estimate is much
less conservative (about `2.69e-14` versus about `1.03e-17` for 10/64), so it
has a larger untested worst-case margin even though the measured gate checks
pass.

## Where the time goes

At the current default (`ratio=2`, 10 terms, cutoff 64), there are 12 active
row bands and 120 length-N FFTs per transform. The conservative ratio-4
variant has 6 active bands and 60 FFTs, at the cost of 12,946,977 direct
entries. The lower-cost 8-term ratio-4 variant has 48 FFTs.

The direct-row microbenchmark measured the current Kahan kernel at about
29.8--30.6 ms for 8,957,697 entries. Reusing a global queue with 32 balanced
tasks reduced that section to 21.8 ms, a 1.34x speedup. The end-to-end result
is smaller because the FFT and other phases remain serial or separately
parallelized.

## FFTW plan_many, individual plans, and layout

The scratch benchmark is
`research/worker1_followup_plan_bench.c`. It compares ten in-place complex
FFTs of length 65536 over the same q-major storage.

| arrangement | 1 worker | 10 workers |
|---|---:|---:|
| `fftw_plan_many_dft`, contiguous q-major rows | 0.004057 s | 0.001056 s |
| ten individual `fftw_plan_dft_1d` plans | 0.004028 s | 0.002681 s |
| `plan_many`, strided term-interleaved layout | 0.007724 s | 0.003242 s |

Individual plans are effectively tied at one worker and are 2.54x slower at
ten workers. The current contiguous q-major batch layout is correct and
should be retained. The strided `[k][term]` layout is roughly 1.9--2.1x
slower, even before considering its less convenient fill path.

`FFTW_PATIENT` reduced the raw one-worker batch from about 4.057 ms to 3.912
ms, but required 14.55 s of plan setup versus about 0.52 s for `MEASURE`. That
3.6% FFT-only improvement is not enough to justify the setup cost. `FFTW_ESTIMATE`
was slower in the repeated runs (4.434 ms at one worker and 1.150 ms at ten).

## vDSP / Accelerate

The scratch benchmark is `research/worker1_followup_vdsp_bench.c`. It uses
double-precision split-complex `vDSP_fft_zipD`, includes the required inverse
normalization by N, and measures serial transforms.

| vDSP mode | 10 terms | 8 terms |
|---|---:|---:|
| `vDSP_fft_zipD` | 0.004426 s | 0.003559 s |
| `vDSP_fft_ziptD` with temporary buffer | 0.004458 s | 0.003672 s |

For comparison, FFTW `plan_many` measured 4.057 ms for 10 terms and 3.209 ms
for 8 terms at one worker. At ten workers FFTW was 1.056 ms for 10 terms and
0.710 ms for 8 terms, while vDSP has no equivalent batch-plan interface in
this path. vDSP would also require maintaining split-complex scratch storage
or paying interleave/deinterleave costs. It is not a viable replacement for
the current threaded FFTW path.

## Fill, scales, and direct-region storage

The current source now uses the safe prefix-only scratch clear. For the
default 12 active bands, the loop microbenchmark measured:

| operation over all active bands | median |
|---|---:|
| clear all q-major scratch rows, then overwrite suffix | 3.774 ms |
| clear only each row's prefix, then overwrite suffix | 2.778 ms |

This saves about 1 ms in the isolated fill phase, roughly 1--2% of the full
transform. It is safe because every suffix element is overwritten before the
FFT; no data from the prior band is needed.

Scales are already precomputed, but stored q-major. Transposing them to
`scale[m * terms + q]` made the isolated post-FFT reduction 1.621 ms ->
1.384 ms for the default active bands. That is a 14.6% reduction of the
reduction loop but only about 0.3% of total transform time. It is a safe,
low-priority cache improvement with no memory increase.

The flattened row-major `double` direct kernel is already the appropriate
storage layout: each row is consumed sequentially and the x prefix is reused.
At the current default it occupies about 68.34 MiB; ratio-4 conservative
partitioning raises this to about 98.78 MiB. Replacing it with `float` would
save roughly half of that array, but introduces coefficient quantization on
the order of 1e-7, far above the 1e-13/1e-12 gate. It is rejected. A separate
double residual would remove that memory benefit and add work.

## Compiler flags on Apple M1 Pro

The strict baseline was the existing `-O3 -DNDEBUG -std=c11` build.
`-mcpu=apple-m1` and `-march=armv8.5-a` produced no reproducible 10% gain;
the latter was slightly slower in one run. Adding
`-fno-math-errno -fno-trapping-math` was also within run-to-run noise.
These flags are not a substitute for algorithmic parallelism.

`-Ofast` (equivalent here to `-O3 -ffast-math`) is tempting:

```text
current strict default:  0.084571 s / 0.047758 s  (1 / 10 workers)
-Ofast default:           0.056177 s / 0.019677 s  (1 / 10 workers)
```

That is 33.57% / 58.80%, and the available harness cases happened to pass;
however, it permits reassociation that defeats the compensated Kahan sum and
changes floating-point exceptional-value semantics. Clang also warns that
the source's `NAN` use is undefined under those options. It is **not a safe
flag for this acceptance gate** and should not be the production
recommendation without a stronger adversarial/full-N reference and an
explicit decision to relax strict floating-point semantics.

## Reproducible scratch artifacts

The investigation's source and binaries are all under the permitted
`research/worker1_followup_*` prefix. The most relevant sources are:

* `worker1_followup_parallel_dht.c` — scratch wrapper with parallel direct
  rows and unchanged FFT/asymptotic code.
* `worker1_followup_plan_bench.c` — FFTW plan, layout, and planning-flag
  comparison.
* `worker1_followup_vdsp_bench.c` — Accelerate double-precision comparison.
* `worker1_followup_loop_bench.c` — fill, direct, and scale-layout timings.
* `worker1_followup_direct_parallel.c` — isolated direct-row scaling test.

The recommended production patch should be applied to the real candidate only
after rerunning the project's full independent N=65536 reference. The
measured and verified minimum change is ratio-4 partitioning plus reusable
direct-row parallelism while retaining 10 terms and cutoff 64.
