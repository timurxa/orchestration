# Benchmark harness

The harness uses identical deterministic inputs and conventions for every candidate. The random stream is derived from the fixed base seed `0x8f3c2d1e7a6b5948`, `N`, and case number; the CSV records the derived seed and full input/output FNV-1a digests. It reports reusable setup separately from input-dependent transform time, uses warmups and repeated medians, and writes machine-readable CSV to `bench/results.csv`. Input cases are `random`, `gaussian`, `compact_bump`, `oscillatory`, and `dynamic`; pass the case number as the ninth argument and `csv` as the final argument. Correctness uses dense direct evaluation at small N plus an independent multiprecision reference and adversarial large-N checks.

Run the selected profile's reproducible timing sweep with:

```sh
./bench/run_winner.sh
```

The benchmark CLI is `dht_benchmark N reps warmups tol threads terms cutoff
block_ratio case [csv]`; `case=0..4` selects random, Gaussian, compact bump,
oscillatory, and high-dynamic-range inputs. Passing `terms=0` or `cutoff=0`
uses the public default profile. `make benchmark` runs one 31-repetition
random case; the script runs the full five-case, finalist, and scaling sweep.

The accuracy CLI is `dht_accuracy large_N tol threads profile_terms
profile_cutoff max_dense profile_ratio`. It performs full-vector 256-bit MPFR
checks through `max_dense`, then selected-row and endpoint-delta checks at
`large_N`; the latter are diagnostics and do not certify arbitrary large-N
vectors.

The residual-sign adversarial checker is kept separately under `research/`
because it constructs each input from a multiprecision asymptotic residual;
the common benchmark and dense MPFR checker do not silently use those inputs.
