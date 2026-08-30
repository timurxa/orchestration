# Worker 2 — butterfly / complementary low-rank structure

## Verdict

Do not promote this route. The matrix has complementary low-rank blocks, but favorable rank-12/13 edge measurements are not representative. Generic real-valued interior blocks require rank 24 at a $10^{-13}$ block tolerance, and a safe nested factorization needs roughly rank 26--28 after allowing error accumulation over $k=16$ levels. The resulting butterfly has substantially more work and memory than an optimistic FFT phase/amplitude baseline.

This is a cost-based rejection, not a claim that an accurate butterfly is impossible. A rank-24/26 approximation is numerically plausible; it simply does not satisfy the promotion criterion.

## Matrix and block experiment

I used $m,n=0,\ldots,N-1$, $N=2^k$, and

$$
A_{mn}=J_0(2\pi mn/N).
$$

For level $\ell$, I used complementary dyadic blocks

$$
I_{\ell,i}=[i2^\ell,(i+1)2^\ell),\qquad
J_{\ell,j}=[j2^{k-\ell},(j+1)2^{k-\ell}),
$$

so $|I||J|=N$. Singular-value ranks were measured as

$$
r_2=\min\{r:\sigma_r/\sigma_0\le\varepsilon\},
\qquad
r_F=\min\left\{r:
\frac{(\sum_{q\ge r}\sigma_q^2)^{1/2}}{\|B\|_F}\le\varepsilon\right\},
$$

where $B=A[I,J]$, with zero-based $\sigma_r$ and $\varepsilon=10^{-13}$ unless noted.

### Stable kernel evaluation

Direct double-precision scipy.special.j0 is not adequate for the $10^{-13}$ rank test at large arguments. For $x\ge64$, I evaluated

$$
J_0(x)=\sqrt{\frac{2}{\pi x}}
       \{P(x)\cos\theta-Q(x)\sin\theta\},
\qquad \theta=x-\pi/4,
$$

with 16 asymptotic terms, reducing the phase exactly through the integer remainder

$$
\theta\equiv 2\pi((mn)\bmod N)/N-\pi/4 \pmod {2\pi}.
$$

For $x<64$ I used scipy.special.j0; selected blocks were independently recomputed with 50-digit mpmath Bessel values. The phase-reduced evaluator agreed with 50-digit values to $6.9\times10^{-16}$ relative to the largest entry on a generic $256\times256$ block. In contrast, raw double j0 made the $N=65536$ edge block appear to have rank 240/256; its maximum absolute disagreement with the high-precision values was $1.26\times10^{-13}$.

### Measured ranks across powers of two

The sample-max column is the maximum over 64 deterministic/random position probes at the central complementary level. It is a representative generic-interior estimate, not an exhaustive proof over all $N^2$ blocks. LL is the low-low block $(i,j)=(0,0)$, maximized over all complementary levels. Axis $i=0/1$ maximizes over all column tiles at the central level for the first two row tiles. HH edge is the upper-right edge block, maximized over levels.

| $N$ | central block | sample max $r_2/r_F$ | LL $r_2$ | axis $i=0$ | axis $i=1$ | HH edge $r_2$ |
|---:|:---:|---:|---:|---:|---:|---:|
| 64 | $8\times8$ | 8/8 | 8 | -- | -- | 8 |
| 128 | $8\times16$ | 8/8 | 8 | -- | -- | 8 |
| 256 | $16\times16$ | 16/16 | 9 | 13 | 16 | 12 |
| 512 | $16\times32$ | 16/16 | 9 | 14 | 16 | 12 |
| 1024 | $32\times32$ | 23/23 | 9 | 15 | 18 | 12 |
| 2048 | $32\times64$ | 24/24 | 10 | 15 | 18 | 12 |
| 4096 | $64\times64$ | 24/24 | 10 | 15 | 18 | 13 |
| 8192 | $64\times128$ | 24/24 | 10 | 15 | 18 | 13 |
| 16384 | $128\times128$ | 24/24 | 10 | 15 | 18 | 13 |
| 32768 | $128\times256$ | 24/24 | 10 | 15 | 18 | 13 |
| 65536 | $256\times256$ | 24/24 | 10 | 15 | 18 | 13 |

The transition corner is benign but not rank one: LL stabilizes at rank 10. Blocks touching an axis but extending into a generic column/row range reach 15--18. Generic interior blocks control the rank and stabilize at 24.

Representative $N=65536$, $256\times256$ spectra are below. next/s0 is the first omitted singular value at the listed $r_2$.

