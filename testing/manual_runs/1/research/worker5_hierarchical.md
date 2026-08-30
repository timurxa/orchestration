# Worker 5 — hierarchical / FMM / local–far structure

**Kernel.** I assume \(m,n\in\{0,\ldots,N-1\}\), \(N=65536\), and

\[
 K_{mn}=J_0(\alpha mn),\qquad \alpha=\frac{2\pi}{N}.
\]

The zero row and column are identically one and should be handled separately. The
accuracy discussion below uses a conservative absolute matvec interpretation:

\[
 \| (K-\widetilde K)x\|_\infty\le 10^{-13}
 \quad\text{for}\quad \|x\|_\infty\le 1.
\]

If the project instead measures relative 2-norm error, the arithmetic conclusion is
less negative, but that case was not established here.

## Verdict

**Do not promote a conventional FMM, \(\mathcal H\), \(\mathcal H^2\), HSS, or HODLR
implementation.** Equal-level off-diagonal blocks do not have bounded rank; the
rank grows with the bilinear phase, and the largest standard HODLR sibling blocks
are numerically full rank.

There is a viable *different* asymptotic idea: evaluate \(mn/N\) below a cutoff
directly, and use a product-adapted complementary low-rank/butterfly scheme for
the two far-field waves. At \(z=\alpha mn\ge 20\), 24 asymptotic coefficients are
enough for a conservative row-sum truncation below \(10^{-13}\). However, the
hyperbolic mask \(1_{mn\ge T}\) prevents this from being only 24 ordinary FFTs;
the generic butterfly rank/channel budget is large, and binary64 accumulation has
not demonstrated \(10^{-13}\) worst-case error. This is a research lead, not a
winning hierarchical path.

## 1. Local/small-argument expansion

The DLMF power series for \(J_\nu\) gives, at order zero,

\[
 J_0(z)=\sum_{k=0}^{\infty}\frac{(-1)^k(z^2/4)^k}{(k!)^2}
 \tag{1}
\]

