# Worker16 batched-block FFTW prototype

Date: 2026-08-28

## Decision

**REJECT for promotion.** Packing all active row-band suffix FFTs into one
large `fftw_plan_many_dft` is numerically valid, but it does not provide a
reproducible N=65536 speedup on the current direct-parallel implementation and
more than doubles the explicit plan memory.

## Prototype

`worker16_batch_impl.c` includes the production implementation read-only and
constructs a research-only plan.  At setup it enumerates the same geometric
bands and computes the same `n0 = ceil(z0*N/(2*pi*lo))` mask.  For each active
band and asymptotic term it allocates one q-major row, clears `[0,n0)`, and
fills `[n0,N)` with the weighted input.  All rows are then executed by one
backward `fftw_plan_many_dft` call.  Assembly iterates bands, output rows, and
terms in the current order; the existing Kahan direct-row parallel kernel is
unchanged.

The phase driver is `worker16_batch_phase_bench.c`.  The comparison baseline
was rebuilt from the latest `src/dht_asym.c` after an existing shared-worker
update changed the default profile to 11 terms, cutoff 23, ratio 4.  No
`src/` or `bench/` file was edited by this experiment.

## N=65536 timing and explicit memory

Input: the common harness deterministic random complex input.  Timing is
`dht_apply` only; setup is shown separately.  Each benchmark used 21 measured
repetitions and 3 warmups.  `plan_bytes` counts explicit plan-owned tables and
scratch, including the batch scratch, but not FFTW's opaque internal planner
allocations.

| FFTW workers | current direct-parallel | batched plan_many | change |
|---:|---:|---:|---:|
| 1 | 0.052519 s, setup 0.641310 s, 65,676,416 B | 0.053007 s, setup 0.640794 s, 134,882,640 B | time +0.93%, memory +105.37% |
| 10 | 0.024161 s, setup 0.682283 s, 65,676,416 B | 0.024818 s, setup 0.642401 s, 134,882,640 B | time +2.72%, memory +105.37% |

The current profile has 7 active bands and 77 length-N FFT rows (11 terms per
band).  Batch scratch alone is 80,740,352 B; the current scratch is 11,534,336
B.  A 15-repetition phase run at 10 workers showed the same direction:

| phase | current | batch | change |
|---|---:|---:|---:|
| fill | 2.807 ms | 2.849 ms | +1.50% |
| FFT | 8.306 ms | 9.196 ms | +10.72% |
| reduction | 2.294 ms | 2.736 ms | +19.27% |
| direct rows | 12.606 ms | 12.616 ms | +0.08% |
| summed profile | 26.330 ms | 28.014 ms | +6.40% |

The direct phase is unchanged as expected.  The large batch's FFTW threaded
execution and larger working set make the FFT and post-FFT reduction slower;
the one-call API does not amortize enough work to compensate.

## Correctness spot check

Command:

```sh
./research/worker16_batch_accuracy 65536 1e-13 10 0 0 128 4
```

The independent 256-bit MPFR harness passed all five input families at dense
N=32, 64, and 128, the N=65536 selected-row diagnostic, and full delta columns
at `at=1` and `at=N-1`.  Worst reported values were:

```text
dense rel_l2       4.4139e-14
dense scaled_linf  4.8016e-14
selected-row rel   4.3026e-14
delta rel_l2       2.3187e-14
delta scaled_linf  2.8431e-14
```

All are below the acceptance thresholds `1e-13` / `1e-12`.  The benchmark
checksum agrees with the current implementation apart from last-bit
differences expected from the distinct FFTW plan.

## Reproduction artifacts

```text
research/worker16_batch_impl.c
research/worker16_batch_phase_bench.c
research/worker16_batch_benchmark
research/worker16_batch_accuracy
research/worker16_current_phase_bench
research/worker16_baseline_benchmark
```
