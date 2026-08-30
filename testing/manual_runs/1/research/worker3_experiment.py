#!/usr/bin/env python3
"""Small-N checks for A[m,n] = J_0(2*pi*m*n/N).

This is deliberately a research scratch program, not production code.  It
compares direct evaluation with an FFT application of the large-argument
asymptotic expansion.  Cells below the certified asymptotic cutoff are
corrected directly, so the only approximation is on the remaining cells.
"""

from __future__ import annotations

import argparse
import math
from typing import Iterable

import numpy as np
from scipy.special import jv


def asymptotic_coefficients(order: int, terms: int) -> np.ndarray:
    """Return a_0,...,a_(2*terms+1) from DLMF 10.17.1."""
    a = np.ones(2 * terms + 2, dtype=float)
    for k in range(1, a.size):
        a[k] = a[k - 1] * (4.0 * order * order - (2 * k - 1) ** 2) / (8.0 * k)
    return a


def asymptotic_j0(z: np.ndarray | float, terms: int, a: np.ndarray | None = None):
    """M-term Poincare expansion of J_0(z), for positive real z."""
    if a is None:
        a = asymptotic_coefficients(0, terms)
    z_arr = np.asarray(z, dtype=float)
    mu = z_arr - math.pi / 4.0
    even = np.zeros_like(z_arr, dtype=float)
    odd = np.zeros_like(z_arr, dtype=float)
    for r in range(terms):
        even += ((-1.0) ** r) * a[2 * r] / z_arr ** (2 * r)
        odd += ((-1.0) ** r) * a[2 * r + 1] / z_arr ** (2 * r + 1)
    return np.sqrt(2.0 / (math.pi * z_arr)) * (
        np.cos(mu) * even - np.sin(mu) * odd
    )


def asymptotic_bound(z: float, terms: int, a: np.ndarray | None = None) -> float:
    """DLMF/Townsend first-neglected-term bound used for the cutoff."""
    if a is None:
        a = asymptotic_coefficients(0, terms)
    return math.sqrt(2.0 / (math.pi * z)) * (
        abs(a[2 * terms]) / z ** (2 * terms)
        + abs(a[2 * terms + 1]) / z ** (2 * terms + 1)
    )


def cutoff_for_bound(terms: int, entry_tol: float) -> float:
    """Smallest z on the decreasing tail with asymptotic_bound(z)<=tol."""
    a = asymptotic_coefficients(0, terms)
    lo, hi = 1.0, 2.0
    while asymptotic_bound(hi, terms, a) > entry_tol:
        hi *= 2.0
    for _ in range(100):
        mid = 0.5 * (lo + hi)
        if asymptotic_bound(mid, terms, a) > entry_tol:
            lo = mid
        else:
            hi = mid
    return hi


def direct_matrix(n: int) -> np.ndarray:
    indices = np.arange(n, dtype=float)
    return jv(0, 2.0 * math.pi * np.outer(indices, indices) / n)


def direct_apply(x: np.ndarray) -> np.ndarray:
    n = x.size
    return direct_matrix(n) @ x


def fft_asymptotic_apply(
    x: np.ndarray, terms: int = 12, entry_tol: float = 1.0e-15
) -> tuple[np.ndarray, float, int]:
    """Apply the asymptotic-FFT approximation and return (y, cutoff, pairs).

    To avoid catastrophic cancellation from inverse powers at small z, direct
    sum the boundary m<L or n<L, where L is chosen so alpha*L*L >= cutoff.
    The FFT is used only on the interior m,n >= L, where the scalar error
    bound applies.
    """
    n = x.size
    alpha = 2.0 * math.pi / n
    a = asymptotic_coefficients(0, terms)
    cutoff = cutoff_for_bound(terms, entry_tol)

    dtype = np.result_type(x, np.complex128)
    y = np.zeros(n, dtype=dtype)
    boundary = max(1, math.ceil(math.sqrt(cutoff / alpha)))
    boundary = min(n, boundary)

    # Directly evaluate the boundary rows and columns.  This includes the
    # zero row/column, where J_0(0)=1 and inverse powers are undefined.
    boundary_pairs = 0
    for mi in range(n):
        first_interior = boundary if mi >= boundary else n
        for ni in range(first_interior):
            y[mi] += jv(0, alpha * mi * ni) * x[ni]
            boundary_pairs += 1

    # For m,n >= 1, expand J_0(alpha*m*n).  The positive-exponent DFT is
    # T[m] = sum_n q[n] exp(+2*pi*i*m*n/n), obtained by N*ifft(q).
    # Its reversed bins are the negative-exponent DFT, so one FFT serves both
    # cosine and sine factors for complex input.
    m = np.arange(boundary, n, dtype=float)
    nn = np.arange(boundary, n, dtype=float)
    phase = math.pi / 4.0
    for r in range(terms):
        even_p = 2.0 * r + 0.5
        odd_p = even_p + 1.0
        even_scale = (
            math.sqrt(2.0 / math.pi)
            * ((-1.0) ** r)
            * a[2 * r]
            * alpha ** (-even_p)
        )
        odd_scale = (
            math.sqrt(2.0 / math.pi)
            * ((-1.0) ** r)
            * a[2 * r + 1]
            * alpha ** (-odd_p)
        )

        for power, scale, trigonometric_sum in (
            (even_p, even_scale, "cos"), (odd_p, odd_scale, "sin")
        ):
            q = np.zeros(n, dtype=dtype)
            q[boundary:] = x[boundary:] * nn ** (-power)
            positive = np.fft.ifft(q) * n
            negative = positive[(-np.arange(n)) % n]
            rotated_positive = np.exp(-1j * phase) * positive
            rotated_negative = np.exp(1j * phase) * negative
            if trigonometric_sum == "cos":
                factor_sum = 0.5 * (rotated_positive + rotated_negative)
                y[boundary:] += scale * m ** (-power) * factor_sum[boundary:]
            else:
                factor_sum = (rotated_positive - rotated_negative) / (2j)
                y[boundary:] -= scale * m ** (-power) * factor_sum[boundary:]

    return y, cutoff, boundary_pairs


