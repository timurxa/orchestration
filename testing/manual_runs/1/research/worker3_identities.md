# Worker 3 — identities, convolution, and Toeplitz structure

## Scope and verdict

I use the natural zero-based grid

\[
 A_{mn}=J_0(\alpha mn),\qquad \alpha=\frac{2\pi}{N},
 \qquad 0\leq m,n<N.
\]

The exact matrix is not Toeplitz, Hankel, circulant, chirp-scaled Toeplitz, or
a function of `mn mod N`.  Therefore there is no exact single ordinary FFT or
convolution reduction.  The useful positive result is a controlled far-field
approximation: the large-argument expansion of `J_0` turns each retained term
into diagonal powers times an exact DFT phase.  Directly evaluating a small
boundary and applying ordinary FFTs to the interior gives, for fixed tolerance,

\[
 O(NL+MN\log N)=O(N^{3/2}+MN\log N),
 \qquad L=\left\lceil\sqrt{\frac{z_*N}{2\pi}}\right\rceil,
\]

where `M` is the number of asymptotic terms and `z_*` is a constant cutoff.
This is substantially below `O(N^2)` for fixed accuracy, but it is approximate,
not an exact identity.  The scratch implementation is
[`worker3_experiment.py`](</Users/alex/areas/productive/orchestration/testing/manual_runs/1/research/worker3_experiment.py>).

The error convention matters.  An entrywise bound `|A-\widetilde A|\leq\epsilon`
is exactly an `\ell_1\to\ell_\infty` operator bound.  For inputs bounded in
`\ell_\infty`, the corresponding bound is `N\epsilon`; a strict
`\ell_\infty\to\ell_\infty` target must therefore use
`\epsilon\leq 10^{-13}/N` and account for floating-point FFT error.

## Literature searched

