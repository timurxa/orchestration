# Worker 3 follow-up — adversarial MPFR profile falsification

Date: 2026-08-28

## Verdict

The low-work profiles are falsified by residual-sign inputs.  In particular,
`K=8,z0=32` fails the required gate on ordinary alternating data at small `N`
and fails by more than an order of magnitude on the high-`N` sign-aligned
probe.  `K=8,z0=34`, `K=8,z0=40`, and `K=6,z0=64` also fail the full small-
`N` gate under sign alignment.  `K=8,z0=48` and `K=10,z0=40` survived every
case in this follow-up, but the non-delta `N=65536` checks are selected-row
checks rather than a full-vector proof.

The profile work proxy is the implementation's reusable direct-entry count;
FFT timing was deliberately not mixed into this residual study.  The detailed
tables below give the raw maximum errors and reference scales.

| profile `(K,z0)` | `N=65536` direct entries | worst small sign-aligned `E2 / E∞` | high-`N` sign-row `E2 / E∞` | result |
|---|---:|---:|---:|---|
| `(8,32)` | 4,773,761 | `1.1623595668e-12 / 1.5213414457e-12` (`N=256`) | `1.2588843448e-12 / 1.4809116456e-12` | **FAIL** |
| `(8,34)` | 5,025,537 | `4.3768907790e-13 / 5.4021931677e-13` (`N=256`) | `4.5494622068e-13 / 5.5024445962e-13` | **FAIL** |
| `(8,40)` | 5,837,057 | `1.1677035488e-13 / 1.3068389906e-13` (`N=256`) | `1.2202567634e-13 / 1.3502384610e-13` | **FAIL** |
| `(8,48)` | 6,944,505 | `2.5375685320e-14 / 2.5668356329e-14` (`N=256`) | `2.9257650070e-14 / 3.0745548930e-14` | pass in tested cases |
| `(10,40)` | 5,837,057 | `1.3182032533e-15 / 1.3647667377e-15` (`N=256`) | `1.3317280913e-15 / 1.3704642939e-15` | pass in tested cases |
| `(6,64)` | 8,957,697 | `2.0737016460e-12 / 2.8098534363e-12` (`N=256`) | `2.2947841804e-12 / 2.7303698713e-12` | **FAIL** |

Here `E2` is the normalized output L2 error and `E∞` is the scaled Linf
error, computed exactly as in `bench/accuracy.c`:

```text
E2 = sqrt(sum_m |y[m]-yref[m]|^2 / sum_m |yref[m]|^2)
E∞ = max_m |y[m]-yref[m]| / max_m |yref[m]|.
```

The gate is `E2 <= 1e-13` and `E∞ <= 1e-12`.  The small tests use all output
rows and a 256-bit MPFR reference.  The high-`N` non-delta values marked
`sign-row` or `selected-row` use the 17 rows listed below; they are not claimed
to be full-vector metrics.  MPFR sums are rounded to binary64 before the
metrics are formed, matching the specified binary64 API and the existing
accuracy harness; the 256-bit reference error is negligible at this gate.

## Independent construction

The test driver is
[`worker3_followup_adversarial.c`](</Users/alex/areas/productive/orchestration/testing/manual_runs/1/research/worker3_followup_adversarial.c>).
It calls the existing public `dht_plan_create_profile` and `dht_apply` API;
`src/` and `bench/` were not modified.

The driver was compiled with the repository's Apple clang/FFTW/MPFR include
and library paths and run as a standalone binary from `/private/tmp`.

For each profile, the independent MPFR profile evaluator computes

```text
J0_K(z) = sqrt(2/(pi*z)) * sum(q=0..K-1)
          c_q * (-1)^floor(q/2) * trig_q(z-pi/4) / z^q,
```

where `trig_q` is cosine for even `q`, sine for odd `q`, and
`c_(q+1)=c_q*(2q+1)^2/(8(q+1))`, `c_0=1`.  The exact value is MPFR `mpfr_j0`
at 256 bits.  This is a separate scalar implementation, not a readback of
the FFT result.

For an output row `m`, the current C implementation sends input indices

```text
k >= n0,  n0 = ceil(z0*N/(2*pi*2^floor(log2(m))))
```

to the asymptotic path, with the remainder handled directly.  The
sign-aligned input is therefore constructed as

```text
x[k] = 0                                  for k < n0,
x[k] = sign(J0_K(2*pi*m*k/N)-J0(2*pi*m*k/N)) * (1 - 0.375 i)
                                             for k >= n0.
```

The sign is formed in MPFR.  Thus the real residuals in the selected row add
instead of cancelling; the imaginary component applies the same test to the
complex path.  The target row is the first power of two whose asymptotic
region is nonempty: `m=8` for the `z0 <= 48` profiles and `m=16` for
`(K=6,z0=64)`.

The other inputs are deterministic:

* `alternating`: `x[k]=(-1)^k*(1 - i*(0.25+0.5t))`,
  `t=k/(N-1)`.
* `high_dynamic`: `x[k]=(-1)^k*2^e*(1 - i*(0.25+0.5t))`, with
  `e=((37*k+17) mod 601)-300`.  This visits binary64 magnitudes from
  `2^-300` through `2^300` in a repeating permutation while retaining
  alternating cancellation.
