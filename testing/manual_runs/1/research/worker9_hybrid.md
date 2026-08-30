# Worker 9 — local-series / masked-FFT hybrid

Date: 2026-08-28

## Decision

**Reject for promotion.** The hybrid is mathematically valid and passes the
repository acceptance gate, but the local series is slower than the existing
direct transition loop at `N=65536`. It saves reusable storage, not apply time:
the repeated benchmark median was about `2.5%` slower than a matched
ratio-2/asymptotic profile. The prototype remains useful as a falsified and
reproducible local-expansion control.

Prototype: [`worker9_hybrid.c`](worker9_hybrid.c).

## Hybrid formula

Let

\[
 A_{mn}=J_0(\alpha mn),\qquad \alpha=2\pi/N.
\]

The exact axes are handled first:

\[
 y_0=\sum_{n=0}^{N-1}x_n,\qquad y_m\mathrel{+}=x_0\quad(m>0).
\]

For the low-product staircase, use the convergent local series

\[
 J_0(z)=\sum_{r=0}^{R-1}c_rz^{2r}+\rho_R(z),
 \qquad c_r=\frac{(-1)^r}{4^r(r!)^2}.
\]

For each positive row define

\[
 L_m=\min\left(N-1,\left\lfloor\frac{z_L}{\alpha m}\right\rfloor\right),
 \qquad
 M_r(q)=\sum_{n=1}^{q}x_n(\alpha n)^{2r}.
\]

Then the local contribution is applied as

\[
 y_m^{\rm loc}=\sum_{r=0}^{R-1}c_rm^{2r}M_r(L_m).
 \tag{1}
\]

Rows are visited in decreasing `m`, so each input index is added to the
prefix moments once. This is the exact-grid specialization of the local,
low-rank side of the Beckman–O'Neil/Wimp strategy: the origin-centered local
box expansion collapses to separable product powers, so no NUFFT or local
matrix is needed.

The transition strip is still evaluated exactly from a setup-time table:

\[
 y_m^{\rm mid}=\sum_{n=L_m+1}^{F_{b(m)}-1}x_nJ_0(\alpha mn),
 \qquad
 F_b=\left\lceil\frac{z_FN}{2\pi b}\right\rceil,
\]

where `b(m)` is the largest power of two no larger than `m`. Therefore every
entry left for the far routine satisfies `\alpha mn\ge z_F`.

For the far rectangle `m\in[b,2b)` and `n\ge F_b`, use Townsend's large-
argument expansion

\[
 J_0(z)\sim\sqrt{\frac{2}{\pi z}}
 \left[
 \cos(z-\pi/4)\sum_{j\ge0}\frac{(-1)^ja_{2j}(0)}{z^{2j}}
 -\sin(z-\pi/4)\sum_{j\ge0}\frac{(-1)^ja_{2j+1}(0)}{z^{2j+1}}
 \right].
 \tag{2}
\]

The powers split as

\[
 z^{-(q+1/2)}=\alpha^{-(q+1/2)}m^{-(q+1/2)}n^{-(q+1/2)}.
\]

Thus each retained order is one weighted length-`N` DFT. The opposite phase
is read from the partner bin `N-m`; this is valid for the specified complex
input because it does not assume conjugate input symmetry. The canonical
prototype uses `R=24`, `z_L=8`, ten far orders (`q=0,...,9`), `z_F=64`, and
dyadic blocks.

The local truncation check is elementary. If

\[
 t_R(z_L)=\frac{(z_L^2/4)^R}{(R!)^2},
 \qquad q_R=\frac{z_L^2}{4(R+1)^2}<1,
\]

then, once the terms decrease,

\[
 |\rho_R(z)|\le \frac{t_R(z_L)}{1-q_R},\qquad 0\le z\le z_L.
 \tag{3}
\]

