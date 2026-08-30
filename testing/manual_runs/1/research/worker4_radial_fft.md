# Worker 4 — radial FFT / projection-slice

## Decision

The literal projection-slice, angular-plane-wave, Cartesian-FFT, and polar-FFT
embeddings do **not** pass the exact-grid gate.  They either need
`Q = Theta(N)` angular samples, a two-dimensional grid of at least quadratic
size, or input-dependent off-grid interpolation.  At `N = 65536` these costs
are much larger than the one-dimensional structured alternatives.

A narrower uniform-grid specialization is useful as a grid-faithful control,
but it is itself a direct structured method rather than a radial embedding:

> Use the large-argument Bessel expansion on the high--high block, where every
> exponential is exactly an `N`-point DFT exponential, and evaluate the
> low-row/low-column band directly (or with a local low-rank expansion).

This is not a continuous Hankel transform and does not replace the target grid.
It has no angular quadrature, no Cartesian-to-polar interpolation, and no
NUFFT coordinate conversion.  The prototype passes the small tests below, but
the `N = 65536` acceptance run still needs compensated/reproducible patch
accumulation and the project’s independent multiprecision reference.  Because
the simple one-band version is more expensive in its direct patch than the
competing product-safe dyadic split, this report does **not** promote it as a
radial-method win.

## 1. Exact target and invariants

The repository target is

\[
 y[m] = \sum_{n=0}^{N-1} x[n] A[m,n],\qquad
 A[m,n] = J_0\!\left(\frac{2\pi mn}{N}\right),
 \quad 0\leq m,n<N.
\]

Equivalently, this is a nonuniform-Hankel notation with

\[
 r_n = n/N,\qquad \omega_m = 2\pi m,
 \qquad A[m,n]=J_0(\omega_m r_n).
\]