* `delta_n1` and `delta_nNm1`: all zero except
  `x[at]=1-0.375i`, for `at=1` and `at=N-1` respectively.

Small full-reference sizes were `N=32,64,128,256`.  At `N=65536`, the MPFR
row set was

```text
0, 1, 2, 3, 4, 6, 7, 8, 10, 15, 16, 31, 32, 64, 1024, 32768, 65535.
```

The two delta inputs also have a full `N=65536` MPFR reference because their
outputs are just one Bessel column times the fixed complex scalar.

## Full small-`N` sign-aligned results

Each cell is `E2 / E∞`; all are full-vector MPFR comparisons.  The raw
maximum error and reference scale are reported for the representative failures
and in the high-`N` tables below.

| `N` | `(8,32)` | `(8,34)` | `(8,40)` | `(8,48)` | `(10,40)` | `(6,64)` |
|---:|---:|---:|---:|---:|---:|---:|
| 32 | `1.2806108677e-13 / 1.3069960936e-13` | `9.6038012796e-14 / 1.2815772973e-13` | `2.6032169323e-14 / 3.6436594637e-14` | `7.3917604055e-15 / 8.0129518169e-15` | `9.5672244018e-16 / 1.0196704713e-15` | `3.9582277237e-13 / 4.8898731228e-13` |
| 64 | `1.0250164452e-12 / 1.6357908730e-12` | `3.4411822999e-13 / 3.9851227346e-13` | `1.1792410781e-13 / 1.2915290375e-13` | `9.7364667754e-15 / 9.1104825675e-15` | `1.3686674012e-15 / 1.3708019166e-15` | `1.9449358951e-12 / 2.8526798445e-12` |
| 128 | `1.0610469975e-12 / 1.5082006942e-12` | `3.9157135947e-13 / 4.6565925719e-13` | `1.1822167529e-13 / 1.3118679208e-13` | `1.8854548153e-14 / 1.8447445611e-14` | `1.2338076477e-15 / 1.2676114636e-15` | `1.7860695971e-12 / 2.7876348728e-12` |
| 256 | `1.1623595668e-12 / 1.5213414457e-12` | `4.3768907790e-13 / 5.4021931677e-13` | `1.1677035488e-13 / 1.3068389906e-13` | `2.5375685320e-14 / 2.5668356329e-14` | `1.3182032533e-15 / 1.3647667377e-15` | `2.0737016460e-12 / 2.8098534363e-12` |

The non-aligned alternating input independently catches `(8,32)`:

```text
N=32:  E2=1.2806108677e-13, E∞=1.3069960936e-13,
       max|error|=5.7352336348e-13, max|reference|=4.3881031188
N=64:  E2=1.2393607926e-13, E∞=1.0379059549e-13
N=128: E2=1.1239282094e-13, E∞=8.5961022377e-14
N=256: E2=1.0517430604e-13, E∞=6.1462221647e-14.
```

`(6,64)` is also far outside the gate on alternating data: at `N=32`,
`E2=3.9582277237e-13`, `E∞=4.8898731228e-13`, and
`max|error|=2.1457267501e-12`.  The high-dynamic-range input is less aligned
with the transition residual at small sizes, but it remained finite and
passed the small gate for every profile.

## `N=65536` selected-row results

These are MPFR comparisons on the selected rows only.  `max|error|` is the
raw absolute error over those rows, and `max|reference|` is the denominator
used for the displayed scaled Linf.

### Alternating and high-dynamic-range inputs

| profile | alternating: `E2 / E∞` | alternating max error | high-dynamic: `E2 / E∞` | high-dynamic max error | row gate |
|---|---:|---:|---:|---:|---|
| `(8,32)` | `5.7596314035e-15 / 2.9782039644e-15` | `5.2733569519e-13` | `1.5462781791e-13 / 2.3151345651e-13` | `7.0340491601e77` | **FAIL** on high-dynamic |
| `(8,34)` | `3.0177664738e-15 / 2.9782039644e-15` | `5.2733569519e-13` | `5.8241664762e-14 / 9.7449611026e-14` | `2.9608013501e77` | pass |
| `(8,40)` | `9.9909129086e-16 / 9.6643237102e-16` | `1.7112135110e-13` | `2.9222886111e-14 / 6.5835612804e-14` | `2.0002765452e77` | pass |
| `(8,48)` | `3.3199017818e-16 / 1.6051568000e-16` | `2.8421709430e-14` | `1.2427031118e-14 / 1.9176085260e-14` | `5.8262499492e76` | pass |
| `(10,40)` | `3.0352509027e-16 / 2.2700345162e-16` | `4.0194366942e-14` | `9.1130834640e-16 / 1.0435904649e-15` | `3.1707300061e75` | pass |
| `(6,64)` | `1.2728260673e-14 / 1.1874906178e-14` | `2.1026303032e-12` | `2.4938726075e-13 / 4.2717970063e-13` | `1.2978956212e78` | **FAIL** on high-dynamic |

