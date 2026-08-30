# Worker 6: large-z `J0` stability and production arithmetic

## Decision

The large-argument series is numerically well behaved **when it is evaluated only
for** `z >= z0`.  A good binary64 scalar choice is

```text
K = 12,    z0 = 32.
```

Here `K` means that coefficient orders `0,1,...,K` are retained.  The real-
argument remainder bound is `8.40e-17` at the cutoff, and the finite sums have
condition numbers below `1.008` after conversion to the integer-grid cosine and
sine coefficients.

However, the direct-grid FFT factorization normally extends that polynomial to
all `(m,n)` and then adds a direct correction in the small-product region.  That
layout is a **FAIL under binary64**: at `N=65536`, `K=12`, the untrusted
asymptotic value at `(m,n)=(1,1)` is of order `1e53`.  Subtracting it from the
exact `J0` value loses roughly 67 decimal digits; a binary64 residual is not
usable.  A masked/rectangular decomposition or extended-precision near-field
calculation would be a different algorithm and must be rebenchmarked.

Thus this expansion is a useful far-field component, but the simple
“26 FFTs plus direct residual corrections” production candidate should not pass
the stated `1e-13`/`1e-12` matvec gate.

## 1. Order-zero expansion

Let

```text
alpha = 2*pi/N,
phi_mn = alpha*m*n,
z = phi_mn,
theta = z - pi/4.
```

For positive real `z`, the standard large-argument expansion is

```text
J0(z) ~ sqrt(2/(pi*z)) *
       ( cos(theta) * P(z) + sin(theta) * Q(z) ),
```

with

```text
P(z) = sum_{j>=0} (-1)^j c_(2j)   / z^(2j),
Q(z) = sum_{j>=0} (-1)^j c_(2j+1) / z^(2j+1),
```

truncated to order `K`.  The coefficient in the usual Hankel notation is

```text
a_k(nu) = product_{r=1..k} (4*nu^2 - (2r-1)^2) / (k! * 8^k).
```

For order zero, define the positive coefficients

```text
c_k = ((2k-1)!!)^2 / (k! * 8^k),
a_k(0) = (-1)^k c_k,
c_0 = 1,
c_(k+1) = c_k * (2k+1)^2 / (8*(k+1)).
```

The first values used by `K=12` are:

| `k` | `c_k` |
|---:|---:|
| 0 | 1 |
| 1 | 0.125 |
| 2 | 0.0703125 |
| 3 | 0.0732421875 |
| 4 | 0.112152099609375 |
| 5 | 0.227108001708984 |
| 6 | 0.572501420974731 |
| 7 | 1.72772750258446 |
| 8 | 6.07404200127348 |
| 9 | 24.3805296995561 |
| 10 | 110.017140269247 |
| 11 | 551.335896122021 |
| 12 | 3038.09051092238 |

The recurrence is preferable to evaluating factorials, gamma functions, or
signed products.  It keeps `c_k` positive and applies the alternating signs only
when forming `P` and `Q`.