([DLMF 10.2.2](https://dlmf.nist.gov/10.2.E2)). Substituting \(z=\alpha mn\),

\[
 K_{mn}=\sum_{k=0}^{\infty}
 \frac{(-1)^k(\pi/N)^{2k}}{(k!)^2}
 (m^{2k})(n^{2k}).
 \tag{2}
\]

Thus the first \(R\) terms are a rank-\(R\) matrix. If \(z\le z_{\max}\), put
\[
 t_R=\frac{(z_{\max}^2/4)^R}{(R!)^2},\qquad
 q_R=\frac{z_{\max}^2}{4(R+1)^2}.
\]
When \(q_R<1\) and the terms are decreasing, the entrywise tail is bounded by
\(t_R/(1-q_R)\). This is useful for rectangles whose maximum product is small,
but it becomes numerically ill-conditioned if used deep into the oscillatory
regime.

The exact Bessel addition theorem is also not a general cure. Neumann's theorem
([DLMF 10.23.2](https://dlmf.nist.gov/10.23.E2)) gives, for integer order,

\[
 J_0(z_0+\delta)=\sum_{k=-\infty}^{\infty}J_{-k}(z_0)J_k(\delta).
 \tag{3}
\]

For a box centered at \((m_c,n_c)\), however,
\[
 \delta=\alpha(n_c u+m_c v+uv),
 \qquad u=m-m_c,\;v=n-n_c.
\]
The mixed \(uv\) term and the potentially large center-linear terms mean that
(3) is not itself a separated matrix expansion. The origin series (2), or a
centered Taylor/interpolation expansion in a genuinely small box, is the useful
local mechanism.

### Small-block experiment

For \(N=65536\), a binary64 evaluation of the truncated series on the origin block
\([0,s)^2\) gave:

| \(s\) | \(z_{\max}=\alpha(s-1)^2\) | terms for observed max entry error \(\le10^{-13}\) | observed error |
|---:|---:|---:|---:|
| 32  | 0.092 | 4  | \(3.5\times10^{-14}\) |
| 64  | 0.381 | 6  | \(4.1\times10^{-15}\) |
| 128 | 1.546 | 9  | \(7.3\times10^{-14}\) |
| 192 | 3.498 | 13 | \(5.2\times10^{-14}\) |
| 256 | 6.234 | 18 | \(1.2\times10^{-14}\) |

At \(z_{\max}\approx6\), about 19 terms are required by the simple \(10^{-15}\)
tail bound. This is acceptable locally, but it is not a global low-rank
representation: the product reaches \(z_{\max}\approx2\pi N\) at the far corner.

## 2. Far-field asymptotics and the oscillatory transition

For positive large \(z\), DLMF 10.17.3 gives

\[
 J_0(z)\sim \sqrt{\frac{2}{\pi z}}
 \left[
 \cos\phi\sum_{k\ge0}\frac{(-1)^k a_{2k}(0)}{z^{2k}}
 -\sin\phi\sum_{k\ge0}\frac{(-1)^k a_{2k+1}(0)}{z^{2k+1}}
 \right],
 \quad \phi=z-\frac\pi4,
 \tag{4}
\]

where
\[
 a_0(0)=1,\qquad
 a_k(0)=\prod_{j=1}^k\frac{-(2j-1)^2}{8j}.
\]
The real-positive error statement in [DLMF 10.17(iii)](https://dlmf.nist.gov/10.17.iii)
says each remainder is no larger than its first omitted term once the stated
termination condition is met. A conservative entrywise estimate for a \(P\)-term
truncation is therefore

\[
 E_P(z)\lesssim 2\sqrt{\frac{2}{\pi z}}\frac{|a_P(0)|}{z^P}.
 \tag{5}
\]

The expansion is asymptotic, not convergent: increasing \(P\) past its optimal
point eventually makes the error worse.

Scalar binary64 checks against scipy.special.j0 over a geometric grid up to
\(10^5\) produced these maximum absolute errors:

| \(z_{\min}\) | \(P=12\) | \(P=16\) | \(P=24\) |
|---:|---:|---:|---:|
| 12 | \(1.9\times10^{-11}\) | \(2.2\times10^{-12}\) | \(5.2\times10^{-13}\) |
| 16 | \(1.4\times10^{-12}\) | \(3.6\times10^{-14}\) | \(5.3\times10^{-16}\) |
| 20 | \(1.3\times10^{-13}\) | \(1.6\times10^{-15}\) | \(8.3\times10^{-17}\) |

Consequently, \(z\in[8,20]\) is a real transition regime for a \(10^{-13}\)
implementation. It should be handled by direct j0, a tested minimax table, or
an appropriately bounded local expansion; the leading asymptotic wave is not enough.

For \(z_F=20\), \(P=24\), summing the first-omitted-term bound over each row of
the far set gives approximately \(1.15\times10^{-14}\) before the factor-two
conservatism in (5), or roughly \(2.3\times10^{-14}\) with it. Thus the
truncation itself can fit a \(10^{-13}\) row budget, but leaves little room for
floating-point application error.

The number of positive-index entries below the cutoff is
\[
 \#\{(m,n):mn<z_FN/(2\pi)\}
 =\sum_{n=1}^{N-1}\min\left(N-1,\left\lfloor\frac{z_FN}{2\pi n}\right\rfloor\right).
 \tag{6}
\]
For \(N=65536\), this is 2,215,574 entries at \(z_F=20\), only \(33.81N\).
Directly applying this near/transition part is therefore practical.

## 3. Product-adapted far rank

The oscillatory part has a particularly simple local factorization. With
\(m=m_c+u\), \(n=n_c+v\),

\[
 e^{\pm i\alpha mn}
 =e^{\pm i\alpha(n_cm+m_cn-m_cn_c)}e^{\pm i\alpha uv}.
 \tag{7}
\]

The first factor is row times column. On a box with half-widths \(h_m,h_n\),

\[
 e^{\pm i\alpha uv}
 =\sum_{\ell=0}^{r-1}\frac{(\pm i\alpha)^\ell}{\ell!}u^\ell v^\ell+R_r,
 \qquad
 |R_r|\le e^\eta\frac{\eta^r}{r!},
 \quad \eta=\alpha h_mh_n.
 \tag{8}
\]

This gives the practical admissibility condition
\[
 \alpha\,\Delta m\,\Delta n\lesssim 4\eta_0.
 \tag{9}
\]
It is complementary rather than ordinary H-matrix admissibility: one box must
shrink as the other grows. For example, if \(\Delta m\Delta n\le N\), then
\(\eta\le\pi/2\), and the conservative Taylor bound needs \(r=22\) for
\(10^{-15}\) residual and \(r=24\) for \(10^{-18}\) residual.

Each far asymptotic coefficient is a separable power
\(m^{-k-1/2}n^{-k-1/2}\) times one of the two waves in (7). A plain low-rank block
bound is therefore

\[
 r_{\rm block}\lesssim 2P\,r_{\rm phase}.
 \tag{10}
\]

At \(z_F=20\), \(P=24\), and \(r_{\rm phase}=24\), this is about 1,152. It is
an intentionally conservative bound, but it shows why ordinary \(\mathcal H^2\)
coupling matrices are unattractive here. The appropriate literature is the
complementary-low-rank/butterfly family, not a standard same-level H2 tree:
[Engquist–Ying, 2008](https://doi.org/10.1137/07068583X) and
[Candès–Demanet–Ying, 2009](https://doi.org/10.1137/080734339).

## 4. Rank experiment: conventional versus complementary blocks

The experiment formed
\(A_{ij}=\operatorname{j0}(2\pi i j/N)\) in binary64 and reported
\(r_{13}=\#\{\sigma_j>10^{-13}\sigma_1\}\).

### Standard HODLR sibling blocks

For the top block \([0,s)\times[s,2s)\), \(s=N/2\), the numerical rank was full:

| \(N\) | \(s\) | \(r_{13}\) |
|---:|---:|---:|
| 256  | 128  | 128 |
| 512  | 256  | 256 |
| 1024 | 512  | 512 |
| 2048 | 1024 | 1024 |

This directly rules out a rank-bounded conventional HODLR/HSS hierarchy. It is
consistent with the fact that the phase \(\alpha mn\) has constant mixed derivative
\(\partial_m\partial_n(\alpha mn)=\alpha\), rather than a coupling that decays
when separated boxes move apart.

### \(N=65536\) raw Bessel blocks

For \(I=J=[N/2,N/2+s)\):

| \(s\) | \(r_{13}\) for raw \(J_0(\alpha mn)\) |
|---:|---:|
| 64  | 54 |
| 128 | 77 |
| 256 | 175 |
| 512 | 426 |

By contrast, the pure dephased residual \(E_{uv}=e^{i\alpha uv}\) on a centered
square has much smaller rank:

| \(s\) | \(\alpha s^2\) | \(r_{13}(E)\) |
|---:|---:|---:|
| 64   | 0.393 | 7 |
| 128  | 1.571 | 9 |
| 256  | 6.283 | 12 |
| 512  | 25.13 | 20 |
| 1024 | 100.5 | 38 |

This is the decisive positive evidence for a complementary butterfly and the
decisive negative evidence for ordinary H/H2/HSS/HODLR. The raw Bessel ranks are
larger because both waves and multiple asymptotic amplitude powers are present.

## 5. Cost and binary64 assessment at \(N=65536\)

Baseline facts:

- \(N^2=4,294,967,296\) entries; a stored real matrix takes 34.4 GB before
  workspace, and a direct on-the-fly matvec needs about \(4.3\times10^9\) kernel
  evaluations.
- The measured 2,215,574-entry near/transition j0 pass took 30.8 ms per pass
  in a vectorized SciPy microbenchmark on this worker host. Four arrays of that
  size (indices, argument, output) fit in roughly 70–100 MB, depending on reuse.
- 24 length-\(N\) NumPy FFTs took 16.9 ms in the same microbenchmark. This is an
  optimistic lower bound for the unmasked far wave; it does **not** apply directly
  to \(1_{mn\ge T}\).

The mask is the constant problem. A simple dyadic magnitude partition has 91
fully-far rectangles at \(z_F=20\). Their total side length is about \(24N\), and
independent chirp-convolution/FFT treatment costs approximately
\(\sum(s_I+s_J)\log_2(s_I+s_J)=2.29\times10^7\) butterfly units per asymptotic
channel. With \(P=24\), this is about \(5.5\times10^8\) butterfly units before
the transition correction. A shared butterfly could reduce this, but that is a
new specialized implementation, not an H2/HODLR drop-in.

For an optimistic structured complementary implementation, the work model is
\(O(P r_{\rm phase}N\log_2N)\): with \(P=24\), \(r_{\rm phase}=24\), and
\(\log_2N=16\), this is about \(6.0\times10^8\) complex-equivalent rank
operations. Generic dense rank transfers are closer to
\(O(P r_{\rm phase}^2N\log N)\), which is not competitive. A generic rank-24
butterfly factor storage estimate is
\(N\log_2N r^2\approx6.0\times10^8\) complex scalars, about 9.7 GB; analytic
DFT factors can avoid this storage, but then the hyperbolic mask still needs a
custom factorization.

There is also a precision issue. The scalar asymptotic experiment bottoms out near
\(8\times10^{-17}\), and the sampled far-row absolute sum is about \(3.7\times10^3\)
at its worst. Ordinary binary64 FFT/tree accumulation has an error scale of
roughly \(u\log_2N\) times such sums, which can be \(10^{-11}\) in a worst-case
absolute bound. Pairwise/compensated summation and exact/reused DFT phases would
be required even to make a \(10^{-13}\) claim plausible; no such implementation
was validated here. An entrywise budget of
\(10^{-13}/N\approx1.5\times10^{-18}\) would be below the observed binary64
scalar floor.

## 6. Relationship to FMM/H/H2/HSS/HODLR

Classical FMM obtains near-linear work from multipole/local expansions for separated
clusters ([Greengard–Rokhlin, 1987](https://doi.org/10.1016/0021-9991(87)90140-9)).
H- and H2-matrices likewise rely on low-rank admissible blocks and, for H2, nested
cluster bases ([Börm, 2007](https://doi.org/10.1016/j.laa.2006.10.021)). HSS algorithms
also assume low-rank off-diagonal structure ([Xia et al., 2010](https://doi.org/10.1002/nla.691)).
Those assumptions fail for same-level boxes of this kernel, as the full-rank table
shows. The oscillatory literature instead uses directional/complementary
partitions, which is precisely the product-adapted condition (9).

## Promotion decision

**Failure for the requested hierarchical candidate.** The local branch is cheap and
the dephased residual has complementary low rank, but the conventional hierarchy
does not. The far asymptotic route requires a bespoke masked butterfly, roughly
hundreds of millions of rank operations at this \(N\), plus compensated binary64
accumulation; neither its constants nor its \(10^{-13}\) application error was
demonstrated. Keep this as a possible specialized FFT/butterfly investigation, but
do not promote it as a winning FMM/H2/HSS/HODLR approach.

No files under src/ or bench/ were edited.
