# Worker 6 — block partition and transform-count optimization

Date: 2026-08-28

## Decision

Keep the current dyadic row partition (`r=2`).  The proof-preserving grouped
variant with non-dyadic geometric ratio `r=3` passes the dense/MPFR checks, but
does not reduce input-dependent time.  Larger grouping ratios and a direct-row
hybrid are slower once the extra direct sweep and larger direct-kernel working
set are charged.  No complete variant reached the required `<= 0.0288 s`
median (10% below the approximately `0.032 s` baseline) at `N=65536`.

All experiment code is isolated under
`research/worker6_partition_variants/`; no `src/` or `bench/` file was edited
by this worker.

## 1. Safe partition family

Let

```text
alpha = 2*pi/N
T     = z0*N/(2*pi)
```

For an integer geometric ratio `r >= 2`, use row bands

```text
I_i = [b_i, min(r*b_i, N)),    b_i = r^i,
n_i = min(N, ceil(T/b_i)).
```

The asymptotic FFT contribution for `I_i` uses only input indices
`n >= n_i`.  The remaining positive-positive entries in that band are added
directly with `J0`.

This is safe for every `r`, including non-dyadic `r=3`, because

```text
alpha*m*n >= alpha*b_i*n_i >= z0
```

for every entry passed to the asymptotic expansion.  Thus the expansion is
never evaluated in the small-argument region and no large asymptotic value is
subtracted from a direct value.  Grouping two adjacent dyadic bands is exactly
the `r=4` member of this family.

For the scratch implementation, `K=8` means eight ordinary full-length FFTs
per active row band, corresponding to retained orders `q=0..7`.  With

```text
c_0 = 1,
c_(q+1) = c_q*(2q+1)^2/(8*(q+1)),
```

the first-omitted-term bound used for the scalar asymptotic remainder is

```text
B_8(z0) = sqrt(2/(pi*z0)) * (c_8/z0^8 + c_9/z0^9)
         = 5.203678e-13       (z0=34).
```

This bound is unchanged by the partition.  In output form, the truncation
part obeys

```text
|delta y[m]| <= B_8(z0) * sum_{n in asymptotic tail of m} |x[n]|,
```

before FFT roundoff.  The partition only changes which entries are direct; it
does not weaken the no-cancellation argument or the scalar asymptotic bound.

## 2. Exact count and memory model at `N=65536`

Here `T=354632.8639159954`.  Direct counts below exclude the exact zero row and
zero column; those axes contribute `2*N-1 = 131071` entries.  `plan_bytes` is
the existing plan accounting: row metadata, precomputed direct `J0` values,
weights, scales, and one `K`-batch of complex FFT scratch.  It excludes FFTW's
internal plan allocation and the input/output arrays.  Every row-grouped
variant below still uses full `N=65536` FFTs.

| partition | total row bands | active bands | FFTs/apply | direct `(+,+)` entries | direct-kernel bytes | plan bytes | asymptotic bound |
|---|---:|---:|---:|---:|---:|---:|---:|
| dyadic `r=2` | 16 | 13 | 104 | 5,025,537 | 40,204,296 | 58,030,272 (55.34 MiB) | `5.203678e-13` |
| geometric `r=3` | 11 | 9 | 72 | 6,234,354 | 49,874,832 | 67,700,808 (64.56 MiB) | same |
| grouped `r=4` | 8 | 6 | 48 | 7,326,321 | 58,610,568 | 76,436,544 (72.90 MiB) | same |
| grouped `r=8` | 6 | 5 | 40 | 10,697,137 | 85,577,096 | 103,403,072 (98.61 MiB) | same |
| grouped `r=16` | 4 | 3 | 24 | 16,904,625 | 135,237,000 | 153,062,976 (145.97 MiB) | same |

Ignoring endpoint rounding, one row band contributes approximately
`(r-1)*T` direct entries.  Therefore

```text
D_r ~= (r-1)*T*log(N)/log(r),
```

while the full-length transform count is approximately
`K*log(N)/log(r)`.  The direct-work coefficient grows with `r` even as the
FFT count falls.  This is the central tradeoff observed in the measurements.

## 3. Timing falsification

The scratch binaries were compiled from
`research/worker6_partition_variants/dht_partition.c` with a compile-time
`PARTITION_RATIO`, using Apple clang, FFTW 3.3.10, `K=8`, `z0=34`, and 10 FFTW
threads.  The benchmark excludes setup from the median and includes input
scaling, all FFTs, output assembly, and the direct sweep.

The first screening used nine repetitions and two warmups:

| partition | setup (s) | median apply (s) | result versus dyadic screening |
|---|---:|---:|---:|
| `r=2` | 0.635263 | 0.030754 | baseline |
| `r=3` | 0.644963 | 0.031563 | 2.6% slower |
| `r=4` | 0.734406 | 0.033489 | 8.9% slower |
| `r=8` | 0.733676 | 0.043973 | 43.0% slower |
| `r=16` | 0.858247 | 0.062572 | 103.5% slower |

A repeated 15-repetition check reduced the risk of making the decision from a
single noisy run:

