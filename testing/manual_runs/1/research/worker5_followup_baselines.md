# Worker 5 follow-up — exact direct-grid baseline audit

Date: 2026-08-28

This is an audit of five published families against the actual operator in this
repository, not against a continuous Hankel integral:

\[
 y_m=\sum_{n=0}^{N-1}x_nJ_0(2\pi mn/N),\qquad 0\leq m,n<N.
\]

The input and output are arbitrary complex binary64 vectors.  The acceptance
gate is normalized L2 <= 1e-13 and scaled Linf <= 1e-12 against an independent
multiprecision reference.  Input-dependent interpolation, spreading, copying,
and conversion are part of apply time; tables, roots, box trees, and other
reusable data are setup time.

## Decision summary

| Family | Native problem | Faithful route to this matrix | Input-dependent conversion | Decision | Potential against current blocked FFT |
|---|---|---|---|---|---|
| FFTLog / log-grid Hankel | Periodic convolution on logarithmic nodes | None without choosing a reconstruction of the linear samples | At least linear-grid -> log-grid and log-grid -> linear-grid resampling; log-periodic aliasing/ringing | Exclude from exact gate; optional exploratory adapter only | No credible lead |
| QDHT / Bessel-zero DHT | Weighted transform on scaled zeros of `J_ν` | None by parameter choice; requires root-grid resampling or a different matrix | Input/output resampling, plus root generation/setup | Exclude from exact gate | No |
| Townsend published algorithms | Root DHT, Fourier–Bessel, and equispaced Schlömilch variants | Yes, by porting the Schlömilch product expansion to `r=m/N`, `ω=2πn`; published `DHT.m` is not the target | None for the exact-grid port | Include as a serious exact-grid candidate; do not use source code verbatim | Yes: geometric masks and exact FFT phases may reduce current block/FFT work |
| Beckman–O'Neil NUFHT | Arbitrary `r_k,ω_j`, with local/asymptotic/direct boxes and Type-III NUFFT | Yes: `r=n`, `ω=2πm/N`, with axes split exactly | None in coordinates, but generic Type-III spreading/deconvolution is apply work | Include as an exact-grid specialization; generic package is a reference, not the final fast path | Yes: Wimp local blocks plus adaptive masks are plausible improvements |
| 2026 convolutional-Gauss-FFT (CGFHT) | Continuous/logarithmically sampled Hankel quadrature | No; it changes both quadrature nodes and operator semantics | Reconstruction onto exponential/Gaussian-shift nodes and output resampling; quadrature/aliasing error | Exclude from exact gate | No |

The strongest leads are therefore not five interchangeable baselines.  They are
two exact-grid algorithmic components:

1. Townsend's equispaced product partition, adapted to the exact phase
   `exp(±2πimn/N)` and ordinary FFTs.
2. Beckman–O'Neil's local Wimp/Chebyshev expansion and adaptive box geometry,
   with exact-grid FFT/pruned-FFT backends replacing generic Type-III NUFFTs.

Both are new exact-grid specializations.  The published root-DHT code and the
generic NUFHT package cannot simply be called on the target and counted as
faithful implementations.

## What counts as faithful

For `m,n>0`, write the target block as

\[
 A_{m,n}=J_0(\alpha mn),\qquad \alpha=2\pi/N.
\]

The axes are exact and should not be approximated:

\[
 y_0=\sum_nx_n,\qquad
 y_m\mathrel{+}=x_0\quad(m>0).
\]

An algorithm is a faithful baseline when its source and target coordinates are
the same integer-indexed product grid and its only approximation is a declared
floating-point/series/low-rank approximation that is tested against the target
matrix.  A continuous transform evaluated by quadrature, or a transform on a
different node set followed by undocumented interpolation, is a different
operator.  For arbitrary complex `x`, smooth-test-function accuracy is not a
substitute for matrix accuracy: impulses, alternating data, and random vectors
must be included.

## 1. FFTLog / logarithmic-grid methods

