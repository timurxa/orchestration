# Worker 11 — real/complex FFT decomposition

Date: 2026-08-28

## Decision

**Do not promote the FFTW `r2c` split as a standalone optimization at
`N=65536`.** It is correct and has essentially the same accounted scratch
memory, but two real transforms do not produce a stable one-thread apply-time
win over the existing batched complex FFT. On the documented default profile,
the higher-repetition control was `85.062 ms` complex versus `86.872 ms`
split (`+2.1%`). On the research `K=12,z0=18,ratio=4` profile it was `53.552
ms` versus `52.937 ms` (`-1.1%`) in the same sweep, but an independent earlier
run was `52.321 ms` versus `54.349 ms` (`+3.9%`). That spread is not a
promotion-quality gain. The split setup is consistently about `0.4--0.5 s`
longer.

The prototype is numerically sound. It uses two in-place, batched FFTW
real-to-complex plans: one for `Re(x) w_q` and one for `Im(x) w_q`, with the
half-spectrum overlaid on each input row. No files under `src/` or `bench/`
were modified.

## Exact sign and reconstruction

For asymptotic order `q`, let the real input weight be `w_q[k]` and define

\[
 a_q[k] = x[k]w_q[k],\qquad
 \theta_{mk}=2\pi mk/N.
\]

The existing complex backward FFT computes

\[
 F_q[m]=\sum_k a_q[k]e^{+i\theta_{mk}}=C_q[m]+iS_q[m],
\]

where `C_q[m]` and `S_q[m]` are complex cosine and sine projections. Its
partner-bin reconstruction is exactly

\[
 C_q[m]=\frac{F_q[m]+F_q[N-m]}2,
 \qquad
 S_q[m]=\frac{F_q[m]-F_q[N-m]}{2i}.
\]

FFTW `r2c` uses the negative-exponent convention. For
`h=min(m,N-m)`, its two half-spectra are

\[
 U_q[h]=\sum_k\operatorname{Re}(a_q[k])e^{-i\theta_{hk}}
       = C_{q,\mathrm{re}}[h]-iS_{q,\mathrm{re}}[h],
\]

\[
 V_q[h]=\sum_k\operatorname{Im}(a_q[k])e^{-i\theta_{hk}}
       = C_{q,\mathrm{im}}[h]-iS_{q,\mathrm{im}}[h].
\]

Therefore, with

\[
 \sigma_m=\begin{cases}+1,&m\le N/2,\\-1,&m>N/2,\end{cases}
\]

the exact complex projections needed by the existing phase code are

```text
C.re =  Re U[h]          C.im =  Re V[h]
S.re = -sigma_m Im U[h]  S.im = -sigma_m Im V[h].
```

The sign change for `m>N/2` is required because
`sin(2*pi*m*k/N)=-sin(2*pi*(N-m)*k/N)`. At `m=N/2`, the Nyquist bins are
real and the sine projection is zero. No conjugate symmetry of the complex
input is assumed; only the two real channels have the Hermitian symmetry used
by `r2c`.

The existing Bessel-phase reconstruction is then unchanged:

```text
q even: H = (C + S) / sqrt(2)   # cos(theta - pi/4)
q odd:  H = (S - C) / sqrt(2)   # sin(theta - pi/4)
```

`H` is multiplied by the existing output scale for order `q`. The exact axes,
product-safe direct rows, Kahan direct accumulation, geometric bands, and
asymptotic coefficients are all unchanged.

## Timing

All timings below use the deterministic random complex input, one FFTW worker,
two warmups, and raw `dht_apply`/split-apply timings with setup excluded. The
default profile is `K=10,z0=64,ratio=2`. The split has twice as many individual
real 1-D transforms, but they are issued as two batched `r2c` executions per
active band.

| `N` | complex median | split median | split / complex |
|---:|---:|---:|---:|
| 4096 | 2.658 ms | 2.631 ms | 0.990 |
| 16384 | 15.212 ms | 14.468 ms | 0.951 |
| 32768 | 35.215 ms | 34.477 ms | 0.979 |
| 65536 | 85.040 ms | 85.227 ms | 1.002 |

The primary `N=65536` high-repetition sweep (`21` timed applications,
`3` warmups) was:

| profile | complex | split `r2c` | split / complex |
|---|---:|---:|---:|
| default `K=10,z0=64,ratio=2` | 85.062 ms | 86.872 ms | 1.021 |
| candidate `K=12,z0=18,ratio=4` | 53.552 ms | 52.937 ms | 0.989 |

The candidate-profile result is within run-to-run noise: a separate 15-rep
pair gave `52.321 ms` complex and `54.349 ms` split. The phase profile points
to the same conclusion: in the 21-rep default pair, the split FFT phase was
`51.258 ms` versus `48.513 ms` complex, while the direct phase was essentially
unchanged (`28.031 ms` versus `27.918 ms`). The lower-dimensional half-spectrum
does not overcome FFTW's real-plan/codelet and reconstruction costs here.

Reusable setup and accounted memory from that same high-repetition run were:

| profile | complex setup | split setup | complex bytes | split bytes |
|---|---:|---:|---:|---:|
| default | 0.727 s | 1.187 s | 93,681,880 | 93,682,200 |
| candidate | 0.635 s | 1.059 s | 59,054,280 | 59,054,664 |

The split memory delta is only the `N+2` real-FFT row padding (`32` bytes per
order), because the output half-spectrum is in-place. FFTW's opaque plan
allocations are excluded from both byte totals, matching the repository's
existing accounting convention.

## MPFR check

The independent checker uses 256-bit MPFR dense evaluation of `J0`, MPFR
accumulation, and binary64-rounded references. It tests random complex and
complex delta inputs at `N=32,64,128,256` for both profiles:

```text
clang -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic \
  -I/opt/homebrew/include research/worker11_split_accuracy.c \
  -L/opt/homebrew/lib -lmpfr -lgmp -lfftw3_threads -lfftw3 -lm \
  -o research/worker11_split_accuracy
research/worker11_split_accuracy 256
```

All 16 cases passed the repository gate (`normalized L2 <= 1e-13`,
`scaled Linf <= 1e-12`). The largest split error observed was
`L2=3.7326e-14`, `scaled Linf=1.2842e-13`; split-vs-complex stayed below
`1.1e-16` in normalized L2 and `1.6e-16` in scaled Linf.

## Reproducibility boundary

Prototype files:

- `research/worker11_split_impl.h` — private-table adapter and split apply
  implementation; includes `src/dht_asym.c` read-only.
- `research/worker11_split_bench.c` — current-complex versus split timing and
  phase breakdown.
- `research/worker11_split_accuracy.c` — small independent MPFR check.

Benchmark command shape:

```text
clang -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic \
  -I/opt/homebrew/include research/worker11_split_bench.c \
  -L/opt/homebrew/lib -lfftw3_threads -lfftw3 -lm \
  -o research/worker11_split_bench
research/worker11_split_bench 65536 21 3 1 0 0  # current complex
research/worker11_split_bench 65536 21 3 1 0 1  # split r2c
```
