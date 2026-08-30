# Worker 1 — asymptotic Bessel + FFT specialization

Date: 2026-08-28

## Decision

**Promote the idea, with an important restriction:** the exact grid admits a
plausible quasilinear transform, but only if the asymptotic formula is applied
on product-safe rectangular blocks. A single global asymptotic FFT followed by
small-entry correction is numerically unusable because the inverse powers in
the asymptotic series overflow/cancel at the `(m,n)=(1,1)` corner.

The exact grid is simpler than Townsend's Bessel-root DHT: there is no root
perturbation, so Neumann addition is vacuous. Beckman--O'Neil's generic NUFHT
also applies and has an `O(N log N)` theorem for this grid's `p=O(N)` regime,
but its Type-III NUFFTs should be replaced by ordinary/pruned FFT structure
only with care. A straightforward stable FFT-block prototype is
`O(M N log^2 N)` (fixed accuracy: quasilinear); Townsend's geometric block
partition gives his sharper `O(M N (log N)^2/log log N)` bound.

## Sources inspected

* Alex Townsend, [A fast analysis-based discrete Hankel transform using
  asymptotic expansions](https://arxiv.org/abs/1501.01652) (SIAM J. Numer.
  Anal. 53 (2015), [published version](https://doi.org/10.1137/151003106)),
  and the [public MATLAB implementation](https://github.com/ajt60gaibb/FastAsyTransforms).
  It combines the large-argument Bessel expansion, FFT/DCT/DST embeddings,
  and Neumann addition; the stated DHT cost is
  `O(N (log N)^2/log log N)`.
* Paul G. Beckman and Michael O'Neil, [A Nonuniform Fast Hankel
  Transform](https://doi.org/10.1137/25M1796758), with the [arXiv
  manuscript](https://arxiv.org/abs/2411.09583) and [reference Julia
  implementation](https://github.com/pbeckman/FastHankelTransform.jl).
  The implementation's `add_asy!` uses two Type-III NUFFTs per asymptotic
  index and its `add_loc!` uses the Wimp/Chebyshev local expansion.
* NIST DLMF [Hankel expansion (10.17.3)](https://dlmf.nist.gov/10.17.E3),
  [real-argument remainder bounds](https://dlmf.nist.gov/10.17.iii), and
  [Neumann addition (10.23.2)](https://dlmf.nist.gov/10.23.2).

## Exact-grid identification

For

\[
A_{mn}=J_0(2\pi mn/N),\qquad m,n=0,\ldots,N-1,
\]

take either

\[
r_m=m/N,\quad \omega_n=2\pi n,
\qquad\text{or}\qquad
r_m=m,\quad \omega_n=2\pi n/N.
\]

Then `omega_n*r_m` is exactly the requested argument. Thus the positive
indices are an equispaced Schlömilch-style product grid, not the perturbed
Bessel-root grid used in Townsend's Section 6 DHT. The zero row and column
are exact special cases:

\[
(Ac)_0=\sum_n c_n,\qquad (Ac)_m\supset c_0\quad(m>0),
\]

because `J_0(0)=1`.

## Central formula: large-argument Bessel terms become FFTs

For `nu=0`, set `phi=-pi/4` and

\[
a_k(0)=\frac{\prod_{j=1}^k (-(2j-1)^2)}{k!\,8^k}.
\]

The `M`-term Hankel expansion is

\[
\widetilde J_{0,M}(z)=\sqrt{\frac{2}{\pi z}}
\sum_{\ell=0}^{M-1}(-1)^\ell\left[
 a_{2\ell}(0)\frac{\cos(z+\phi)}{z^{2\ell}}
 -a_{2\ell+1}(0)\frac{\sin(z+\phi)}{z^{2\ell+1}}
\right].
\]

For a block with input indices `n in I_n`, define

\[
x^{(q)}_n=c_n n^{-q}{\bf 1}_{n\in I_n},\qquad n\ge 1,
\]

and the two ordinary length-`N` DFTs

\[
F_\pm x(m)=\sum_{n=0}^{N-1}x_n e^{\pm 2\pi i mn/N}.
\]

The phase sums are

\[
\begin{aligned}
C_q(m)&=\sum_{n\in I_n}c_n n^{-q}\cos(2\pi mn/N+\phi)\\
 &=\tfrac12\left(e^{i\phi}F_+x^{(q)}(m)+e^{-i\phi}F_-x^{(q)}(m)\right),\\
S_q(m)&=\sum_{n\in I_n}c_n n^{-q}\sin(2\pi mn/N+\phi)\\
 &=\tfrac1{2i}\left(e^{i\phi}F_+x^{(q)}(m)-e^{-i\phi}F_-x^{(q)}(m)\right).
\end{aligned}
\]

Writing `rho=N/(2*pi)`, the asymptotic block matvec is

\[
\boxed{
\begin{aligned}
\widetilde y_m=\sqrt{\frac2\pi}\sum_{\ell=0}^{M-1}(-1)^\ell\bigg[&a_{2\ell}(0)\,\rho^{2\ell+1/2}m^{-2\ell-1/2}C_{2\ell+1/2}(m)\\
 &-a_{2\ell+1}(0)\,\rho^{2\ell+3/2}m^{-2\ell-3/2}S_{2\ell+3/2}(m)\bigg].
\end{aligned}}
\]

This is exactly diagonal scalings, followed by ordinary FFTs, followed by
diagonal scalings. For real `c`, `F_-x=conj(F_+x)`, so one complex FFT per
power is enough and its real/imaginary parts give both phase sums. For general
complex `c`, apply the real operator to real and imaginary parts, or compute
both signs; this is only a constant-factor difference.

## Product-safe block partition

The asymptotic series must never be evaluated below its cutoff. Let `eta` be
the desired entrywise asymptotic error, and choose `z_*` so that

\[
B_M(z_*):=\sqrt{\frac2{\pi z_*}}
\left(\frac{|a_{2M}(0)|}{z_*^{2M}}+
      \frac{|a_{2M+1}(0)|}{z_*^{2M+1}}\right)\le\eta.
\]

For each dyadic output band

\[
I_i=[b_i,\min(2b_i-1,N-1)],\qquad b_i=2^i,
\]

set

\[
n_i=\left\lceil \frac{z_*N}{2\pi b_i}\right\rceil.
\]

If `n_i <= N-1`, apply the boxed FFT formula only to the rectangle

\[
I_i\times[n_i,N-1].
\]

Every nonzero entry in that rectangle has
`2*pi*m*n/N >= 2*pi*b_i*n_i/N >= z_*`. All remaining positive-index pairs
are evaluated directly with `J0`, together with the exact zero row/column.
There is no subtraction of a huge asymptotic value from a direct value.

For fixed `z_*`, the number of direct positive pairs is

\[
\sum_i |I_i|(n_i-1)_+=O(N\log N),
\]

since each nonempty dyadic band contributes `O(z_* N)`, and there are
`O(log N)` bands. Reusing one length-`N` FFT buffer gives `O(N)` extra memory;
materializing the direct correction list would instead cost `O(N log N)`
memory and is unnecessary. The simple dyadic scheme uses `O(log N)` blocks,
`2M` FFTs per block for real data, and therefore costs

\[
O(MN(\log N)^2)+O(N\log N).
\]

Townsend's geometric masks (his `beta=min(3/log N,0.8)` construction) reduce
the number of full-length FFT blocks to `O(log N/log log N)` and give the
published `O(MN(log N)^2/log log N)` cost. The same masks are easier here:
there is no Neumann/Taylor correction for perturbed roots. A future optimized
implementation should use those masks or a p-based/pruned transform rather
than the prototype's dyadic bands.

## What happens to NUFHT, Toeplitz, and convolution structure?

| Object | Exact specialization | Caveat |
|---|---|---|
| Full-grid Type-III phase | Ordinary length-`N` DFT, because `m,n` are integer grids and the phase is `2*pi*mn/N`. | Zero indices must be handled before inverse-power scalings. |
| Adaptive asymptotic block | A masked DFT of a contiguous subvector; use a zero-padded FFT, or an exact chirp-z/Bluestein convolution. | A full length-`N` FFT per block gives the extra `log N` in the simple bound. |
| Phase subblock | After local indices `a,b`, `exp(+-2*pi*i*a*b/N)` obeys `exp(+-pi*i*a^2/N) exp(+-pi*i*b^2/N) exp(-+pi*i*(a-b)^2/N)`, hence is Toeplitz after diagonal chirps and is applied by linear convolution. | This applies to the oscillatory phase, not to the exact Bessel matrix. |
| Full exact `A` | Not Toeplitz, not Hankel, and not an ordinary convolution: `A_{m,n}` depends on the product `mn`, while `J0` is not periodic under `mn -> mn+N`. | The power factors in each asymptotic term are separable diagonal weights. |
| Precomputation | `a_k(0)`, cutoff, band boundaries, powers, chirp tables, and FFT plans are reusable; no `N^2` matrix is needed. | Direct entries may be precomputed at `O(N log N)` memory, but streaming them is cheaper. |

Beckman--O'Neil's theorem gives

\[
O\big((L+M)(m+n)\log\min(m,n)+Mp\log p\big),
\quad p=(\omega_{\max}-\omega_{\min})(r_{\max}-r_{\min}).
\]

Here `m=n=N` and `p ~= 2*pi*N`, so their generic NUFHT is `O(N log N)` at
fixed tolerance/order. Their code calls `nufft1d3!` twice per asymptotic index;
on the exact full grid those calls can be replaced by FFTs, but on a small
masked block the p-based Type-III cost is not automatically matched by a
full-length FFT. This is why the strongest production path is either (a) keep
the generic Type-III NUFHT with exact-grid fast paths, or (b) implement a
pruned/chirp-z block transform together with the product-safe partition.

## Neumann-addition specialization

Townsend uses

\[
J_\nu(z+\delta z)=\sum_{s=-\infty}^{\infty}J_{\nu-s}(z)J_s(\delta z)
\]

to absorb a perturbation of an equally spaced Bessel-root grid. In the exact
matrix, choose the reference grid equal to the data grid, so `delta z=0`.
Then `J_s(0)=0` for `s != 0` and `J_0(0)=1`; only the `s=0` term remains, and
the Taylor inner sum also collapses to its zeroth term. Consequently there is
no `K` or `T` Neumann/Taylor overhead, no perturbed-root error, and no reason
to evaluate shifted-order Bessel transforms.

## Accuracy at `1e-13`

Use the DLMF/Townsend first-neglected-term bound for the asymptotic blocks,
and direct `J0` evaluation for everything below `z_*`. A conservative binary64
choice used below is

* `eta=1e-15` entrywise,
* `M=6`, for which solving the bound gives `z_*=29.999031...`; use `30`.

Then the exact arithmetic matvec error is bounded by

\[
\|y-\widetilde y\|_\infty\le \eta\|c\|_1,
\]

before FFT roundoff. For a requested absolute output tolerance, set `eta`
relative to the actual input `||c||_1`; for a scale-free gate, normalize
`||c||_2=1` and report relative 2-norm error. The FFT arithmetic error is the
remaining practical limit, so compensated accumulation or higher-precision
FFT is needed for a formal worst-case absolute guarantee at very large `N`.

## Cheapest falsification experiment and result

Prototype: Python/NumPy ordinary FFTs implementing the boxed formula, direct
`scipy.special.j0` on the complement, and exact zero row/column. Reference:
dense direct matrix-vector multiplication with `scipy.special.j0`; an
independent 140-decimal `Decimal` implementation of the convergent power
series for `J0` was also used at `N=32`.

The workspace acceptance gate is normalized L2 `<=1e-13` and scaled Linf
`<=1e-12`. The prototype used `M=6`, `z_*=30`, dyadic bands, and unit-2-norm
inputs.
The table reports the worst case among delta, all-ones, alternating, and
random complex inputs at each `N` (the `N=2048` row is the random test).

| `N` | asymptotic blocks | direct positive pairs | worst relative 2-norm | worst max absolute |
|---:|---:|---:|---:|---:|
| 64 | 3 | 1,337 | `2.4e-15` | `1.0e-15` |
| 128 | 4 | 3,289 | `8.1e-15` | `6.0e-15` |
| 256 | 5 | 7,801 | `1.1e-14` | `7.2e-15` |
| 512 | 6 | 18,049 | `2.8e-14` | `2.5e-14` |
| 1024 | 7 | 40,993 | `5.1e-14` | `4.8e-14` |
| 2048 | 8 | 91,769 | `5.9e-14` | `1.1e-14` |

The independent 140-decimal `N=32` reference gave max absolute error
`4.47e-16` and max error divided by the largest reference component
`4.66e-16`.

The tempting **global** asymptotic FFT, even with exact direct correction on
all `z<30` entries, fails because it still forms unstable inverse powers in
the FFT stage:

| `N` | global-asymptotic max absolute | global relative 2-norm |
|---:|---:|---:|
| 64 | `1.09e-3` | `8.2e-4` |
| 128 | `1.63e1` | `7.1e0` |
| 256 | `1.69e4` | `6.9e3` |

Therefore the decisive failure mode is known and avoided: **never use a
global asymptotic FFT; mask product-safe rectangles first**. The stable
rectangular prototype survives the `1e-13` small-`N` gate and is a credible
near-linear candidate, subject to implementing the FFT-block/NUFHT fast path
and a larger-N roundoff test in the shared benchmark harness.
