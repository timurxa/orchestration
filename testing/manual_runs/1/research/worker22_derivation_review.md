# Worker 22 — independent derivation review

Date: 2026-08-28

## Status

**PASS for the requested mathematics in `src/dht_asym.c`: no sign,
normalization, endpoint, or exact-arithmetic partition defect was found.**
The implementation is a product-safe blocked asymptotic approximation, not an
accuracy certification for every binary64 complex vector at `N=65536`.

This review checked `src/dht_asym.c` against the derivations in
`research/worker1_asymptotic.md`, `worker3_identities.md`,
`worker4_radial_fft.md`, `worker6_partition.md`, `worker6_stability.md`,
`worker11_split.md`, `worker12_audit.md`, and the independent residual-sign
reports `worker3_followup_adversarial.md` and `worker10_k12_validation.md`.
No additional long experiment was run for this bounded assignment.

## 1. Order-0 Bessel expansion and code coefficients

Let

\[
    \alpha=\frac{2\pi}{N},\qquad z=\alpha mn,
    \qquad \vartheta=z-\frac{\pi}{4}.
\]

For positive real `z`, the order-0 Hankel expansion is

\[
 J_0(z)\sim \sqrt{\frac{2}{\pi z}}
 \left\{
 \cos\vartheta\sum_{r\ge0}\frac{(-1)^r a_{2r}(0)}{z^{2r}}
 -\sin\vartheta\sum_{r\ge0}\frac{(-1)^r a_{2r+1}(0)}{z^{2r+1}}
 \right\},
\]

where

\[
 a_q(0)=\frac{\prod_{j=1}^{q}[-(2j-1)^2]}{q!\,8^q}.
\]

Equivalently, with the positive numbers

\[
 c_q=\frac{((2q-1)!!)^2}{q!\,8^q},\quad c_0=1,
 \qquad c_{q+1}=c_q\frac{(2q+1)^2}{8(q+1)},
\]

the coefficient of the `q`th separated term is

\[
 b_{2r}=(-1)^r c_{2r},\qquad
 b_{2r+1}=(-1)^r c_{2r+1},
\]

with `cos(vartheta)` for even `q` and `sin(vartheta)` for odd `q`.
The first terms are

\[
 \sqrt{\frac{2}{\pi z}}
 \left[\cos\vartheta+\frac{\sin\vartheta}{8z}
 -\frac{9\cos\vartheta}{128z^2}
 -\frac{225\sin\vartheta}{3072z^3}+\cdots\right].
\]

`asym_coeff(q)` at `src/dht_asym.c:60-70` returns exactly `b_q`; its signed
product is `a_q(0)`, and its parity branches supply the extra even/odd Hankel
signs. Thus the code's signs agree with the standard expansion. In the source,
`terms=K` means the retained orders are `q=0,...,K-1`; the first omitted
orders are `K` and `K+1`. Reports that use `K` to mean the largest retained
order (`q=0,...,K`) must not be mixed with this source convention.

For one output band and one retained order, set `p=q+1/2` and

\[
 u_q[n]=x[n]n^{-p}{\bf1}_{n\in I_n},\qquad
 F_q^+(m)=\sum_n u_q[n]e^{+i\alpha mn}.
\]

Then

\[
 z^{-p}=\alpha^{-p}m^{-p}n^{-p},
\]

so the corresponding contribution is

\[
 \sqrt{\frac2\pi}\,b_q\,\alpha^{-p}m^{-p}
 \sum_n x[n]n^{-p}T_q(\alpha mn-\pi/4),
\]

where `T_q` is cosine for even `q` and sine for odd `q`. The source tables at
`src/dht_asym.c:132-165` implement the `n^{-p}` and
`sqrt(2/pi)*b_q*alpha^{-p}*m^{-p}` factors separately, with zero entries for
the invalid `n=0` and `m=0` inverse powers.

## 2. One complex backward FFT plus its partner bin