For the alternating rows, `max|reference|=1.7706500344e2`; for the
high-dynamic rows it is `3.0382895518e90`.  The enormous raw errors in the
latter table are expected from the deliberately allowed `2^300` input scale;
the normalized metrics are the relevant comparison.

### Residual-sign input

The following is the direct high-`N` evidence against the transition profiles.
`residual L1` is the MPFR sum of the absolute scalar asymptotic residuals in
the sign-aligned target row before the complex factor `1-0.375i` is applied.

| profile | target `m` | `n0` | positive / negative signs | residual L1 | target raw error | target reference magnitude | target relative error |
|---|---:|---:|---:|---:|---:|---:|---:|
| `(8,32)` | 8 | 41,722 | 12,259 / 11,555 | `2.7728345428e-09` | `2.9611522886e-09` | `1.9995468990e3` | `1.4809116456e-12` |
| `(8,34)` | 8 | 44,330 | 12,115 / 9,091 | `1.6640671062e-09` | `1.7770878936e-09` | `1.7632463993e3` | `1.0078500057e-12` |
| `(8,40)` | 8 | 52,152 | 8,176 / 5,208 | `4.0123539692e-10` | `4.2800201556e-10` | `1.0384117721e3` | `4.1216984152e-13` |
| `(8,48)` | 8 | 62,583 | 2,035 / 918 | `3.4373794996e-11` | `3.6678103148e-11` | `1.9013728549e2` | `1.9290326489e-13` |
| `(10,40)` | 8 | 52,152 | 5,212 / 8,172 | `3.8230734375e-12` | `4.3324232621e-12` | `1.0355365623e3` | `4.1837472667e-15` |
| `(6,64)` | 16 | 41,722 | 11,532 / 12,282 | `3.6097361411e-09` | `3.8550386096e-09` | `1.4119107635e3` | `2.7303698713e-12` |

The selected-row aggregate results for these same inputs were:

| profile | `E2` | scaled `E∞` | max raw error | max selected reference | row gate |
|---|---:|---:|---:|---:|---|
| `(8,32)` | `1.2588843448e-12` | `1.4809116456e-12` | `2.9611522886e-09` | `1.9995468990e3` | **FAIL** |
| `(8,34)` | `4.5494622068e-13` | `5.5024445962e-13` | `1.7770878936e-09` | `3.2296334157e3` | **FAIL** |
| `(8,40)` | `1.2202567634e-13` | `1.3502384610e-13` | `4.2800201556e-10` | `3.1698253895e3` | **FAIL** |
| `(8,48)` | `2.9257650070e-14` | `3.0745548930e-14` | `3.6678103148e-11` | `1.1929565229e3` | pass |
| `(10,40)` | `1.3317280913e-15` | `1.3704642939e-15` | `4.3324232621e-12` | `3.1612813858e3` | pass |
| `(6,64)` | `2.2947841804e-12` | `2.7303698713e-12` | `3.8550386096e-09` | `1.4119107635e3` | **FAIL** |

### Full-vector high-`N` delta checks

Both deltas were compared on all 65,536 output rows with MPFR.  These cases
are useful endpoint/aliasing checks but are not adversarial enough to certify
the profiles, because the column itself is a single Bessel sequence.

| profile | delta `n=1`: `E2 / E∞` | delta `n=N-1`: `E2 / E∞` | result |
|---|---:|---:|---|
| `(8,32)` | `1.6354516745e-16 / 2.7755575616e-16` | `9.5233274643e-15 / 1.0835703346e-14` | pass |
| `(8,34)` | `1.6354516745e-16 / 2.7755575616e-16` | `9.5233274643e-15 / 1.0835703346e-14` | pass |
| `(8,40)` | `1.6354516745e-16 / 2.7755575616e-16` | `9.5233274643e-15 / 1.0835703346e-14` | pass |
| `(8,48)` | `1.6354516745e-16 / 2.7755575616e-16` | `9.5233274643e-15 / 1.0835703346e-14` | pass |
| `(10,40)` | `1.6354516745e-16 / 2.7755575616e-16` | `3.1839389510e-16 / 3.3306690739e-16` | pass |
| `(6,64)` | `1.6354516745e-16 / 2.7755575616e-16` | `3.3934114110e-14 / 3.0199207063e-14` | pass |

The largest raw errors in the `n=1` column were `2.9642967752e-16` with
`max|reference|=1.0680004682`; in the `n=N-1` column they were
`1.1572536246e-14` for the eight-term profiles and
`3.2252767282e-14` for `(6,64)`, with the same reference scale.

## Decision

Do not promote `(8,32)`, `(8,34)`, `(8,40)`, or `(6,64)` to a gate-qualified
profile.  The sign-aligned construction exposes the sum of the scalar
asymptotic remainder directly, and the failures are reproduced both in full
small-vector MPFR tests and in selected `N=65536` rows.  `(8,48)` is the
cheapest eight-term profile with positive evidence here; `(10,40)` has a much
larger residual margin and also passes the exact full-vector delta checks.
Neither should be called formally certified from this follow-up alone: a
full arbitrary-input `N=65536` MPFR matvec is infeasible, and the non-delta
large-`N` evidence is row-selected.