| partition | setup (s) | median apply (s) |
|---|---:|---:|
| `r=2` | 0.643521 | 0.032264 |
| `r=3` | 0.637582 | 0.032793 |

The `r=3` result is still above the `0.0288 s` success threshold.  The
different medians are ordinary host scheduling noise, but both runs show that
removing 32 full FFTs does not compensate for the larger direct region in this
implementation.

## 4. Hybrid direct threshold

I also tested a dyadic hybrid that makes all rows `m < M` direct and starts the
dyadic FFT bands at `M`.  `M=16` removes the active `[8,16)` band, saving eight
FFTs while adding only the extra direct rows.  The exact count model is:

| direct-row limit `M` | active bands | FFTs/apply | direct `(+,+)` entries | plan bytes |
|---:|---:|---:|---:|---:|
| 0 (current) | 13 | 104 | 5,025,537 | 58,030,272 |
| 16 | 12 | 96 | 5,195,185 | 59,387,456 (56.64 MiB) |
| 32 | 11 | 88 | 5,889,121 | 64,938,944 (61.93 MiB) |
| 64 | 10 | 80 | 7,631,617 | 78,878,912 (75.22 MiB) |
| 128 | 9 | 72 | 11,471,233 | 109,595,840 (104.52 MiB) |

The 15-repetition `M=16` run was `0.032160 s` median, effectively tied with
the dyadic run and nowhere near a 10% improvement.  The larger limits screened
at `0.033894 s`, `0.044766 s`, and `0.071370 s` for `M=32,64,128`, respectively.

The hybrid preserves the same safety proof: the newly direct rows never enter
the asymptotic stage, and all remaining bands retain their lower-endpoint
cutoff.

## 5. Asymmetric row/column blocking

A two-sided partition can use the local identity

```text
exp(i*alpha*a*b)
 = exp(i*alpha*a^2/2) * exp(i*alpha*b^2/2)
   * exp(-i*alpha*(a-b)^2/2)
```

on a rectangle of local row length `L_m` and column length `L_n`.  It needs a
linear-convolution FFT of length at least `L_m+L_n-1` (rounded to a convenient
FFT length).  For arbitrary complex input, positive and negative phase signs
are independent; after setup-time kernel spectra are reused, a conservative
application lower bound is four local FFTs per asymptotic coefficient per far
rectangle (input and inverse transforms for both signs).

The scratch count model rejects this route before a full implementation:

| row ratio | column ratio | far rectangles | direct `(+,+)` entries | lower-bound apply FFTs | max FFT length | sum of FFT lengths | `sum L log2(L)` |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 2 | 2 | 78 | 7,208,961 | 2,496 | 65,536 | 2,500,608 | 38,479,872 |
| 2 | 4 | 36 | 10,354,689 | 1,152 | 131,072 | 1,462,272 | 22,945,792 |
| 4 | 2 | 36 | 10,354,689 | 1,152 | 131,072 | 1,462,272 | 22,945,792 |

For comparison, the current dyadic full-FFT stage has

```text
K * active_bands * N * log2(N)
= 8 * 13 * 65536 * 16
= 109,051,904
```

complex FFT work units.  The two-sided `2x2` lower bound is already
`4*K*38,479,872 = 1,231,355,904` such units, before output accumulation and
the larger direct pass.  The asymmetric `2x4`/`4x2` choices remain more than
six times the dyadic work model.  Column blocking also does not obtain a free
factor of two from matrix symmetry because the required input is complex and
the positive/negative phase transforms are not conjugates.

## 6. Dense and high-precision falsification

The read-only workspace MPFR harness was linked against the scratch objects;
it uses a 256-bit MPFR dense reference for `N=32,64,128,256`, selected large
rows at `N=65536`, and full transforms of delta inputs at columns `1` and
`N-1`.

The `r=3` grouped variant passed every check:

```text
dense worst over N<=256:       rel_l2  = 8.2786e-14
                               scaled_linf = 1.8321e-13
large-row maximum:             1.0673e-13   (harness limit 1e-11)
delta at 1:                    rel_l2  = 1.6267e-16, scaled_linf = 2.7990e-16
delta at N-1:                  rel_l2  = 3.6129e-15, scaled_linf = 4.0158e-15
```

The `r=4` variant also passed all dense, large-row, and delta checks; its dense
worst was `rel_l2=7.0584e-14`, `scaled_linf=1.8885e-13`.  The `M=16` hybrid
passed as well, with dense worst `rel_l2=8.3363e-14`,
`scaled_linf=1.9002e-13`, and large-row maximum `1.5671e-13`.

Representative reproducibility commands were:

```sh
python3 research/worker6_partition_variants/partition_metrics.py 65536 34 8 2 3 4 8 16
research/worker6_partition_variants/bench_r3 65536 15 3 1e-13 10 8 34 3
research/worker6_partition_variants/accuracy_r3 65536 1e-13 1 8 34 256 3
```

The measured pass/fail result plus the cost tables falsify the proposed
full-length-FFT partition alternatives for the requested speed gate.  The
dyadic partition is therefore near-optimal within this masked full-FFT design;
a larger speedup would require a genuinely pruned/local convolution transform,
not only a different row grouping.