There are no radial quadrature weights, endpoint half-weights, logarithmic
nodes, or Bessel-root nodes.  In particular, this is not the usual DHT based
on the zeros of `J0`; Townsend’s fast DHT is a useful related reference, but
its root grid is a different operator ([Townsend, 2015](https://arxiv.org/abs/1501.01652),
especially its definition of the root-grid DHT).

The largest Bessel argument is

\[
 z_{\max}=\frac{2\pi(N-1)^2}{N}.
\]

At `N = 65536`, `zmax = 411762.2660165808`, or `zmax/N = 6.2829935610`.
The acceptance gate is normalized `L2 <= 1e-13` and scaled `Linf <= 1e-12`.
All conversion errors therefore belong in the input-dependent transform
budget, not in an unreported setup step.

## 2. Angular plane-wave representation

The radial Fourier identity is valid, but its discrete use has a severe
sampling requirement.  The NIST DLMF gives

\[
 J_0(z)=\frac1{\pi}\int_0^\pi \cos(z\cos\theta)\,d\theta
       =\frac1{2\pi}\int_0^{2\pi}e^{iz\cos\theta}\,d\theta
\]

([DLMF §10.9](https://dlmf.nist.gov/10.9), Eq. 10.9.1).  A `Q`-point periodic
trapezoidal rule consequently gives

\[
 T_Q(z)=\frac1Q\sum_{q=0}^{Q-1}
   \exp\!\left(i z\cos\frac{2\pi q}{Q}\right).
\]

The Jacobi--Anger expansion ([DLMF §10.12](https://dlmf.nist.gov/10.12))
shows the alias mechanism directly:

\[
 e^{iz\cos\theta}=\sum_{\ell\in\mathbb Z}i^\ell J_\ell(z)e^{i\ell\theta},
 \qquad
 T_Q(z)=\sum_{s\in\mathbb Z}i^{sQ}J_{sQ}(z).
\]

Thus the first omitted angular harmonic is around order `Q`, while the target
contains arguments up to `zmax`.  Once `Q > zmax`, a practical tail estimate
is

\[
 |T_Q(z)-J_0(z)|
 \lesssim 2\sum_{s\geq1}|J_{sQ}(z_{\max})|.
\]

The table below evaluates that Bessel-tail estimate at `zmax`.  The `1e-13`
column is an entrywise budget; `1e-16` is a more realistic internal budget
before summing over `N` inputs.  The small-N values were checked by direct
matrix formation.

| `N` | `zmax` | `Q` for `1e-13` | `Q/N` | `Q` for `1e-16` | `Q/N` |
|---:|---:|---:|---:|---:|---:|
| 16 | 88.3573 | 132 | 8.2500 | 139 | 8.6875 |
| 32 | 188.6919 | 244 | 7.6250 | 253 | 7.9063 |
| 64 | 389.6557 | 459 | 7.1719 | 470 | 7.3438 |
| 128 | 791.7304 | 879 | 6.8672 | 893 | 6.9766 |
| 256 | 1595.9536 | 1705 | 6.6602 | 1723 | 6.7305 |
| 1024 | 6421.4215 | 6592 | 6.4375 | 6621 | 6.4658 |
| 65536 | 411762.2660 | 412419 | 6.2930 | 412535 | 6.2948 |

For a complete matvec, a `1e-18` angular budget changes the last value only
slightly (`Q = 412608`, `Q/N = 6.2959`) but is the safer number.  The
asymptotic conclusion is unchanged: angular resolution is approximately
`6.3N`, not a small fixed number of rays.

### Direct numerical falsification

For `x[n] = exp(0.17 i n^2/N) + 0.3 exp(-0.73 i n)`, I formed `T_Q` in
binary64 and compared it with the independent `scipy.special.jv(0,z)` code
path.  The experiment’s `scaled Linf` is
`max(abs(error))/max(1,max(abs(yref)))`.

| `N` | rule | `Q` | max entry error | relative `L2` | scaled `Linf` |
|---:|---|---:|---:|---:|---:|
| 64 | `4N` | 256 | `2.108e-1` | `7.330e-2` | `3.539e-2` |
| 64 | `6N` | 384 | `1.850e-1` | `1.700e-2` | `2.535e-2` |
| 64 | tail budget | 459 | `6.958e-14` | `4.256e-15` | `6.169e-15` |
| 128 | `4N` | 512 | `1.683e-1` | `6.044e-2` | `2.284e-2` |
| 128 | `6N` | 768 | `1.406e-1` | `1.613e-2` | `1.714e-2` |
| 128 | tail budget | 879 | `6.843e-14` | `4.006e-15` | `3.102e-15` |
| 256 | `4N` | 1024 | `1.337e-1` | `5.582e-2` | `1.800e-2` |
| 256 | `6N` | 1536 | `1.166e-1` | `1.523e-2` | `1.325e-2` |
| 256 | tail budget | 1705 | `8.371e-14` | `5.617e-15` | `1.911e-15` |

For fixed `theta_q`, the inner sum is

\[
 g_q[m]=\sum_n x[n]e^{i(2\pi m\cos\theta_q/N)n},
\]

which is a type-3 NUFFT with source span `O(N)`, target-frequency span
`O(1)`, and space-frequency product `p ~= 2*pi*N`.  A NUFFT replaces the
`N^2` inner work by roughly `p log p`, but it must be called `Q` times.  At
`N=65536`:

\[
 Qp\log_2p \approx 3.17\times10^{12}
\]

FFT-sized complex work units, before counting the angular reduction.  A
literal ring embedding has `QN = 27,028,291,584` source points, about
`0.393 TiB` just for complex128 strengths.  This fails the cost gate even
before a 2-D FFT is considered.

## 3. Cartesian FFT, polar FFT, and sparse interpolation

### Cartesian FFT embedding

The geometric interpretation is clean: put a unit-mass circle at radius
`r_n=n/N`; its 2-D Fourier transform at radius `m` is the Bessel factor, so
the weighted sum of circles gives `y[m]`.  The problem is that a finite circle
must be converted to Cartesian data.  The conversion is input-dependent and
needs the `Q` angular samples above for every `n`.

The target frequencies reach `m=N-1` in the convention `exp(2*pi*i*xi*x)`.
The circle support occupies a diameter-two box, so Nyquist requires spatial
spacing approximately `h <= 1/(2N)`, or at least `L0 ~= 4N` Cartesian samples
per axis.  One complex128 array then costs:

| grid | complex128 storage for one array |
|---:|---:|
| `L0 = 4N = 262144` | `1.00 TiB` |
| `2L0 = 8N = 524288` (2x gridding oversampling) | `4.00 TiB` |

Real FFT work arrays, source spreading, and output buffers increase this.
Using fewer Cartesian samples silently aliases the required radial frequencies;
using a small radial array instead of rings is a different operator.

### Polar and projection-slice FFTs

Oppenheim, Frisk, and Martinez use projection-slice ideas to compute
continuous Hankel transforms with one-dimensional FFTs
([JASA 68, 523--529, 1980](https://doi.org/10.1121/1.384765); an author PDF is
[available here](https://dsp-group.mit.edu/wp-content/uploads/2024/11/computation_1980.pdf)).
Those methods are valuable for continuous quadrature problems, but their
radial quadrature and truncation are not the fixed sum above.

The fast polar FFT of Averbuch et al. has `O(N^2 log N)` complexity for an
`N x N` Cartesian image and explicitly uses short-support interpolation;
the authors state that exact results cannot be claimed
([Averbuch et al., 2006](https://doi.org/10.1016/j.acha.2005.11.003)).
The pseudopolar transform has a fast, one-dimensional construction on its own
grid, but it is not an exact analogue of a continuous polar grid
([Averbuch et al., 2008](https://doi.org/10.1137/060650283)).  Neither fact
licenses replacing `r_n=n/N` and `omega_m=2*pi*m` by a log or pseudopolar
grid.

### Interpolation order and oversampling

For a NUFFT-style compact spreading/interpolation kernel, the current
FINUFFT parameter rule is approximately

\[
 w \simeq
 \left\lceil \frac{\log(c_\epsilon/\epsilon)}
 {\pi\sqrt{1-1/\sigma}}+1\right\rceil,
\]

where `sigma` is the fine-grid oversampling factor and the constant is
kernel/type dependent.  This follows the exponential kernel analysis in
[Barnett--Magland--af Klinteberg, 2019](https://arxiv.org/abs/1808.06736)
and [Barnett, 2021](https://arxiv.org/abs/2001.09405); the practical parameter
choice is documented in the [FINUFFT options and accuracy notes](https://finufft.readthedocs.io/en/stable/).
Using the type-3 constant in that rule gives the following useful planning
numbers (width `w`, roughly the number of fine-grid samples in a 1-D stencil):

| internal tolerance | `sigma=1.25` | `sigma=1.5` | `sigma=2.0` |
|---:|---:|---:|---:|
| `1e-13` | 22 | 17 | 14 |
| `1e-16` | 27 | 21 | 17 |
| `1e-18` | 30 | 23 | 20 |

These are not a proof for the complete Bessel matvec.  In 2-D the local
stencil is roughly `w^2`, and both source spreading and output interpolation
are input-dependent.  The [FINUFFT troubleshooting guidance](https://finufft.readthedocs.io/en/stable/trouble.html)
also warns that double-precision NUFFT accuracy around `1e-14` is generally
limited by roundoff and that type-3 sensitivity scales with the
space-frequency product.  Here `p*epsmach ~= 9e-11`, so an off-grid type-3
route should not be expected to satisfy a robust `1e-13` end-to-end gate.

For ordinary local polynomial interpolation there is no universal order
number: the order depends on the exact kernel, oversampling, offset, and
bandlimit.  Full periodic sinc interpolation is exact only when its full
support is retained, which removes the intended sparse speedup.  Therefore
the values above should be treated as NUFFT starting points, not permission
to omit or hide a radial conversion error.

### Chirp-z transform

Bluestein’s identity and the chirp-z algorithm convert a DFT or a circular/
spiral z-transform contour into a convolution
([Bluestein, 1970](https://doi.org/10.1109/TAU.1970.1162132);
[Rabiner, Schafer, and Rader, 1969](https://doi.org/10.1002/j.1538-7305.1969.tb04268.x)).
They do not turn `J0(c mn)` into one DFT.  For the present uniform target,
however, every exponential in the large-argument Bessel expansion is already
exactly `exp(+-2*pi*i*m*n/N)`, so a radix-2 FFT is simpler and cheaper than a
chirp-z transform.  Chirp-z is useful only if a genuinely nonuniform or
non-power-of-two subgrid is requested; then its conversion cost must be
charged.

## 4. Promising uniform-grid asymptotic-FFT embedding

The NIST large-argument expansion is ([DLMF §10.17](https://dlmf.nist.gov/10.17),
Eqs. 10.17.1 and 10.17.3)

\[
 J_0(z) \sim \sqrt{\frac{2}{\pi z}}
 \left[
 \cos(z-\pi/4)\sum_{\ell\ge0}\frac{(-1)^\ell a_{2\ell}(0)}{z^{2\ell}}
 -\sin(z-\pi/4)\sum_{\ell\ge0}\frac{(-1)^\ell a_{2\ell+1}(0)}{z^{2\ell+1}}
 \right],
\]

with

\[
 a_k(0)=\frac{\prod_{j=1}^k[-(2j-1)^2]}{k!8^k},
 \quad a_0=1.
\]

For `z = c mn`, `c=2*pi/N`, every power is separable:

\[
 z^{-p}=c^{-p}m^{-p}n^{-p},
\]

and the oscillatory factors are exact length-`N` DFT factors.  For complex
input, define the positive-exponent transform

\[
 F_p[m]=\sum_{n=b}^{N-1}x[n]n^{-p}e^{+2\pi i mn/N}.
\]

It is one ordinary FFT (up to the library normalization) of the weighted
input.  The negative exponent is not another off-grid transform:
`F_p[-m] = F_p[(-m) mod N]`.  Hence

\[
 C_p[m]=\frac{e^{-i\pi/4}F_p[m]+e^{+i\pi/4}F_p[-m]}2,
\]

\[
 S_p[m]=\frac{e^{-i\pi/4}F_p[m]-e^{+i\pi/4}F_p[-m]}{2i}
\]

are exactly the sums with `cos(cmn-pi/4)` and `sin(cmn-pi/4)` for complex
`x`.  Taking only `Re(F)` or `Im(F)` would be wrong for complex input.

Choose `b` so that the high--high block is in the asymptotic regime:

\[
 c b^2\ge z_c,
 \qquad
 b=\left\lceil\sqrt{z_cN/(2\pi)}\right\rceil.
\]

The two low bands are evaluated directly: all rows `m<b`, and all columns
`n<b` in rows `m>=b`.  Their union has

\[
 P= bN+(N-b)b=2bN-b^2
\]

input-dependent interactions.  This is the complete conversion and transform
for the prototype; the low-band work is not omitted from the cost.

For `M` retained asymptotic pairs, a pointwise remainder budget `delta` can
use the bound

\[
 B_M(z)=\sqrt{\frac2\pi}\left(
 \frac{|a_{2M}(0)|}{z^{2M+1/2}}+
 \frac{|a_{2M+1}(0)|}{z^{2M+3/2}}
 \right),
\]

which is the same first-neglected-term bound used in the recent fully
nonuniform Hankel analysis ([Beckman and O’Neil, 2024/2025](https://arxiv.org/html/2411.09583v1),
Eqs. 3.18--3.20).  At `N=65536`:

| `M` | `delta` | `zc` | `b` | `P` interactions | FFTs/input | optional real patch table |
|---:|---:|---:|---:|---:|---:|---:|
| 4 | `1e-16` | 92.29 | 982 | 127.75 M | 8 | 0.95 GiB |
| 6 | `1e-16` | 35.99 | 613 | 79.97 M | 12 | 0.60 GiB |
| 6 | `1e-18` | 51.83 | 736 | 95.93 M | 12 | 0.72 GiB |
| 8 | `1e-18` | 31.82 | 577 | 75.30 M | 16 | 0.56 GiB |

The optional table stores the real Bessel coefficients for the direct patch;
its bytes are `8P`.  If it is not stored, the same coefficients can be
generated row-by-row, at the cost of Bessel evaluation in the input-dependent
path.  The FFT-only work uses `O(N)` complex storage (a few MiB for the input,
output, and reusable work arrays), not a 2-D array.

### Measured cost at `N=65536`

On the repository platform (Apple M1 Pro, 32 GB), the scratch implementation
measured the following for the deterministic complex input above:

* `M=6`, `delta=1e-16`, `b=613`: 12 FFTs plus weighting/scaling, `0.028 s`;
  on-the-fly direct patch, `1.49 s`.
* `M=6`, `delta=1e-18`, `b=736`: 12 FFTs plus weighting/scaling of the same
  order; on-the-fly direct patch, `1.72 s`.

These are NumPy/SciPy timings, not a production C/Accelerate benchmark.  They
are useful because they include the roughly 80--96 million low-band
interactions that an FFT-only headline would hide.  A reusable patch table
would move Bessel evaluation and most of its storage to setup; its per-input
work remains a `P`-entry matrix-vector application.

### Small complete-transform experiment

The prototype used the exact integer grid, an exact `N`-point FFT for the
high--high block, and direct `J0` evaluation only for the low bands.  The
reference was `scipy.special.jv(0,z)`; `j0` versus `jv` differed by at most
`4.8e-15` at `N=2048` in this check.

| `N` | `M` | `delta` | `b` | relative `L2` | scaled `Linf` |
|---:|---:|---:|---:|---:|---:|
| 256 | 4 | `1e-16` | 62 | `2.520e-15` | `1.738e-15` |
| 512 | 4 | `1e-16` | 87 | `4.381e-15` | `2.883e-15` |
| 1024 | 4 | `1e-16` | 123 | `7.551e-15` | `3.229e-15` |
| 2048 | 4 | `1e-16` | 174 | `1.290e-14` | `6.615e-15` |
| 4096 | 4 | `1e-16` | 246 | `2.228e-14` | `1.316e-14` |

This is a pass against the numerical thresholds at the tested sizes, not a
proof at `N=65536`.  The error grows with transform size, mainly from binary64
summation/FFT arithmetic rather than from the Bessel truncation.  The full
acceptance run should use `delta <= 1e-18`, pairwise or compensated dot
products in the patch, and a multiprecision direct reference.

## 5. Error budget and promotion gate

| route | grid/conversion error | `N=65536` cost | verdict |
|---|---|---:|---|
| angular plane waves + 1-D NUFFTs | requires `Q ~= 6.3N`; type-3 roundoff and angular accumulation | `~3.2e12` FFT-sized units | **fail** |
| Cartesian rings + 2-D FFT | finite-ring quadrature plus Cartesian gridding; `QN` sources | `>=1 TiB` even before normal oversampling | **fail** |
| polar/pseudopolar FFT | radial/grid conversion is interpolatory or changes nodes; 2-D image cost | `O(N^2 log N)` if embedded | **fail** |
| chirp-z on changed grids | exact for its contour, not for the Bessel matrix; conversions remain | no advantage for `N=2^16` | **fail** |
| uniform asymptotic + exact DFT + direct patch | no angular/off-grid conversion; explicit `P` patch | `~1.5--1.8 s` scratch, `0.56--0.72 GiB` optional patch table | **grid-faithful baseline; no promotion** |

The simple one-band candidate plausibly beats dense `O(N^2)` work at this `N`
and is strictly grid-faithful, but it does not yet plausibly beat the
product-safe direct-structured split: at a comparable cutoff that split has
about `3.43 M` direct positive-positive pairs, versus `79.97 M` for the
`M=6, delta=1e-16` one-band patch, before charging its additional FFT blocks.
The natural next optimization is a local Wimp/Chebyshev patch or a
pruned/chirp-z block transform; either belongs to the direct-structured
follow-up and must be benchmarked head-to-head.

**Promotion:** promote none of the radial/projection-slice, Cartesian, polar,
chirp-z, or sparse-interpolation routes.  Retain the uniform asymptotic-FFT
split as a grid-faithful baseline and only promote an optimized version after
the `N=65536` multiprecision/adversarial checks and a direct-structured timing
comparison pass.

## References

1. NIST Digital Library of Mathematical Functions, [Bessel integral representations, §10.9](https://dlmf.nist.gov/10.9), [Jacobi--Anger expansions, §10.12](https://dlmf.nist.gov/10.12), and [large-argument expansions, §10.17](https://dlmf.nist.gov/10.17).
2. A. V. Oppenheim, G. E. Frisk, and D. R. Martinez, “Computation of the Hankel transform using projections,” *JASA* 68 (1980), 523--529, [DOI](https://doi.org/10.1121/1.384765), [author PDF](https://dsp-group.mit.edu/wp-content/uploads/2024/11/computation_1980.pdf).
3. A. Averbuch, R. R. Coifman, D. L. Donoho, M. Elad, and M. Israeli, “Fast and accurate Polar Fourier transform,” *ACHA* 21 (2006), 145--167, [DOI](https://doi.org/10.1016/j.acha.2005.11.003).
4. A. Averbuch, R. R. Coifman, D. L. Donoho, M. Israeli, and Y. Shkolnisky, “A Framework for Discrete Integral Transformations I—The Pseudopolar Fourier Transform,” *SIAM J. Sci. Comput.* (2008), [DOI](https://doi.org/10.1137/060650283).
5. L. Bluestein, “A linear filtering approach to the computation of discrete Fourier transform,” *IEEE Trans. Audio Electroacoustics* 18 (1970), 451--455, [DOI](https://doi.org/10.1109/TAU.1970.1162132).
6. L. R. Rabiner, R. W. Schafer, and C. M. Rader, “The Chirp z-Transform Algorithm and Its Application,” *Bell Syst. Tech. J.* 48 (1969), 1249--1292, [DOI](https://doi.org/10.1002/j.1538-7305.1969.tb04268.x).
7. A. H. Barnett, J. F. Magland, and L. af Klinteberg, “A parallel non-uniform fast Fourier transform library based on an ‘exponential of semicircle’ kernel,” [arXiv:1808.06736](https://arxiv.org/abs/1808.06736); A. H. Barnett, “Aliasing error of the exp kernel in the nonuniform fast Fourier transform,” [arXiv:2001.09405](https://arxiv.org/abs/2001.09405).
8. P. G. Beckman and M. O’Neil, “A Nonuniform Fast Hankel Transform,” [arXiv HTML](https://arxiv.org/html/2411.09583v1), [SIAM DOI](https://doi.org/10.1137/25M1796758).
9. A. Townsend, “A fast analysis-based discrete Hankel transform using asymptotic expansions,” [arXiv:1501.01652](https://arxiv.org/abs/1501.01652).
