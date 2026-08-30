# Worker 7 — adversarial numerical verification

Date: 2026-08-28

## Verdict

The leading profile `(terms=12, cutoff=18, block_ratio=4)` is **FAIL**.  It
passes ordinary random, phase, cancellation, dynamic-range, and full delta
checks, but the MPFR residual-sign input fails the acceptance gate on every
full small-N test and again at `N=65536`.

The best speed/safety balance tested is `(12, 21, 4)`.  If maximum margin is
preferred over speed, use `(10, 40, 4)`.

## Method and commands

The driver was compiled directly against the current `src/dht_asym.c`; its
source and all logs were kept in `/private/tmp`.  It uses a separate 256-bit
MPFR `mpfr_j0` direct reference, rounded to binary64 before error metrics.
Small full-vector tests used `N=32,64,128,256`.  At `N=65536`, arbitrary
inputs were checked on 23 rows spanning block boundaries and endpoints; full
vector MPFR checks were done for delta inputs at both `n=1` and `n=N-1`, with
additional checkpoints at `N=1024,4096,16384`.

```sh
make all
clang -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic \
  -I/opt/homebrew/include -I/Users/alex/areas/productive/orchestration/testing/manual_runs/1/src \
  /private/tmp/worker7_adversarial.c src/dht_asym.c \
  -L/opt/homebrew/lib -lmpfr -lgmp -lfftw3_threads -lfftw3 -lm \
  -o /private/tmp/worker7_adversarial
/private/tmp/worker7_adversarial > /private/tmp/worker7_adversarial.csv
build/dht_accuracy 65536 1e-13 1 12 20.25 256 4
build/dht_accuracy 65536 1e-13 1 12 21 256 4
```

The residual-sign vector uses the first active ratio-4 block and

```text
x[k] = sign(A_K(2*pi*m*k/N) - J0(2*pi*m*k/N)) * (1 - 0.375 i)
```

for the asymptotic tail, with the sign formed in MPFR.  For the requested
profile at `N=65536`, `m=4`, `n0=46937`, and the scalar residual L1 is
`9.50874e-10`.

`E2` is normalized L2 and `Einf` is scaled Linf; the gate is
`E2 <= 1e-13` and `Einf <= 1e-12`.

## Results

Worst residual-sign metrics are shown below.  “Small” is the maximum over the
full small-N residual-sign runs (all `N=32,64,128,256` for the main profiles;
`N=64,128,256` for the fine `20.x` sweep, plus the standard full suite at
`N=32`); “high” is over the 23 selected `N=65536` rows.

| profile | direct entries | plan bytes | small `E2 / Einf` | high `E2 / Einf` | result |
|---|---:|---:|---:|---:|---|
| `(12,18,4)` | 4,104,957 | 59,054,280 | `3.193e-13 / 5.739e-13` | `3.237e-13 / 5.185e-13` | **FAIL** |
| `(12,20,4)` | 4,526,913 | 62,429,928 | `1.047e-13 / 1.311e-13` | `1.004e-13 / 1.221e-13` | **FAIL** |
| `(12,20.25,4)` | 4,580,385 | 62,857,704 | `6.121e-14 / 6.899e-14` | `6.923e-14 / 7.793e-14` | pass, narrow |
| `(12,21,4)` | 4,769,025 | 64,366,824 | `2.545e-14 / 2.665e-14` | `2.524e-14 / 2.628e-14` | **PASS** |
| `(12,24,4)` | 5,436,213 | 69,704,328 | `1.254e-14 / 3.314e-14` | `3.292e-14 / 5.840e-14` | **PASS** |
| `(10,40,4)` | 8,457,345 | 89,679,064 | `3.635e-15 / 4.964e-15` | `3.119e-15 / 3.792e-15` | **PASS** |
| `(8,48,4)` | 9,961,089 | 97,514,696 | `3.133e-14 / 3.251e-14` | `3.500e-14 / 3.233e-14` | **PASS** |

For the requested profile, the worst ordinary high-N selected cases were the
binary64 dynamic-range input (`2^-300` through `2^300`):
`E2=5.261e-14`, `Einf=8.907e-14`.  The complex phase-chirp case was
`2.648e-14 / 1.719e-14`; alternating and paired-cancellation cases passed.
The dynamic reference scale reached `3.038e90` without overflow.

Full endpoint delta results for `(12,18,4)` remained well within the gate:

| `N` | delta at `1` `E2 / Einf` | delta at `N-1` `E2 / Einf` |
|---:|---:|---:|
| 1,024 | `1.652e-16 / 2.220e-16` | `3.296e-15 / 3.750e-15` |
| 4,096 | `1.645e-16 / 2.509e-16` | `3.315e-15 / 3.864e-15` |
| 16,384 | `1.632e-16 / 2.509e-16` | `3.242e-15 / 3.861e-15` |
| 65,536 | `1.635e-16 / 2.776e-16` | `3.188e-15 / 3.908e-15` |

## Timing and recommendation

`build/dht_benchmark 65536 15 3 1e-13 1 ... 4`, one thread, deterministic
complex input:

| profile | setup (s) | median apply (s) |
|---|---:|---:|
| `(12,18,4)` | 0.6426 | 0.05309 |
| `(12,20.25,4)` | 0.6490 | 0.05314 |
| `(12,21,4)` | 0.7092 | 0.05479 |
| `(12,24,4)` | 0.6500 | 0.05626 |
| `(10,40,4)` | 0.7169 | 0.05663 |
| `(8,48,4)` | 0.7243 | 0.05567 |

`(12,20.25,4)` is the fastest observed passing probe, but its selected
high-N residual-sign L2 is only `1.45x` below the gate and is not a safe
promotion.  Recommend `(12,21,4)`: it is only about 3% slower than the
blocked winner, uses 64.4 MB, and has materially more residual margin.  Use
`(10,40,4)` when the extra safety margin is worth roughly 3.4% more apply time
and 39% more plan storage.

No writes targeted `src/` or `bench/`.  This checkout has no `.git` metadata,
so cleanliness was verified by path scope rather than `git diff`.