- The Bessel power series, integral representations, generating function,
  Neumann/Graf addition theorems, and large-argument expansion are collected in
  the [NIST DLMF Bessel chapter](https://dlmf.nist.gov/10).  The specific
  formulas used below are [10.2.2](https://dlmf.nist.gov/10.2.E2),
  [10.9.4](https://dlmf.nist.gov/10.9.E4),
  [10.12.1–3](https://dlmf.nist.gov/10.12),
  [10.23.2 and 10.23.7](https://dlmf.nist.gov/10.23.ii), and
  [10.17.1–3](https://dlmf.nist.gov/10.17).
- Townsend, *A fast analysis-based discrete Hankel transform using asymptotic
  expansions*, SIAM J. Numer. Anal. 53 (2015), DOI
  [10.1137/151003106](https://doi.org/10.1137/151003106), explicitly combines
  the large-argument Bessel expansion, FFTs, and Neumann addition for
  Schlömilch/Fourier–Bessel products `J_\nu(r_k\omega_n)`.  It reports
  `O(N(log N)^2/log log N)` for its partitioned Schlömilch algorithm and gives
  error-selection rules; the simpler global-boundary version tested here is
  `O(N^{3/2}+MN log N)`.
- The standard displacement-rank framework is due to Kailath, Kung, and Morf,
  *Displacement ranks of matrices and linear equations*, J. Math. Anal. Appl.
  68 (1979), DOI
  [10.1016/0022-247X(79)90124-0](https://doi.org/10.1016/0022-247X(79)90124-0).
- For the chirp identity used as a comparison, see Rabiner, Schafer, and Rader,
  *The Chirp z-Transform Algorithm and Its Application*, Bell Syst. Tech. J.
  48 (1969), DOI
  [10.1002/j.1538-7305.1969.tb04268.x](https://doi.org/10.1002/j.1538-7305.1969.tb04268.x).

## Exact identities and why they do not give an ordinary convolution

### Integral / Jacobi–Anger representation

From the Poisson integral,

\[
 J_0(z)=\frac1\pi\int_{-1}^{1}\frac{e^{izt}}{\sqrt{1-t^2}}\,dt
       =\frac1{2\pi}\int_0^{2\pi}e^{iz\cos\theta}\,d\theta.
\]

Consequently, for `X(\omega)=\sum_n x_n e^{i\omega n}`,

\[
 (Ax)_m=\frac1{2\pi}\int_0^{2\pi}
 X\!\left(\frac{2\pi m}{N}\cos\theta\right)d\theta.
 \tag{1}
\]

This is exact, but the frequencies in (1) are continuous and depend on `m`.
They are not the `N` uniform DFT frequencies.  Uniform angular quadrature does
not change that conclusion.  Jacobi–Anger gives the exact alias identity

\[
 \frac1K\sum_{q=0}^{K-1}e^{iz\cos(2\pi q/K)}
   =\sum_{\ell\in\mathbb Z}i^{\ell K}J_{\ell K}(z).
 \tag{2}
\]

The right side has nonzero aliases for finite `K`; resolving all arguments up to
`z_{\max}=\alpha(N-1)^2\simeq2\pi N` needs a number of quadrature modes that
grows with `N`.  Thus (1) is a continuous-superposition/NUFFT route, not a
fixed number of ordinary FFTs.

### Generating function and Taylor separation

The generating function

\[
 e^{\frac z2(t-t^{-1})}=\sum_{k\in\mathbb Z}t^kJ_k(z)
\]

and the order-zero power series give

\[
 J_0(\alpha mn)=\sum_{k=0}^{\infty}
 \frac{(-1)^k(\pi/N)^{2k}}{(k!)^2}\,m^{2k}n^{2k}.
 \tag{3}
\]

The first `R` terms are a rank-`R` separable matrix and cost `O(RN)` to apply.
However, the largest argument is `z_{\max}\simeq2\pi N`, and the Taylor-term
ratio is

\[
 \frac{|t_{k+1}|}{|t_k|}=\frac{z^2}{4(k+1)^2}.
\]

The terms peak near `k=z/2`; uniform accuracy through the far corner therefore
requires `R=\Theta(N)`, returning to `O(N^2)` work.  Formula (3) remains useful
for genuinely small-product boundary blocks.

### Neumann and Graf addition

Neumann's addition theorem specializes to

\[
 J_0(u-v)=\sum_{k\in\mathbb Z}J_k(u)J_k(v),
 \qquad
 J_0(u+v)=\sum_{k\in\mathbb Z}(-1)^kJ_k(u)J_k(v).
 \tag{4}
\]

Graf's theorem gives the radial-distance form

\[
 J_0\!\left(\sqrt{u^2+v^2-2uv\cos\vartheta}\right)
 =\sum_{k\in\mathbb Z}J_k(u)J_k(v)e^{ik\vartheta}.
 \tag{5}
\]

These are exact separations for a sum/difference or a Euclidean distance of two
radii.  The target argument is the product `\alpha mn`, not one of those
arguments, so (4)–(5) do not produce a fixed difference kernel or an ordinary
convolution.  The addition theorem is useful in Townsend's *perturbed-grid*
algorithm, but there the perturbation is small; there is no small perturbation
to exploit in the exact integer product grid.

### Schlömilch and Poisson summation

Applying Poisson summation to the integral representation, with Abel
regularization because the Bessel samples are not absolutely summable, gives

\[
 \sum_{n\in\mathbb Z}J_0(an)
 =2\sum_{k:\,|2\pi k|<a}\frac1{\sqrt{a^2-(2\pi k)^2}}.
 \tag{6}
\]

In particular, for `0<a<2\pi`,

\[
 1+2\sum_{n=1}^{\infty}J_0(an)=\frac2a.
 \tag{7}
\]

For `a=2\pi m/N`, `1\leq m<N`, this gives `N/(\pi m)`.  It is a useful
unweighted Schlömilch check, but it does not evaluate
`\sum_n x_nJ_0(\alpha mn)` for arbitrary weights `x_n`; the finite window also
leaves a nontrivial tail.  The general Poisson formula used in this derivation
is [DLMF 1.8.14](https://dlmf.nist.gov/1.8.E14).

### Product-index and logarithmic-grid ideas

On a geometric grid, `m_i=m_0q^i`, `n_j=n_0q^j`, the product depends on
`i+j`, so a Bessel product kernel becomes Hankel-like in log coordinates.  The
present grid is arithmetic (`m=i`, including zero), and `log i` is not uniform;
resampling it changes the operator and leads to a nonuniform transform.

A multiplicative cyclic convolution would require `A_{mn}=f(mn\bmod N)`.  That
is false because `J_0` is not periodic in its argument.  For example, at `N=8`,
`1\cdot1\equiv3\cdot3\pmod 8`, but

\[
 A_{1,1}=0.8516319137048081,
 \qquad A_{3,3}=0.2996954444624918.
 \tag{8}
\]

Dirichlet convolution sums over divisors, whereas the present row sums over all
`n`; no divisor reindexing removes the `N^2` pair set for arbitrary `x`.

## Toeplitz, displacement, and chirp tests

For `N=4`, direct evaluation is

\[
\begin{bmatrix}
1&1&1&1\\
1&0.472001215768235&-0.304242177644094&-0.265857249958324\\
1&-0.304242177644094&0.220276908539934&-0.181211453508928\\
1&-0.265857249958324&-0.181211453508928&0.151323266251391
\end{bmatrix}.
\]

The diagonal is not constant (`A_{00}\ne A_{11}`), so the matrix is not
Toeplitz; anti-diagonals also fail (`A_{02}\ne A_{11}`), so it is not Hankel.
The first row is all ones, while the second row is not, so it cannot be
circulant.  The standard shift residuals confirm that this is not a low
displacement-rank matrix.  With `Z` the nilpotent down-shift and `P` the cyclic
down-shift, a Toeplitz matrix has `rank(ZA-AZ)\le2`, a Hankel matrix has
`rank(ZA-AZ^T)\le2`, and a circulant commutes with `P`.  The scratch test gives

| `N` | `rank(ZA-AZ)` | `rank(ZA-AZ^T)` | `rank(PA-AP)` |
|---:|---:|---:|---:|
| 4  | 4  | 4  | 4  |
| 8  | 8  | 8  | 8  |
| 16 | 16 | 16 | 16 |

Ranks use a `10^{-12}` relative singular-value threshold; this is a numerical
diagnostic, while the `N=4` entrywise contradictions are exact.

Bluestein's DFT factorization is

\[
 e^{-2\pi imn/N}
 =e^{-\pi im^2/N}e^{-\pi in^2/N}e^{+\pi i(m-n)^2/N},
 \tag{9}
\]

which works because the exponential converts a bilinear product to a quadratic
difference.  There is no corresponding one-term factorization for `J_0`.  If
`A_{mn}=u_mv_nh_{m-n}`, then for fixed `d=m-n`

\[
 \frac{A_{mn}A_{m+1,n+1}}{A_{m,n+1}A_{m+1,n}}
 =\frac{h_d^2}{h_{d-1}h_{d+1}}
\]

must be independent of position along that diagonal.  At `N=8`, the two
`d=0` values from the scratch test are `-1.163014458850461` and
`-1.2900381276438022`, so even a diagonal-scaled Toeplitz/chirp convolution is
ruled out.

## Positive result: asymptotic expansion plus ordinary FFTs

The large-argument expansion in [DLMF 10.17.3](https://dlmf.nist.gov/10.17.E3)
is, for `z>0`,

\[
 J_0(z)=\sqrt{\frac2{\pi z}}
 \left[
 \cos\phi\sum_{r=0}^{M-1}\frac{(-1)^ra_{2r}(0)}{z^{2r}}
 -\sin\phi\sum_{r=0}^{M-1}\frac{(-1)^ra_{2r+1}(0)}{z^{2r+1}}
 \right]+R_M(z),
 \qquad \phi=z-\frac\pi4,
 \tag{10}
\]

where

\[
 a_0(0)=1,\qquad
 a_k(0)=\prod_{j=1}^{k}\frac{-(2j-1)^2}{8j}.
\]

The real-positive error rule in [DLMF 10.17(iii)](https://dlmf.nist.gov/10.17.iii)
bounds the two remainders by their first omitted terms, hence the conservative
entrywise bound used here is

\[
 |R_M(z)|\leq E_M(z):=
 \sqrt{\frac2{\pi z}}
 \left(\frac{|a_{2M}(0)|}{z^{2M}}+
       \frac{|a_{2M+1}(0)|}{z^{2M+1}}\right).
 \tag{11}
\]

Set `z_*` so `E_M(z_*)\le\epsilon` and choose
`L=ceil(sqrt(z_*N/(2\pi)))`.  Then all interior cells `m,n\ge L` satisfy
`\alpha mn\ge z_*`; evaluate the `2NL-L^2` boundary cells directly.

For an interior power `p`, define

\[
 T_p(m)=\sum_{n=L}^{N-1}n^{-p}x_ne^{i\alpha mn}.
\]

One length-`N` inverse FFT of the vector with entries `n^{-p}x_n` (zero below
`L`) computes all `T_p(m)`.  The reversed bins give the negative-exponent sum,
so

\[
 C_p(m)=\frac12\left(e^{-i\pi/4}T_p(m)+e^{i\pi/4}T_p(-m)\right),
\]

\[
 S_p(m)=\frac1{2i}\left(e^{-i\pi/4}T_p(m)-e^{i\pi/4}T_p(-m)\right).
\]

With `p_r=2r+1/2` and `q_r=2r+3/2`, the FFT part is exactly

\[
 \widetilde y_m=
 \sum_{r=0}^{M-1}\left[
 \sqrt{\frac2\pi}(-1)^ra_{2r}(0)\alpha^{-p_r}m^{-p_r}C_{p_r}(m)
 -\sqrt{\frac2\pi}(-1)^ra_{2r+1}(0)\alpha^{-q_r}m^{-q_r}S_{q_r}(m)
 \right].
 \tag{12}
\]

There are `2M` ordinary FFTs for complex input, plus `O(NL)` direct boundary
work and `O(N)` storage.  The global-boundary scratch is intentionally simpler
than Townsend's partitioned `O(N(log N)^2/log log N)` algorithm; it avoids the
catastrophic cancellation that occurs if (12) is evaluated on small `mn` and
then corrected.

For `M=12` and `epsilon=10^{-15}`, solving (11) gives
`z_*=16.49561245092576`.  The direct boundary and binary64 checks were:

| `N` | direct boundary pairs | max scalar error on FFT interior | max error for stress matvec |
|---:|---:|---:|---:|
| 4   | 16    | `0.000e+00` | `5.551e-17` |
| 8   | 55    | `2.498e-16` | `3.249e-16` |
| 16  | 175   | `3.272e-16` | `1.617e-15` |
| 32  | 540   | `3.504e-16` | `4.433e-15` |
| 64  | 1495  | `1.259e-15` | `1.201e-14` |
| 128 | 4503  | `1.281e-15` | `2.428e-14` |
| 256 | 12636 | `2.056e-15` | `6.383e-14` |

The command is:

```text
python3 -u research/worker3_experiment.py \
  --ns 4 8 16 32 64 128 256 --terms 12 --entry-tol 1e-15
```

For independent scale checking, complex random vectors normalized to
`||x||_1=1` gave maximum errors `1.49e-16`, `1.40e-16`, `1.38e-16`,
`1.76e-16`, and `1.64e-16` at `N=128,256,512,1024,2048`, respectively.
These compare against direct dense `A@x` in binary64; they validate the
operator scaling but are not a proof of a worst-case binary64 accumulation
bound.  The formal mathematical truncation guarantee is (11), while FFT and
Bessel-evaluation roundoff must be budgeted separately.

## Promotion decision

1. **Do not promote an exact ordinary FFT/convolution, Toeplitz, chirp, or
   multiplicative-cyclic identity.**  Equations (8), the `N=4` matrix, full
   standard displacement ranks, and the cross-ratio test are direct failures.
2. **Promote only the conditional approximate route:** large-argument Bessel
   expansion + `2M` ordinary FFTs + direct small boundary.  It has a certified
   entrywise/`\ell_1\to\ell_\infty` truncation bound and fixed-tolerance
   `O(N^{3/2}+MN\log N)` arithmetic; the tested stress matvec is below
   `10^{-13}` through `N=256`.
3. **Hold promotion for a strict `\ell_\infty` unit-input guarantee at large
   `N`.**  That interpretation needs an entry budget of `10^{-13}/N` and a
   roundoff-aware implementation (or the more sophisticated partitioned
   algorithm).  This scratch experiment does not establish that worst-case
   binary64 claim.

No files under `src/` or `bench/` were edited.