def displacement_ranks(n: int) -> dict[str, int]:
    """Numerical ranks of standard Toeplitz/Hankel/circulant residuals."""
    a = direct_matrix(n)
    z = np.zeros((n, n), dtype=float)
    z[1:, :-1] = np.eye(n - 1)
    p = np.roll(np.eye(n), 1, axis=0)
    residuals = {
        "Toeplitz Z A - A Z": z @ a - a @ z,
        "Hankel Z A - A Z.T": z @ a - a @ z.T,
        "Circulant P A - A P": p @ a - a @ p,
    }
    ranks: dict[str, int] = {}
    for name, residual in residuals.items():
        singular_values = np.linalg.svd(residual, compute_uv=False)
        ranks[name] = int(
            np.count_nonzero(singular_values > singular_values[0] * 1.0e-12)
        )
    return ranks


def run(ns: Iterable[int], terms: int, entry_tol: float) -> None:
    print(f"terms={terms} entry_tol={entry_tol:.1e}")
    print("N  cutoff       direct_boundary  max_interior_error  max_matvec_error")
    for n in ns:
        a = direct_matrix(n)
        _, cutoff, direct_boundary = fft_asymptotic_apply(
            np.ones(n, dtype=np.complex128), terms, entry_tol
        )
        # Boundary cells are evaluated directly; check the scalar error only
        # on cells actually sent through the FFT.
        boundary = min(n, max(1, math.ceil(math.sqrt(cutoff * n / (2.0 * math.pi)))))
        interior_error = 0.0
        for mi in range(boundary, n):
            for ni in range(boundary, n):
                z = 2.0 * math.pi * mi * ni / n
                interior_error = max(
                    interior_error,
                    abs(float(jv(0, z)) - float(asymptotic_j0(z, terms))),
                )
        x = np.sin(np.arange(n)) + 1j * np.cos(0.37 * np.arange(n))
        error = np.max(np.abs(fft_asymptotic_apply(x, terms, entry_tol)[0] - a @ x))
        print(f"{n:3d} {cutoff:10.6f} {direct_boundary:16d} {interior_error:19.3e} {error:17.3e}")

    print("\nstandard displacement ranks at N=16:", displacement_ranks(16))
    n = 4
    a = direct_matrix(n)
    print("\nN=4 matrix (exact Toeplitz/circulant counterexample):")
    print(np.array2string(a, precision=15, suppress_small=False))
    print("A[1,1] vs A[0,0] =", a[1, 1], a[0, 0])
    print("A[1,2] vs A[0,1] =", a[1, 2], a[0, 1])

    n = 8
    a = direct_matrix(n)
    r11 = a[1, 1] * a[2, 2] / (a[1, 2] * a[2, 1])
    r22 = a[2, 2] * a[3, 3] / (a[2, 3] * a[3, 2])
    print("\nN=8 diagonal-scaled-Toeplitz cross ratios on d=0:", r11, r22)
    print("N=8 same product mod N, A[1,1] vs A[3,3] =", a[1, 1], a[3, 3])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ns", nargs="+", type=int, default=[8, 16, 32, 64, 128, 256])
    parser.add_argument("--terms", type=int, default=12)
    parser.add_argument("--entry-tol", type=float, default=1.0e-15)
    args = parser.parse_args()
    run(args.ns, args.terms, args.entry_tol)