FFTW's `FFTW_BACKWARD` transform is the unnormalized positive-exponent sum:

\[
 F_q^+(m)=\sum_{n=0}^{N-1}u_q[n]e^{+2\pi i mn/N}.
\]

There is no conjugation assumption here. Even for complex `x`, integer-grid
periodicity gives

\[
 F_q^-(m):=\sum_nu_q[n]e^{-2\pi i mn/N}
       =F_q^+((N-m)\bmod N).
\]

For `m=1,...,N-1`, this is exactly the `partner=N-m` read at
`src/dht_asym.c:340-347`. Therefore one complex inverse FFT per order and
per active output band supplies both phase signs.

The phase-shifted projections are

\[
 C_q(m)=\frac{e^{-i\pi/4}F_q^+(m)+e^{+i\pi/4}F_q^-(m)}2,
\]

\[
 S_q(m)=\frac{e^{-i\pi/4}F_q^+(m)-e^{+i\pi/4}F_q^-(m)}{2i}.
\]

The source forms the unshifted projections first. Writing
`F^+=a_r+ia_i` and `F^-=b_r+ib_i`, it computes

\[
 C_0=\frac{F^++F^-}{2},\qquad
 S_0=\frac{F^+-F^-}{2i},
\]

with

\[
 \Re S_0=\frac{a_i-b_i}{2},\qquad
 \Im S_0=-\frac{a_r-b_r}{2}.
\]

Hence the code's lines 348-351 are correct. Since

\[
 \cos(t-\pi/4)=\frac{\cos t+\sin t}{\sqrt2},\qquad
 \sin(t-\pi/4)=\frac{\sin t-\cos t}{\sqrt2},
\]

the lines 353-359 correctly use

\[
 q\text{ even}:\ H_q=(C_0+S_0)/\sqrt2,
 \qquad
 q\text{ odd}:\ H_q=(S_0-C_0)/\sqrt2.
\]

The order contribution then is the stored scale times `H_q`, exactly as at
lines 360-362. A second FFT for the negative phase is unnecessary.

## 3. FFTW normalization

The target operator has an unnormalized sum over `n`; it has no factor `1/N`.
FFTW does not normalize either forward or backward transforms. Consequently
the absence of an extra `N` or `1/N` in the source is correct. The only scale
needed after the FFT is the Bessel factor

\[
 \sqrt{\frac2\pi}\,b_q\,\alpha^{-(q+1/2)}m^{-(q+1/2)},
\]

which is precomputed at lines 157-163. A library that normalized its inverse
FFT would require multiplication by `N`; FFTW's backward plan at lines 211-213
does not.

## 4. Ratio-4 mask and direct/asymptotic partition

Let

\[
 T=\frac{z_0N}{2\pi}=\frac{z_0}{\alpha}.
\]

For ratio 4, the output bands are

\[
 I_b=[b,4b)\cap\{1,\ldots,N-1\},
 \qquad b=1,4,16,\ldots,
\]

with a final truncated band if necessary. For each band the source sets

\[
 n_0=\min\!\left(N,\left\lceil\frac{T}{b}\right\rceil\right).
\]

For every `m in I_b` and `n >= n0`,

\[
 \alpha mn\ge \alpha b n_0\ge z_0.
\]

Thus the asymptotic formula is evaluated only on a product-safe rectangle.
The source implements this at `add_asym_block` lines 326-338. The prefix
`1 <= n < n0` is evaluated directly from `J0` and stored in the row's direct
kernel (`build_direct_region`, lines 85-129; `add_direct_rows`, lines
265-285). The direct prefix plus the asymptotic suffix partitions every
positive-positive entry in that output band exactly once; entries that are
already above the cutoff but lie in the conservative direct prefix are simply
evaluated exactly.

The ratio-4 choice changes grouping and work; it does not change the scalar
remainder bound on any entry that reaches the asymptotic path. It is a
rectangular conservative mask, not the exact hyperbolic mask `mn >= T`.