| block start $(a,b)$ | interpretation | $r_2/r_F$ | next/s0 |
|:---:|:---|---:|---:|
| (0, 0) | LL transition | 10/10 | $1.36\times10^{-15}$ |
| (0, 32768) | axis-to-interior | 12/12 | $5.13\times10^{-14}$ |
| (50688, 9216) | generic interior | 24/24 | $4.77\times10^{-14}$ |
| (65280, 65280) | upper-right edge | 13/12 | $7.70\times10^{-15}$ |
| (32768, 32768) | center | 13/12 | $7.88\times10^{-15}$ |

For the generic block $(a,b)=(50688,9216)$, the singular-value ratios around the cutoff are

$$
\ldots,1.47\times10^{-12},1.40\times10^{-12},
4.77\times10^{-14},4.52\times10^{-14},
1.46\times10^{-15},1.46\times10^{-15},8.2\times10^{-16},\ldots.
$$

Thus the same block needs rank 24 at $10^{-13}$, rank 26 at $10^{-14}$, and rank 28 at $10^{-15}$. The paired spectrum is the real-valued $e^{+i\phi}+e^{-i\phi}$ effect; inspecting only one complex phase branch understates real rank by about 2x.

## Compression tests

### Chebyshev / product-polynomial compression

On the LL transition range $t=mn/N\in[0,1]$, sampled Chebyshev interpolation gave:

| scalar function | degree | sampled max error |
|:---|---:|---:|
| $J_0(2\pi t)$ | 16 | $5.24\times10^{-13}$ |
| $J_0(2\pi t)$ | 17 | $1.75\times10^{-13}$ |
| $J_0(2\pi t)$ | 18 | $5.77\times10^{-15}$ |
| $e^{i2\pi t}$ | 18 | $7.91\times10^{-14}$ |
| $e^{i2\pi t}$ | 19 | $7.00\times10^{-15}$ |

A degree-$d$ polynomial in $t=mn/N$ has separated rank at most $d+1$, so degree 18 is a safe analytic upper bound (rank 19) for the LL transition. The observed SVD/ID rank 10 is much better, but it is a numerical block rank rather than a uniform scalar error bound. For the real oscillatory cosine, a direct real Chebyshev split has a rank bound near $2(d+1)$; this is why ID or randomized compression is preferable to blindly expanding both phase branches.

### Interpolative and randomized compression

The following are relative spectral/Frobenius residuals on $N=65536$, using deterministic column ID (rand=false) and a Gaussian range finder with oversampling $p=8$, respectively.

| block | ID rank / residual | randomized rank / residual |
|:---|:---|:---|
| LL | $r=10:\ 2.31\times10^{-15}/2.09\times10^{-15}$ | -- |
| axis-to-edge LH | $r=12:\ 2.03\times10^{-13}/1.99\times10^{-13}$; $r=13:\ 2.74\times10^{-15}/2.75\times10^{-15}$ | -- |
| HH edge | $r=13:\ 2.06\times10^{-14}/1.57\times10^{-14}$; $r=14:\ 5.29\times10^{-16}/6.28\times10^{-16}$ | -- |
| generic interior | $r=24:\ 1.14\times10^{-13}/9.48\times10^{-14}$; $r=26:\ 3.59\times10^{-15}/2.95\times10^{-15}$ | $r=24,p=8:\ 4.77\times10^{-14}/4.13\times10^{-14}$ |

Across 24 additional generic central blocks, randomized rank 24 had worst spectral residual $5.03\times10^{-14}$; ID rank 26 had worst $4.55\times10^{-15}$. This supports rank 24 as a plausible block target and rank 26 as a safer practical ID target, but randomized compression is probabilistic and still needs a held-out check per level.

### Phase/amplitude splitting

For $x=2\pi mn/N\gg1$,

$$
J_0(x)=\sqrt{2/(\pi x)}\,[P(x)\cos(x-\pi/4)-Q(x)\sin(x-\pi/4)].
$$

The powers $x^{-q}$ split exactly into $m^{-q}n^{-q}$ times an $N$-dependent scalar. On $N=65536$ high-$x$ blocks, relative Frobenius errors were:

| retained asymptotic orders | HH edge | center |
|:---:|---:|---:|
| 0 only (leading cosine) | $2.37\times10^{-7}$ | $9.34\times10^{-7}$ |
| 0--1 (add $Q\sim-1/(8x)$) | $4.18\times10^{-13}$ | $6.54\times10^{-12}$ |
| 0--2 (also $P\sim1-9/(128x^2)$) | $9.50\times10^{-18}$ | $8.39\times10^{-17}$ |