### Native method and sources

Talman's original paper is [Numerical Fourier and Bessel transforms in
logarithmic variables](https://doi.org/10.1016/0021-9991(78)90107-9).  A
widely used implementation and analysis is Hamilton's [FFTLog
paper](https://arxiv.org/abs/astro-ph/9905191) and [original FFTLog
page](https://jila.colorado.edu/~ajsh/FFTLog/index.html).  The latter links
the original Fortran source and describes the native nodes as periodic
sequences on a logarithmic grid; [pyfftlog](https://github.com/emsig/pyfftlog)
is a usable public implementation.

FFTLog changes variables so that a Hankel transform becomes a convolution in
`log(r)`/`log(k)`.  Its discrete fast operation is a cyclic convolution on
nodes of the form

\[
 r_j=r_0\exp(j\,\Delta),\qquad k_j=k_0\exp(j\,\Delta),
\]

with a Mellin/Gamma multiplier.  It can be highly accurate for that
log-periodic discrete problem.  That statement does not make it exact for a
linearly sampled finite matrix.

### What would be needed for this target

The positive target samples are at `n=1,...,N-1`, not at log-spaced radii.
The zero index also has no finite logarithm.  A target adapter would have to:

1. split out `x[0]` and the `m=0` row exactly;
2. choose a positive log interval, number of log nodes, bias, endpoint
   convention, and interpolation/reconstruction model;
3. reconstruct the arbitrary linear-grid vector `x[1:]` on those log nodes;
4. run FFTLog; and
5. reconstruct the positive linear-grid outputs from FFTLog's log-frequency
   nodes.

The two reconstructions are input-dependent work.  With `Q` log nodes they
cost at least O(N+Q) for local interpolation and can be O(NQ) for a global
reconstruction.  They must be included in apply time.  Enlarging the log
interval, zero-padding, or increasing interpolation order reduces some
log-periodic aliasing and endpoint error, but it does not turn arbitrary
linear samples into exact log samples.  For a vector containing components
near the linear-grid Nyquist scale, interpolation error is not controlled by
the accuracy of the FFTLog kernel.  In particular, no finite interpolation
rule can preserve every arbitrary complex length-`N` vector on both unrelated
node sets without an explicit bandlimit/reconstruction assumption.

The periodic extension inherent in FFTLog adds ringing and aliasing choices.
Those errors are separate from binary64 roundoff and can be large at the
target's first and last positive indices.  Treating `x[0]` as a limiting log
sample is also not valid for the finite sum; its contribution is a known axis
term and should be added separately.

### Decision

**Exclude from the exact acceptance gate.**  FFTLog is a good continuous or
log-grid Hankel baseline, but using it here would benchmark a reconstruction
pipeline rather than the exact direct-grid matrix.  It has no evident route to
beat an exact ordinary-FFT specialization after the required conversions are
charged.

### Fair small-N experiment, if an exploratory number is desired

Use `pyfftlog` or Hamilton's Fortran code without changing its kernel.  For
`N=32,64,...,1024`, sweep a declared log span, `Q/N` in `{1,2,4,8}`, bias,
and linear/cubic/barycentric interpolation.  Use the same deterministic
complex inputs as the exact baselines, add the axes exactly, and compare with
the multiprecision target.  Record separately:

- interpolation and output-conversion time;
- FFTLog setup and apply time;
- log span, `Q`, bias, padding, and interpolation order;
- normalized L2 and scaled Linf errors for random, impulse, alternating, and
  smooth inputs.

This experiment can quantify how far the method is from the gate, but a pass on
smooth inputs must not promote it to an exact baseline.

## 2. QDHT and Bessel-zero transforms

### Native method and sources

The original zero-order paper is Yu et al., [Quasi-discrete Hankel
transform](https://doi.org/10.1364/OL.23.000409).  The integer-order extension
is Guizar-Sicairos and Gutiérrez-Vega, [Computation of quasi-discrete Hankel
transforms of integer order](https://doi.org/10.1364/JOSAA.21.000053).  The
[GSL DHT documentation](https://www.gnu.org/software/gsl/doc/html/dht.html)
also states the defining zero-based sampling convention.  Public reference
implementations include the [CUDA QDHT
repository](https://github.com/cristian-v-achim/quasi-discrete-Hankel-transform)
and [Hankel.jl](https://github.com/chrisbrahms/Hankel.jl).

For order zero, a representative convention chooses positive Bessel zeros
`j_{0,k}` and a scale satisfying `S=RP≈j_{0,N+1}`.  The native nodes are
proportional to those zeros, and the matrix has the form

\[
 J_0\!\left(j_{0,m}j_{0,n}/S\right)
\]

with diagonal factors involving `J_1(j_{0,n})` (and a convention-dependent
overall scale).  Indexing and normalization differ across implementations,
but the root grid and weights do not: it is not the integer grid
`m/N,n/N` with unit input weights.

### Why parameter selection cannot make it the target

There is no scalar `S` for which all scaled Bessel zeros equal the integers.
Changing `R`, `P`, or the endpoint convention only rescales the zero grid; it
does not replace `j_{0,m}j_{0,n}/S` by `2πmn/N`, and the QDHT diagonal weights
do not become one.  Thus a root-DHT call computes a different matrix even if
its asymptotic complexity looks favorable.

A target adapter would need a reconstruction from the arbitrary linear samples
to the QDHT root nodes and a reconstruction from the root-frequency outputs
back to `m=1,...,N-1`.  The minimum work is O(N) for sparse local conversion;
global interpolation is denser.  The interpolation/reconstruction error is
uncontrolled for arbitrary complex input unless a bandlimit and function space
are declared.  Root generation is reusable setup, but the two data conversions
are input-dependent apply work.  The `m=0`/`n=0` terms still need to be split
out exactly.

### Decision

**Exclude from the exact acceptance gate.**  QDHT is a valid baseline for a
different Bessel-zero discretization and can be used to sanity-check root-DHT
code, but it cannot be used as the exact integer-grid baseline by rescaling or
by silently omitting its quadrature weights.

### Fair small-N falsification experiment

For `N=32,64,...,512`, generate the same target input vectors and interpolate
them to the selected QDHT root nodes using a declared order and endpoint rule.
Run a public QDHT implementation, convert the output back to the target
linear-frequency nodes, and compare with the direct multiprecision matrix.
Report the native-root result separately from the target-adapted result.  Sweep
root truncation, interpolation order, and oversampling.  Charge both
conversions in apply time.  A failure on impulses or alternating data is
expected and is evidence for exclusion; a good smooth-function result only
validates the interpolation model, not the target matrix.

## 3. Townsend's published algorithms

### Native methods and source code

Townsend's primary paper is [Fast computation of the Hankel transform using
the discrete Fourier transform](https://arxiv.org/abs/1501.01652), published
as [SIAM J. Sci. Comput. 38 (2016), DOI
10.1137/151003106](https://doi.org/10.1137/151003106).  The author's source is
[FastAsyTransforms](https://github.com/ajt60gaibb/FastAsyTransforms).

The paper treats several sums of the form

\[
 f_k=\sum_n c_nJ_\nu(r_k\omega_n),
\]

including:

- a Schlömilch/equispaced case with `ω_n=nπ` and `r_k=k/N`;
- a Fourier–Bessel case with `ω_n=j_{0,n}`; and
- a DHT with both coordinates tied to Bessel zeros.

The repository's `DHT.m` is the last case: it evaluates a root-grid matrix
with Bessel-root ratios and uses `besselroots`, DCT/DST pieces, and direct
small blocks.  It is not a drop-in implementation of
`J0(2πmn/N)`.  `FastSchlomilchEvaluation.m` and its `QJASYQ` asymptotic helper
are the relevant source for the equispaced mechanism.  The paper's main
ideas are a large-argument Bessel asymptotic expansion, DCT/DST transforms for
the separable oscillatory phases, low-argument direct/Taylor treatment, and a
geometric mask partition.  The paper also notes that direct evaluation is the
appropriate reference at small sizes (roughly `N<=256`).

### Exact-grid adaptation

The target's positive block is a Schlömilch-like product sum after choosing

\[
 r_m=m/N,\qquad \omega_n=2\pi n.
\]

This choice is exact because `r_mω_n=2πmn/N`.  Alternatively one may choose
`r_m=m` and `ω_n=2πn/N`; the first form makes the product-partition geometry
more familiar.  For large products, the Bessel expansion has powers of
`(mn)^{-1/2-ell}` multiplying `cos(2πmn/N-π/4)` and
`sin(2πmn/N-π/4)`.  Every power-weighted phase sum is an ordinary DFT bin:

\[
 \sum_n a_n e^{+2\pi imn/N},
 \qquad
 \sum_n a_n e^{-2\pi imn/N}.
\]

For complex data, the opposite-sign sequence can be obtained from the
opposite bin of the same complex DFT; no real-input shortcut is allowed.

The faithful port therefore needs to:

1. split the two exact axes;
2. partition the positive `(m,n)` rectangle into product-safe direct,
   low-argument, and asymptotic blocks;
3. use direct `J0` on the low-product complement;
4. apply the declared asymptotic order only where its lower product bound is
   valid; and
5. use ordinary FFT/DFT phases for the exact integer grid.

The `nπ` Schlömilch DCT/DST code cannot simply be called with a `2πn` array:
the phase spacing and the transform length change.  The exact-grid ordinary
FFT backend and its block extraction are a small new specialization, not a
parameter setting in the published MATLAB code.  There is no input
interpolation or coordinate conversion in this route.

### Error and cost requirements

For order `M`, use Townsend's first-omitted-term bound (or the equivalent
order-zero bound used in the repository's NUFHT notes) on every asymptotic
block:

\[
 B_M(z)=\sqrt{2/\pi}\left(
 |a_{2M}|z^{-2M-1/2}+|a_{2M+1}|z^{-2M-3/2}\right).
\]

The cutoff must be selected from a row/norm error budget, not only from the
pointwise bound.  FFT roundoff, weighted-input scaling, and block
accumulation must then be measured in binary64.  Townsend reports tolerances
using higher-precision/direct comparisons; that is evidence for parameter
selection, not a proof of this repository's binary64 gate.

This adaptation removes the Neumann addition used for perturbed Bessel-root
grids: the reference grid is the actual grid, so the perturbation is zero.
That is a material advantage over the published root-DHT path.  A simple
dyadic partition still costs approximately O(M N log^2 N) with full FFTs per
scale.  Townsend's geometric masks can reduce the number of masks toward
O(log N/log log N), but the exact benefit depends on pruned/zero-padded FFT
implementation and on how much direct work remains.

### Decision

**Include as an exact-grid candidate, but only as a new port of the
Schlömilch/product machinery.**  Do not label `DHT.m` itself a target
baseline.  This is the clearest route that could beat the current blocked
ordinary-FFT specialization: it has the same exact phases, no root-grid
conversion, no Neumann perturbation series, and a published argument for a
more economical geometric mask layout.  It is not guaranteed to win; FFT
count, scratch traffic, and numerical accumulation decide that.

### Fair small-N benchmark

Implement the port in an isolated benchmark harness, not a shared source file,
with the following rows:

1. dense direct binary64 and independent multiprecision reference;
2. current blocked ordinary-FFT plan;
3. an exact-grid Townsend port with dyadic masks;
4. the same port with Townsend-style geometric masks.

Use `N=32,64,128,256,512,1024,2048,4096` (extend to 8192 if the direct
reference remains practical).  Sweep asymptotic order and cutoff, beginning
with the paper's order/cutoff guidance and tightening until the binary64 gate
passes.  Record setup versus apply, direct interaction count, number and
length of FFTs, temporary bytes, and normalized L2/scaled Linf errors.  Inputs
must include the project deterministic complex vector plus an impulse at each
axis, an interior impulse, all ones, alternating signs, a high-frequency
chirp, random complex data, and a large-dynamic-range vector.  A candidate is
not competitive if it only wins on smooth data or if setup/table generation is
hidden in apply time.

## 4. Beckman–O'Neil NUFHT

### Native method and source code

The primary paper is [Beckman and O'Neil, A fast and accurate algorithm for
the numerical evaluation of the Hankel transform](https://arxiv.org/abs/2411.09583)
([HTML version](https://arxiv.org/html/2411.09583v1)); the published SIAM
version is [DOI 10.1137/25M1796758](https://doi.org/10.1137/25M1796758).  The
authors' implementation is [FastHankelTransform.jl](https://github.com/pbeckman/FastHankelTransform.jl).

The NUFHT evaluates

\[
 g_j=\sum_k c_kJ_\nu(\omega_jr_k)
\]

for arbitrary nonnegative, sorted `r_k` and `ω_j`; it does not require
quadrature weights.  It recursively boxes the product plane and chooses:

- a local Wimp/Chebyshev low-rank expansion for small arguments;
- a Hankel asymptotic expansion for large arguments, implemented by repeated
  Type-III NUFFTs; and
- direct summation for small mixed boxes.

The paper gives the same kind of first-omitted-term asymptotic bound as above
and a complexity with a Type-III grid-size term, schematically

\[
 O((L+M)(m+n)\log\min(m,n)+M p\log p),
\]

where `L` is local expansion rank, `M` is asymptotic order, and `p` depends on
the product of coordinate spans.  The source's `nufht.jl` makes the structure
concrete: it has `add_loc!`, `add_asy!`, and `add_dir!`, calls two Type-III
NUFFTs per asymptotic order term, and uses precomputed tables.  The published
package allocates a real `Float64` output buffer, so its API is not directly a
complex-valued implementation of this task; running real and imaginary parts
separately or changing the buffers is required.

### Exact-grid path

Use the positive indices only and set either

\[
 r_n=n,\qquad \omega_m=2\pi m/N,
\]

or the equivalent scaled pair `r_n=n/N`, `ω_m=2πm`.  Then
`ω_mr_n=2πmn/N` exactly.  Split `n=0` and `m=0` as described at the top of
this report.  No source/output interpolation is needed, and arbitrary complex
coefficients are allowed once the output buffers and accumulation are made
complex.

Calling the generic package this way is faithful in coordinates, but it is
not automatically a good exact-grid implementation.  Its Type-III NUFFT
contains input-dependent spreading, fine-grid FFT, deconvolution, and local
interpolation.  That work belongs in apply time.  For the target, the span
parameter is approximately

\[
 p\approx (N-1)\,2\pi(N-1)/N\approx 2\pi N,
\]

so the theorem's O(N log N) form hides a substantial fine-grid constant.  On
the exact grid, each asymptotic phase is an ordinary FFT phase.  A specialized
implementation should therefore retain NUFHT's box classification and local
expansion but replace Type-III calls with ordinary FFTs, zero-padded/pruned
FFTs, or a chirp-z variant appropriate to each contiguous block.  This removes
off-grid spreading error and can reduce both work and memory.

The local expansion is particularly interesting for this repository.  It can
replace many low-product direct interactions, while the adaptive box tree can
avoid applying a full-length FFT to every coarse dyadic band.  The local rank,
asymptotic order, cutoff, and direct-block threshold must be tuned against the
same error gate.  The source's available tolerance range and its direct-test
comparisons are useful starting evidence, not a binary64 guarantee for this
matrix.

### Decision

**Include as an exact-grid specialization candidate.**  The generic Julia
package is a useful independent reference and a way to validate the box
partition, but it should be benchmarked separately from an exact-grid FFT
port.  The plausible winning component is the combination of Wimp local
blocks, adaptive product masks, and exact ordinary FFT phases.  The generic
Type-III path alone is unlikely to beat a tuned ordinary-FFT specialization at
this grid size because it pays spreading/deconvolution overhead for a phase
grid that is already FFT-compatible.

### Fair small-N benchmark

Use an isolated adapter with `r=n`, `ω=2πm/N`, exact axes, and complex data.
Benchmark these variants:

1. dense direct binary64 and multiprecision reference;
2. the current blocked ordinary-FFT plan;
3. the published generic NUFHT package, run on real and imaginary parts (if
   its Julia/FINUFFT dependencies are available);
4. a NUFHT box partition with exact-grid FFT backends.

Sweep `min_dim_prod`, local rank `L`, asymptotic order `M`, and the direct
threshold.  Use the same `N` sequence and input set as the Townsend experiment.
Report box generation/table setup separately from apply, and in apply report
Type-III spread points or exact FFT sizes, direct interactions, and all
temporary memory.  Require the two error metrics for both real and imaginary
components and for the complex norm.  This experiment directly answers
whether local expansion reduces the current implementation's direct patch
enough to offset its extra box and FFT machinery.

## 5. 2026 convolutional-Gauss-FFT (CGFHT)

### Native method and source evidence

The primary article is Tian and Li, [An efficient discrete Hankel transform
based on convolutional Gaussian fast Fourier transform](https://link.springer.com/article/10.1186/s40623-026-02436-5),
DOI [10.1186/s40623-026-02436-5](https://doi.org/10.1186/s40623-026-02436-5).
The method starts from a continuous Hankel integral, changes both variables to
logarithmic/exponential coordinates, forms a Toeplitz convolution kernel, and
uses Gaussian quadrature over shifted log grids.  Its work is roughly
O(M\,\widehat N\log\widehat N), with multiple FFTs and shifted/Gaussian
samples; segmented sampling is used to control coarsening and aliasing at
large offsets.  The paper's experiments are continuous geophysical/CSEM
integrals, not arbitrary coefficient vectors for a finite Bessel matrix.

The paper itself identifies exponential-grid sampling as a limitation and
points to future work on high-precision transforms using uniform grids.  I
found no public implementation link in the article; its data/code availability
statement says materials are available from the corresponding authors on
reasonable request.

### Why it does not implement this matrix

The target's `x[n]` are coefficients at the fixed linear frequencies
`2πn/N`.  CGFHT's natural samples are values of a reconstructed continuous
integrand at exponentially spaced frequencies and Gaussian shifts.  The
quadrature weights and Toeplitz kernel therefore represent a different
operator.  If the target vector is converted to CGFHT nodes, the adapter must:

1. choose a continuous reconstruction of the arbitrary linear samples,
   including behavior at zero and the truncated endpoints;
2. evaluate that reconstruction on each exponential/Gaussian-shift grid;
3. run the segmented CGFHT quadrature; and
4. resample its exponential output back to the target linear `m` nodes.

The input reconstruction and output resampling are input-dependent.  Depending
on whether the reconstruction is local or global, the sampling cost is at
least O(N) and can be O(MN), in addition to the Gaussian quadrature and
segmentation work.  Its finite-interval, coarsening, and aliasing errors are
not the target matrix error and are especially problematic for impulses and
alternating vectors.  If one instead forces the CGFHT nodes to be
`2πn/N` and `m`, the log convolution and its Toeplitz structure disappear;
that is no longer the published algorithm.

### Decision

**Exclude from the exact acceptance gate and from the serious performance
shortlist.**  CGFHT may be useful for its intended continuous/log-grid
integrals, but a target adapter would benchmark interpolation plus a different
quadrature operator.  There is no evidence that it can beat an exact-grid FFT
method after those costs and errors are charged.

### Optional falsification experiment

If a numerical illustration is needed, choose a fixed exponential span,
Gaussian order `M`, number of segments, and cubic/barycentric reconstruction.
For `N=32,...,512`, run the full linear -> CGFHT -> linear pipeline and compare
against the direct multiprecision target on impulses, alternating data, and
smooth analytic samples.  Publish the reconstruction and segmentation
parameters with every result.  Do not promote it based on the smooth case;
promotion would require a stated reconstruction model that passes arbitrary
complex vectors at the repository gate.

## Fair benchmark protocol for the two candidates

The following protocol keeps the comparison honest and can be reused for both
the Townsend port and the exact-grid NUFHT hybrid:

1. **Reference.** Use dense direct evaluation for small `N` and an independent
   multiprecision implementation for the reported gate.  Do not use the same
   asymptotic series or FFT path as both candidate and reference.
2. **Sizes.** Use powers of two `32` through `4096`; add `8192` only when the
   reference and memory budget remain reasonable.  Include a separate
   `N=65536` timing run once a candidate has passed accuracy at smaller sizes.
3. **Inputs.** Use the project's deterministic complex input and, at minimum,
   complex random, all ones, alternating signs, impulses at `0`, `1`, and
   `N-1`, an interior impulse, a high-frequency chirp, and a vector spanning
   several binary64 decades.
4. **Timing.** Warm up; report a median of repeated applies.  Time only
   input-dependent weighting/copying, FFT/NUFFT calls, direct work, and output
   accumulation.  Report reusable roots, coefficient tables, box trees, FFT
   plans, and scratch allocation separately.
5. **Numerics.** Report normalized L2 and scaled Linf for the complete complex
   output, plus the worst input.  Record asymptotic order, local rank, cutoff,
   block policy, FFT lengths, direct interactions, and any compensation or
   scaling.  A method that needs input-dependent interpolation must report
   interpolation error and time as first-class results.
6. **Promotion rule.** Promote only an exact-coordinate method that passes
   both error thresholds on every adversarial class and has a measured apply
   speed/memory advantage over the current plan at a relevant size.  A method
   that is fast only after omitting conversion, setup, axes, or output
   resampling is not a fair baseline.

## Final inclusion/exclusion result

- **Do not implement as shared baselines:** FFTLog, QDHT, or CGFHT.  Their
  native grids/weights and the target's unit-weight integer grid are different;
  a conversion pipeline is both input-dependent and an additional source of
  error.
- **Prototype privately first:** a Townsend Section-4-style exact-grid port,
  using the target's ordinary FFT phases and product-safe geometric masks.
- **Prototype alongside it:** a Beckman–O'Neil box partition with Wimp local
  expansion and exact-grid FFT backends.  Benchmark the generic Type-III
  implementation only as a separate arbitrary-node reference.
- **Most plausible way to beat the current blocked ordinary-FFT
  specialization:** combine Townsend's lower-mask-count geometry with the
  exact phase/FFT path, and/or use NUFHT's local expansion to shrink the direct
  low-product region.  Neither published root-DHT code nor a log-grid/CGFHT
  conversion is a credible winner for the exact matrix.

## Source index

- [Talman 1978, original FFTLog/log-variable method](https://doi.org/10.1016/0021-9991(78)90107-9)
- [Hamilton 2000 FFTLog paper](https://arxiv.org/abs/astro-ph/9905191) and [original source page](https://jila.colorado.edu/~ajsh/FFTLog/index.html)
- [Yu et al. 1998 QDHT](https://doi.org/10.1364/OL.23.000409)
- [Guizar-Sicairos and Gutiérrez-Vega 2004 integer-order QDHT](https://doi.org/10.1364/JOSAA.21.000053)
- [Townsend 2016 paper](https://doi.org/10.1137/151003106) and [FastAsyTransforms source](https://github.com/ajt60gaibb/FastAsyTransforms)
- [Beckman–O'Neil 2026 paper](https://doi.org/10.1137/25M1796758) and [FastHankelTransform.jl source](https://github.com/pbeckman/FastHankelTransform.jl)
- [Tian–Li 2026 CGFHT article](https://doi.org/10.1186/s40623-026-02436-5)