There is one proof-hardening note: the source computes `T` and `ceil(T/b)` in
binary64. The real-arithmetic inequality above is exact, but a formal boundary
guarantee should compute or guard the integer cutoff so that rounding cannot
select `n0` one below an exact integer boundary; equivalently, verify
`alpha*b*n0 >= z0` and increment `n0` if needed. No such boundary failure was
reproduced in the reviewed evidence, so this is a robustness recommendation,
not a found defect.

## 5. Endpoint rows and bins

The inverse powers are not used on the axes:

* `n=0`: `J0(0)=1`, and the initial assignment adds `x[0]` to every output.
* `m=0`: `J0(0)=1` for every column, and `add_zero_row` replaces row zero by
  the compensated sum of all `x[n]`.
* `m=N/2` when `N` is even: `partner=N-m=m`; the FFT bin is self-partnering,
  `S_0=0` algebraically, and the code's subtraction uses the same stored bin.
* `m>N/2`: `partner=N-m` is the correct positive-frequency partner; no sign
  change is needed because the formula uses the bin value itself, not a real
  input conjugate symmetry.

The exact axis handling is at `src/dht_asym.c:369-377`; the band loop only
passes `m=1,...,N-1` to the asymptotic path.

## Corrections to research wording

1. `worker6_stability.md` says that complex input requires two independent
   signed FFTs and predicts `2*(K+1)` FFTs. That is false for this exact
   integer grid and this partner-bin implementation. The correct count is one
   backward FFT per retained order per active output band; the `N-m` bin gives
   the opposite sign even for complex input.
2. The same report's `K=12` convention retains orders `0,...,12`, whereas the
   production API's `terms=12` retains `0,...,11`. State the convention before
   quoting omitted-term bounds or FFT counts.
3. Any statement such as “2M FFTs” must say whether `M` counts even/odd order
   pairs or individual retained orders. It must not count the two phase signs
   as two FFTs. For the current source, `terms=12` and seven active ratio-4
   bands imply 84 length-`N` complex FFT executions, not 168.
4. The reports' scalar asymptotic checks do not certify the complete binary64
   matvec. In particular, the residual-sign reports show that some lower-cutoff
   profiles fail the normalized-L2 gate, while the archive audit notes that
   non-delta large-`N` checks are selected-row checks. These are accuracy-status
   limitations, not defects in the separation identities reviewed here.

## Safe statements for the final report

* The exact grid phase `2*pi*m*n/N` makes each separated asymptotic term an
  ordinary length-`N` DFT of a power-weighted input.
* With FFTW's unnormalized `FFTW_BACKWARD` transform, one complex FFT per
  retained order and active row band is sufficient; bin `N-m` supplies the
  negative phase, including for complex input.
* The code's even-order reconstruction is `(C+S)/sqrt(2)` and its odd-order
  reconstruction is `(S-C)/sqrt(2)`, corresponding to the phase
  `z-pi/4`; the signs and Bessel prefactors are correct.
* Ratio-4 bands use the lower output endpoint to choose a conservative input
  suffix. Every asymptotic entry satisfies `z >= z0`; the remaining positive
  entries and both zero axes are evaluated directly/exactly.
* The derivation and partition pass mathematical review, but this alone is
  not an arbitrary-vector `N=65536` accuracy certificate. Quote the independent
  MPFR coverage and residual-sign results separately, and do not claim a
  certified finalist unless the frozen-source full gate has actually been run.

## Recommendation

**Sign off the derivation and retain the implementation structure.** Correct
the FFT-count/order-convention wording in the research narrative, and, before
making a formal cutoff proof, harden the floating-point boundary test for
`n0`. Keep the final performance/accuracy conclusion conditional on the
existing MPFR evidence; the mathematics reviewed here does not by itself
justify a production accuracy certification.