The order-2 correction is required for a $10^{-13}$ target away from the upper-right edge. A complex phase implementation has complex rank 12 at $10^{-13}$, 13 at $10^{-14}$, and 14 at $10^{-15}$, but applying $\operatorname{Re}(Cx)$ costs roughly the real rank-24/26/28 alternative in scalar work and storage.

## Matrix-free butterfly design

The natural design is a standard complementary butterfly with row clusters at level $\ell$, column clusters at level $k-\ell$, and nested rank-$r$ bases:

1. Handle $m=0$ and $n=0$ explicitly; the $x^{-1/2}$ asymptotic factors are invalid there.
2. Use product Chebyshev/ID bases for LL and transition/axis blocks.
3. Use the phase-reduced asymptotic formula for high-$x$ samples, with order-2 amplitude correction.
4. Build row/column bases with randomized sketches or pivoted ID and form $r\times r$ transfer matrices between adjacent levels.
5. Apply the upward column transform, sparse middle transfers, and downward row transform without materializing $A$.

The kernel is evaluated during setup only. A matrix-free per-application implementation that recomputes every Bessel sample would lose the point of the factorization.

Let $L=k=16$ and use generic safe rank $r=26$ (rank 28 is the more conservative $10^{-15}$-local-error choice) at $N=65536$:

| quantity | $r=24$ | $r=26$ | $r=28$ |
|:---|---:|---:|---:|
| $rNL$ coefficient slots | 25.2 M | 27.3 M | 29.4 M |
| $2rNL$ typical two-sided slots/applications | 50.3 M | 54.5 M | 58.7 M |
| one $rNL$ real-double layer | 192 MiB | 208 MiB | 224 MiB |
| two such layers | 384 MiB | 416 MiB | 448 MiB |
| naive $r^2NL$ setup samples | 604.0 M | 708.8 M | 822.1 M |

The $O(r^2NL)$ setup count is the sample-equivalent cost of per-block Chebyshev/ID construction; analytic transfer matrices can reduce it, but transition blocks and nested basis changes still have to be handled. The stored factorization remains $O(rNL)$, and each application is $O(rNL)$ arithmetic with a large memory-bandwidth constant.

The order-2 phase/amplitude formula needs only three weighted complex DFTs for an *unmasked high-$x$ interior*, but that is not a complete transform: the hyperbolic transition mask changes the channel count. The strongest FFT-oriented planning point already present in the shared research is the masked asymptotic split at $N=65536$: about 26 length-$N$ complex FFTs plus 3.43 million direct near-field entries at cutoff $z_0=32$. It is not yet a validated winner, but it is the relevant optimistic baseline; the simpler rectangular split uses 12 FFTs plus roughly 80 million direct entries and is not the best comparison.

The masked baseline is about $26NL/2=13.6$ million radix-2 butterfly units, plus the direct near-field loop. The complementary butterfly needs roughly 54--59 million sparse coefficient applications at safe rank 26--28, with 416--448 MiB for two real coefficient layers. Thus it does not plausibly beat the best masked FFT baseline once complex FFT arithmetic, memory traffic, and setup are counted. If dense $r\times r$ transfer matrices are stored per block, the $O(r^2NL)$ storage is about 5.7--6.6 GB of real doubles at ranks 26--28, making the comparison still worse. Setup is also a disadvantage because the FFT plan/twiddles do not require data-dependent rank construction.

## Cheap falsification gate

Before implementing a full factorization, run the following small gate with the phase-reduced evaluator:

* At $N=1024$, $\ell=5$, $w=h=32$, test $I=[704,736)$, $J=[768,800)$. The measured rank is 23 at $10^{-13}$. Rank-12 ID has residual $1.76\times10^{-5}$, rank-23 ID $1.41\times10^{-13}$, and rank-24 ID $5.23\times10^{-15}$. This immediately falsifies any estimate based only on the rank-10 LL or rank-12 edge blocks.
* Sample at least 16 central blocks at $N=1024,2048,4096$, compute rank-24 randomized/ID residuals, and reject if any held-out spectral residual exceeds $10^{-13}$ (use $3\times10^{-15}$ for the per-level safety budget).
* If a candidate factorization survives, compare its matrix-free result against a high-precision direct reference at $N=64$ or $128$ on random vectors. The stable evaluator itself passed the high-precision block check above; no full butterfly application was built because the cost gate already rejects promotion.

## Reproducibility note

All measurements were run independently in Python with NumPy/SciPy; high-$x$ validation used 50-digit mpmath in disposable scratch space. Only this markdown artifact was written in the workspace; shared src/ and bench/ files were not modified.