The formula follows DLMF [10.17.1](https://dlmf.nist.gov/10.17.E1),
[10.17.2](https://dlmf.nist.gov/10.17.E2), and
[10.17.3](https://dlmf.nist.gov/10.17.E3).

## 2. Exact integer-grid FFT specialization

Use

```text
cos(phi - pi/4) = (cos(phi) + sin(phi))/sqrt(2),
sin(phi - pi/4) = (sin(phi) - cos(phi))/sqrt(2).
```

Therefore the truncated kernel is

```text
A_K(m,n) = 1/sqrt(pi*z) *
           ((P(z)-Q(z))*cos(phi_mn) + (P(z)+Q(z))*sin(phi_mn)).
```

This is the direct-grid specialization; no nonuniform phase or radial-grid
substitution is involved.  More usefully, each order is separable because

```text
z^(-(k+1/2)) = alpha^(-(k+1/2)) * m^(-(k+1/2)) * n^(-(k+1/2)).
```

Define the two signed DFTs

```text
F_+^(p)[m] = sum_{n=1..N-1} x[n] * n^(-p) * exp(+i*alpha*m*n),
F_-^(p)[m] = sum_{n=1..N-1} x[n] * n^(-p) * exp(-i*alpha*m*n),
```

where `p=k+1/2`, and let `b_k=(-1)^floor(k/2)c_k`.  The order contribution is

```text
even k: b_k*sqrt(2/pi)*alpha^(-p)*m^(-p) *
        ( exp(-i*pi/4)*F_+^(p) + exp(+i*pi/4)*F_-^(p) )/2,

odd k:  b_k*sqrt(2/pi)*alpha^(-p)*m^(-p) *
       ( exp(-i*pi/4)*F_+^(p) - exp(+i*pi/4)*F_-^(p) )/(2i).
```

Because `x` is complex, the two signs are independent.  The predicted count is
therefore

```text
2*(K+1) complex length-N FFTs.
```

For `K=12` this is 26 FFTs.  The `m=0` row and `n=0` column are exact `J0(0)=1`
axes and should be handled separately.  A real input could exploit conjugate
symmetry; the specified complex input cannot.

For production phase arithmetic, form the DFT phase through the FFT roots.  Do
not evaluate `cos(2*pi*m*n/N)` after forming a large rounded product.  For the
specified range, `m*n < 2^34` and `m*n/N` is exact when represented as a binary64
integer quotient, but reduction of `2*pi*m*n/N` still introduces avoidable phase
rounding.  The FFT specialization avoids that reduction entirely.

## 3. Cutoff and truncation order

For `nu=0`, the real-argument remainder theorem bounds each of the even and odd
series by its first omitted term.  This is the result stated in DLMF
[10.17(iii)](https://dlmf.nist.gov/10.17.iii).  If `e` is the first omitted even
order and `o` the first omitted odd order, a conservative absolute kernel bound
is

```text
E_K(z) = sqrt(2/(pi*z)) * (c_e/z^e + c_o/z^o).
```

The following are the smallest continuous cutoffs from this bound.  They are
rounded upward in actual use; the grid only samples `z=2*pi*m*n/N`.

| retained `K` | `z0` for `E_K <= 1e-13` | `z0` for `E_K <= 1e-14` | `z0` for `E_K <= 1e-16` | signed FFTs |
|---:|---:|---:|---:|---:|
| 8  | 32.365 | 41.127 | 66.511 | 18 |
| 10 | 23.350 | 28.440 | 42.247 | 22 |
| 12 | 19.090 | 22.573 | 31.594 | 26 |
| 14 | 16.777 | 19.410 | 26.002 | 30 |
| 16 | 15.422 | 17.546 | 22.727 | 34 |

The recommended scalar choice `K=12,z0=32` has, at the cutoff,

```text
sqrt(2/(pi*z0))*c_13/z0^13 = 6.9801e-17,
sqrt(2/(pi*z0))*c_14/z0^14 = 1.4198e-17,
E_12(32) = 8.3999e-17.
```

At `z=32`, the largest retained term after the leading term is only
`c_1/z=3.90625e-3`; the order-12 term is `2.6351e-15`.  The terms are
monotonically decreasing through order 12 because

```text
term_(k+1)/term_k = (2k+1)^2 / (8*(k+1)*z) <= 0.188
```

over the retained range at `z>=32`.

Independent 120-decimal-digit `decimal` spot checks used the convergent power
series

```text
J0(z) = sum_{j>=0} (-1)^j * (z^2/4)^j / (j!)^2
```

for the reference.  The table reports the actual phase-specific error of the
high-precision `K=12` expansion; the bound above is the uniform guarantee.

| `z` | uniform bound `E_12(z)` | 120-digit observed error |
|---:|---:|---:|
| 12 | 6.062e-11 | 3.307e-11 |
| 16 | 1.138e-12 | 5.694e-13 |
| 20 | 5.270e-14 | 2.059e-15 |
| 24 | 4.313e-15 | 2.673e-15 |
| 28 | 5.218e-16 | 3.945e-16 |
| 32 | 8.400e-17 | 2.661e-17 |
| 40 | 3.991e-18 | 3.303e-18 |

Binary64 evaluation adds an approximately `1e-16` to few-`1e-16` scalar floor
depending on phase and summation order.  It is not the limiting error at the
recommended cutoff; the direct-region cancellation below is.

## 4. Coefficient cancellation and stable evaluation

For each finite sum, use the positive-term recurrence above and pairwise,
Kahan, or `fsum` accumulation.  At `K=12`, the absolute condition numbers at
the cutoff are small:

| `z` | `kappa(P)` | `kappa(Q)` | `kappa(P-Q)` | `kappa(P+Q)` |
|---:|---:|---:|---:|---:|
| 16 | 1.000550 | 1.004590 | 1.016306 | 1.000581 |
| 24 | 1.000244 | 1.002037 | 1.010718 | 1.000253 |
| 32 | 1.000137 | 1.001145 | 1.007982 | 1.000141 |

Here `kappa(sum)=sum(abs(terms))/abs(sum)`.  At `z=32`, for example,

```text
P = 0.999931441878041,
Q = 0.003904021544561,
P-Q = 0.996027420333480,
P+Q = 1.003835463422603.
```

With `u=2^-53`, a 13-term summation bound is approximately
`gamma_13=13u/(1-13u)=1.44e-15`; the coefficient sums themselves therefore do
not threaten the gate.  Relative pointwise error is of course unbounded at a
zero of `J0`, but the absolute kernel error remains bounded.

The serious cancellation is elsewhere.  If the factorized FFT result is formed
for all positive `(m,n)` and the small-product region is corrected by
`J0(z)-A_K(z)`, then `A_K` is being evaluated far outside its valid range.  At
`m=n=1`, `z_min=2*pi/N`.  The order-12 term alone has the following scale:

| `N` | `z_min` | `sqrt(2/(pi*z_min))*c_12/z_min^12` | one-binary64-ulp scale `u*B` |
|---:|---:|---:|---:|
| 4096 | 1.534e-3 | 3.646e38 | 4.048e22 |
| 8192 | 7.670e-4 | 2.112e42 | 2.345e26 |
| 16384 | 3.835e-4 | 1.223e46 | 1.358e30 |
| 32768 | 1.917e-4 | 7.086e49 | 7.867e33 |
| 65536 | 9.587e-5 | 4.105e53 | 4.557e37 |
| 131072 | 4.794e-5 | 2.378e57 | 2.640e41 |

The exact `z_min` values are `2*pi/N`; the displayed rounded values are for
readability.  To leave an absolute residual below `1e-13` at `N=65536` would
require about 220 mantissa bits (roughly 67 decimal digits) in that subtraction,
not 53 bits.

The following basis-input experiment used `x[1]=1`, all other `x[n]=0`, NumPy
complex FFTs, and direct `scipy.special.j0` residuals.  It is intentionally a
simple cancellation test rather than an end-to-end acceptance run:

| `N` | maximum unsafe asymptotic magnitude on the direct strip | resulting `L_inf` residual |
|---:|---:|---:|
| 4096  | 2.583e38 | 3.778e22 |
| 16384 | 8.654e45 | 1.268e30 |
| 65536 | 2.903e53 | 1.038e34 |
| 131072 | 1.681e57 | 6.646e35 |

This is the production-arithmetic failure mode: the direct correction count is
small relative to `N^2`, but the residual is formed against an enormous,
untrusted asymptotic quantity.  Increasing `K` makes the far-field truncation
better and makes this cancellation strictly worse.

## 5. Direct product region versus FFT count

With the strict direct condition `z<z0`, let

```text
q_max = ceil(z0*N/(2*pi)) - 1.
```

The number of positive-positive direct pairs is

```text
D(N,z0) = sum_{m=1..min(N-1,q_max)}
          min(N-1, floor(q_max/m)).
```

For `z0=32`, `K=12`, the counts are:

| `N` | `q_max` for direct region | `D(N,32)` positive-positive pairs | predicted signed FFTs |
|---:|---:|---:|---:|
| 4096   | 20860  | 156378  | 26 |
| 8192   | 41721  | 341688  | 26 |
| 16384  | 83443  | 741242  | 26 |
| 32768  | 166886 | 1598166 | 26 |
| 65536  | 333772 | 3427653 | 26 |
| 131072 | 667544 | 7318007 | 26 |

The axes add only `2N-1` exact entries and are excluded from `D`.  Since
`q_max=O(N)`, the direct product region is `O(N log N)` pairs, with a sizeable
constant.  At `N=65536`, it is 3.43 million direct pairs in addition to 26
length-`N` complex FFTs.

Some scalar-error tradeoffs at `N=65536` are:

| `K` | `z0` | bound at cutoff | direct pairs | signed FFTs |
|---:|---:|---:|---:|---:|
| 8  | 64 | 1.45e-16 | 6456021 | 18 |
| 10 | 40 | 1.89e-16 | 4205809 | 22 |
| 12 | 32 | 8.40e-17 | 3427653 | 26 |
| 14 | 24 | 3.53e-16 | 2625750 | 30 |
| 16 | 20 | 9.71e-16 | 2215574 | 34 |

These are algebraic counts only.  They do not make the global residual layout
stable; a mask that prevents the FFT expansion from touching `mn<q_max+1`
changes the factorization and adds work beyond this table.

## 6. Reproducibility snippet

The coefficient, bound, and pair-count tables can be regenerated with plain
Python (the dense exploratory scan used NumPy/SciPy; the spot table used the
120-digit Decimal series described above):

```python
import math

def coeffs(K):
    c = [1.0]
    for k in range(1, K + 3):
        c.append(c[-1] * (2*k - 1)**2 / (8.0*k))
    return c

def remainder_bound(z, K):
    c = coeffs(K)
    e = next(k for k in range(K + 1, K + 3) if k % 2 == 0)
    o = next(k for k in range(K + 1, K + 3) if k % 2 == 1)
    return math.sqrt(2.0/(math.pi*z)) * (c[e]/z**e + c[o]/z**o)

def direct_pairs(N, z0):
    qmax = math.ceil(z0*N/(2*math.pi)) - 1
    return sum(min(N-1, qmax//m)
               for m in range(1, min(N-1, qmax) + 1))

def unsafe_order_K_scale(N, K):
    c = coeffs(K)
    z = 2*math.pi/N
    return math.sqrt(2.0/(math.pi*z)) * c[K] / z**K

print(remainder_bound(32.0, 12))
for p in range(12, 18):
    N = 1 << p
    print(N, direct_pairs(N, 32.0), unsafe_order_K_scale(N, 12))
```

## Recommendation

**FAIL for the current production design**: do not submit the unmasked global
asymptotic FFT plus direct residual correction for the complete complex matvec.
It cannot satisfy the stated binary64 gate because of small-`z` cancellation,
even though its far-field scalar expansion is accurate enough.

Retain `K=12,z0=32` as the starting point only if a follow-up design guarantees
that no binary64 operation forms `A_12(z)` for `z<32`.  The follow-up must then
be tested against the independent multiprecision matvec reference, including
FFT roundoff and the direct near field; the scalar tables here are not an
end-to-end pass claim.
