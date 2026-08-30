#!/usr/bin/env python3
"""Exact integer-count model for the masked full-length-FFT variants."""

import math
import sys


def coeffs(last):
    c = [1.0]
    for k in range(1, last + 1):
        c.append(c[-1] * (2 * k - 1) ** 2 / (8.0 * k))
    return c


def block_base(m, ratio):
    b = 1
    while b <= m // ratio:
        b *= ratio
    return b


def metrics(n, z0, terms, ratio):
    threshold = z0 * n / (2.0 * math.pi)
    direct = 0
    asym_entries = 0
    active = 0
    blocks = []
    b = 1
    while b < n:
        hi = min(ratio * b, n)
        raw = threshold / b
        n0 = n if raw >= n else math.ceil(raw)
        rows = hi - b
        length = n0 - 1 if n0 > 1 else 0
        direct += rows * length
        if n0 < n:
            active += 1
            asym_entries += rows * (n - n0)
        blocks.append((b, hi, n0, rows))
        b = hi

    c = coeffs(terms + 1)
    bound = math.sqrt(2.0 / (math.pi * z0)) * (
        c[terms] / z0**terms + c[terms + 1] / z0 ** (terms + 1)
    )
    # This is the plan accounting used by the scratch C implementation.
    struct_bytes = 120
    plan_bytes = (
        struct_bytes
        + 2 * n * 8
        + direct * 8
        + 2 * terms * n * 8
        + terms * 8
        + terms * n * 16
    )
    return {
        "ratio": ratio,
        "blocks": len(blocks),
        "active": active,
        "fft_count": active * terms,
        "fft_length": n,
        "direct": direct,
        "axes": 2 * n - 1,
        "asym_entries": asym_entries,
        "direct_bytes": direct * 8,
        "plan_bytes": plan_bytes,
        "bound": bound,
        "blocks_detail": blocks,
    }


def next_power_of_two(x):
    p = 1
    while p < x:
        p *= 2
    return p


def tiled_metrics(n, z0, terms, row_ratio, col_ratio):
    """Safe two-sided geometric tiling with local chirp convolutions.

    A cell is asymptotic only when its lower-left corner is already beyond the
    cutoff.  The FFT length is the conservative power-of-two length for the
    local linear convolution of its row and column extents.
    """
    threshold = z0 * n / (2.0 * math.pi)

    def blocks(ratio):
        out = []
        b = 1
        while b < n:
            hi = min(ratio * b, n)
            out.append((b, hi, hi - b))
            b = hi
        return out

    row_blocks = blocks(row_ratio)
    col_blocks = blocks(col_ratio)
    direct = 0
    far_cells = []
    for rb, rh, rows in row_blocks:
        for cb, ch, cols in col_blocks:
            if rb * cb < threshold:
                direct += rows * cols
            else:
                far_cells.append((rb, cb, rows, cols))

    lengths = [next_power_of_two(rows + cols - 1)
               for _, _, rows, cols in far_cells]
    return {
        "row_ratio": row_ratio,
        "col_ratio": col_ratio,
        "row_blocks": len(row_blocks),
        "col_blocks": len(col_blocks),
        "far_cells": len(far_cells),
        "direct": direct,
        "fft_count_lower": 4 * terms * len(far_cells),
        "max_fft_length": max(lengths) if lengths else 0,
        "sum_fft_lengths": sum(lengths),
        "sum_fft_work": sum(L * math.log2(L) for L in lengths),
        "length_hist": {L: lengths.count(L) for L in sorted(set(lengths))},
    }


def hybrid_metrics(n, z0, terms, ratio, direct_limit):
    """Dyadic/geometric bands after making all rows below a limit direct."""
    threshold = z0 * n / (2.0 * math.pi)
    direct = 0
    for m in range(1, n):
        if m < direct_limit:
            n0 = n
        else:
            b = block_base(m, ratio)
            raw = threshold / b
            n0 = n if raw >= n else math.ceil(raw)
        direct += n0 - 1 if n0 > 1 else 0

    active = 0
    b = max(1, direct_limit)
    while b < n:
        # The tested limits are aligned with the ratio, so b is a valid band
        # lower endpoint here.
        n0 = n if threshold / b >= n else math.ceil(threshold / b)
        if n0 < n:
            active += 1
        b = min(ratio * b, n)

    fixed = 120 + 2 * n * 8 + 2 * terms * n * 8 + terms * 8 + terms * n * 16
    return {
        "direct_limit": direct_limit,
        "active": active,
        "fft_count": active * terms,
        "direct": direct,
        "plan_bytes": fixed + direct * 8,
    }


def main(argv):
    n = int(argv[1]) if len(argv) > 1 else 65536
    z0 = float(argv[2]) if len(argv) > 2 else 34.0
    terms = int(argv[3]) if len(argv) > 3 else 8
    ratios = [int(v) for v in argv[4:]] or [2, 3, 4, 8, 16]

    print("ratio blocks active FFTs FFT_len direct(+,+) axes asym_entries plan_bytes E_bound")
    for ratio in ratios:
        v = metrics(n, z0, terms, ratio)
        print(
            f"{ratio:5d} {v['blocks']:6d} {v['active']:6d} {v['fft_count']:4d} "
            f"{v['fft_length']:7d} {v['direct']:12d} {v['axes']:8d} "
            f"{v['asym_entries']:12d} {v['plan_bytes']:10d} {v['bound']:.6e}"
        )

    print("\ntwo-sided local-convolution tilings (each far cell needs two signs;")
    print("the count is a lower bound assuming setup-time kernel FFTs are reused):")
    print("row_ratio col_ratio far_cells direct(+,+) apply_FFTs max_len sum_len")
    for row_ratio, col_ratio in ((2, 2), (2, 4), (4, 2)):
        v = tiled_metrics(n, z0, terms, row_ratio, col_ratio)
        print(
            f"{row_ratio:9d} {col_ratio:9d} {v['far_cells']:9d} "
            f"{v['direct']:12d} {v['fft_count_lower']:10d} "
            f"{v['max_fft_length']:7d} {v['sum_fft_lengths']:7d}"
        )

    print("\nhybrid direct-row threshold (ratio=2):")
    print("direct_limit active FFTs direct(+,+) plan_bytes")
    for limit in (0, 16, 32, 64, 128):
        v = hybrid_metrics(n, z0, terms, 2, limit)
        print(
            f"{limit:12d} {v['active']:6d} {v['fft_count']:4d} "
            f"{v['direct']:12d} {v['plan_bytes']:10d}"
        )

    # Print the exact blocks for the two primary candidates when requested.
    if len(ratios) <= 2:
        for ratio in ratios:
            print(f"\nratio={ratio} blocks (lo, hi, n0, rows):")
            for item in metrics(n, z0, terms, ratio)["blocks_detail"]:
                print(" ".join(str(x) for x in item))


if __name__ == "__main__":
    main(sys.argv)
