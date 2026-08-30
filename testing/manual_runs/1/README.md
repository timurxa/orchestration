# Direct uniform-grid discrete Hankel transform research

This repository targets

```text
y[m] = sum(k=0..N-1) x[k] * J0(2*pi*m*k/N),  m=0..N-1
```

The retained implementation is a product-safe blocked asymptotic/FFT
specialization using `terms=10`, `cutoff=30`, and ratio-4 row bands at the
`1e-13` target. Build the C benchmark and MPFR accuracy harness with:

```sh
make all
make verify
make benchmark
```

The measured machine is an arm64 MacBookPro18,3 with Apple M1 Pro (10 cores,
8 performance + 2 efficiency), 32 GB RAM, and macOS 26.5.2. The production
build uses Apple clang 21.0.0, Homebrew FFTW 3.3.10 with threaded FFTW, and
Apple libdispatch; the MPFR/GMP libraries under `/opt/homebrew` are needed by
the accuracy executable only. The benchmark's transform timing excludes plan
construction but includes all input-dependent scaling, copies, FFTs, direct
corrections, and output assembly. A plan is reusable sequentially; its FFTW
scratch is shared, so concurrent calls on one plan are unsupported. See
`research/` for the literature, hypothesis archive, and worker reports.

The explicit correctness command is:

```sh
./build/dht_accuracy 65536 1e-13 10 30 21 512 4
```

The common timing/scaling sweep is:

```sh
./bench/run_winner.sh
```