At `z_L=8`, `R=24`, this bound is `2.11e-19`. The DLMF real-argument
remainder rule for (2) gives `1.03e-17` for the first omitted even/odd pair at
`z_F=64` with ten retained orders. Sources: [DLMF §10.8](https://dlmf.nist.gov/10.8),
[DLMF §10.17(iii)](https://dlmf.nist.gov/10.17.iii),
[Townsend](https://arxiv.org/abs/1501.01652), and
[Beckman–O'Neil](https://arxiv.org/abs/2411.09583).

## Complexity and reusable state

For fixed `R`, `z_L`, `z_F`, and dyadic blocking:

\[
 T(N)=O(RN)+O(D_N)+O(B_NMN\log N),
 \qquad B_N=O(\log N),
\]

where `D_N` is the direct transition count. Hence the simple full-FFT
prototype is `O(MN(log N)^2+N log N)` apply work, with an additional `O(RN)`
local moment/evaluation pass. It uses `O(MN+D_N+R)` reusable memory. The
local region itself is not stored as a matrix.

At `N=65536`, the canonical layout was:

| quantity | hybrid | matched existing profile |
|---|---:|---:|
| local series terms | 24 | — |
| far orders / dyadic far blocks | 10 / 12 | 10 / 12 |
| local positive pairs replaced | 922,648 | 0 |
| setup-time direct entries | 8,035,049 | 8,957,697 |
| plan bytes | 86,826,104 | 93,681,880 |

The hybrid removes `10.3%` of the direct entries and `7.3%` of the plan
storage. It does not reduce the FFT count.

## Falsification and accuracy

The reference is independent 256-bit MPFR evaluation of `J0` and MPFR
accumulation for dense small matrices. For large `N`, full-length impulse
vectors reduce the reference to one MPFR Bessel evaluation per output and are
still exact matvec tests.

Canonical command:

```text
clang -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic \
  -I/opt/homebrew/include research/worker9_hybrid.c src/dht_asym.c \
  -L/opt/homebrew/lib -lmpfr -lgmp -lfftw3_threads -lfftw3 -lm \
  -o research/worker9_hybrid
research/worker9_hybrid check 512 24 8 10 64 2
```

All 25 dense cases (`N=32,64,128,256,512`, five deterministic complex input
families) passed. The worst dense `N=512` values were:

| test aggregate | normalized L2 | scaled Linf |
|---|---:|---:|
| worst of five cases | `8.79e-15` | `1.63e-14` |
| delta, `N=65536`, `n=1` | `2.50e-15` | `9.05e-15` |
| delta, `N=65536`, `n=N-1` | `2.59e-15` | `2.85e-15` |
| delta, `N=65536`, `n=324` (local boundary) | `6.00e-15` | `1.99e-14` |

The explicit order falsification was:

```text
research/worker9_hybrid check 32 18 8 10 64 2
```

It fails on the first dense random case with `rel_l2=1.8291e-11` and
`scaled_linf=1.9028e-11`. Its bound from (3) is `1.21e-10`; lowering the local
order is therefore not a viable speed shortcut.

## Runtime measurement

The benchmark uses the same deterministic random complex input, three warmups,
and thirteen timed applications. `FFTW_MEASURE` plan construction is outside
apply time; FFTW wisdom is cleared before each plan build. The following are
three independent process runs of
`research/worker9_hybrid bench 65536 13 3 24 8 10 64 2`:

| run | hybrid median s | matched profile median s | matched / hybrid |
|---:|---:|---:|---:|
| 1 | `0.086461` | `0.085478` | `0.9886` |
| 2 | `0.088067` | `0.085250` | `0.9680` |
| 3 | `0.087679` | `0.085632` | `0.9767` |
| median of runs | `0.087679` | `0.085478` | `0.9749` |

The corresponding median reusable setup times were `0.7085 s` hybrid and
`0.7173 s` matched profile; plan storage is the more stable distinction. The
local moment pass costs more than the `0.92M` direct multiply-adds it removes,
so the small setup/memory reduction does not translate to an apply win.

For attribution, a coarser ratio-4 control with the same `z_L=8,R=24` local
series and eight far orders measured `0.06788 s` hybrid versus `0.06647 s` for
the matched far-only profile. The large speedup relative to the repository's
ratio-2 default comes from halving the number of far blocks, not from the local
series; it also increases the direct transition count to `12.0M` and plan
storage to `114.5 MB`.

## Reproducibility boundary

Only [`worker9_hybrid.c`](worker9_hybrid.c), this report, and the scratch
executable `research/worker9_hybrid` were produced under `research/worker9_*`.
No files under `src/` or `bench/` were edited.
