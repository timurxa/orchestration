#include <complex.h>
#include <fftw3.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static volatile double benchmark_sink;

static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + 1e-9 * (double)ts.tv_nsec;
}

static double median(double *a, unsigned n) {
    for (unsigned i = 1; i < n; ++i) {
        double v = a[i];
        unsigned j = i;
        while (j > 0 && a[j - 1] > v) {
            a[j] = a[j - 1];
            --j;
        }
        a[j] = v;
    }
    return a[n / 2];
}

static double checksum(const double *re, const double *im, size_t n) {
    double sum = 0.0;
    for (size_t i = 0; i < n; ++i) sum += re[i] + im[i];
    return sum;
}

static void kahan_add(double value, double *sum, double *correction) {
    double y = value - *correction;
    double t = *sum + y;
    *correction = (t - *sum) - y;
    *sum = t;
}

static size_t block_base(size_t x, unsigned ratio) {
    size_t p = 1;
    while (p <= x / ratio) p *= ratio;
    return p;
}

static void make_rows(size_t n, double z0, unsigned ratio, size_t *offset,
                      size_t *length, size_t *count_out) {
    size_t count = 0;
    double threshold = z0 * (double)n / (2.0 * M_PI);
    offset[0] = 0;
    length[0] = 0;
    for (size_t m = 1; m < n; ++m) {
        size_t lo = block_base(m, ratio);
        double raw = threshold / (double)lo;
        size_t n0 = raw >= (double)n ? n : (size_t)ceil(raw);
        if (n0 > n) n0 = n;
        length[m] = n0 > 1 ? n0 - 1 : 0;
        offset[m] = count;
        count += length[m];
    }
    *count_out = count;
}

static void direct_current(size_t n, const size_t *offset,
                           const size_t *length, const double *kernel,
                           const double *xre, const double *xim, double *yre,
                           double *yim) {
    for (size_t m = 1; m < n; ++m) {
        size_t len = length[m];
        size_t off = offset[m];
        double sr = 0.0, si = 0.0, cr = 0.0, ci = 0.0;
        for (size_t j = 0; j < len; ++j) {
            size_t k = j + 1;
            double a = kernel[off + j];
            kahan_add(a * xre[k], &sr, &cr);
            kahan_add(a * xim[k], &si, &ci);
        }
        yre[m] += sr;
        yim[m] += si;
    }
}

static void fill_current(fftw_complex *scratch, const double *weights,
                         const double *xre, const double *xim, size_t n,
                         unsigned terms, size_t n0) {
    memset(scratch, 0, (size_t)terms * n * sizeof(*scratch));
    for (unsigned q = 0; q < terms; ++q) {
        fftw_complex *row = scratch + (size_t)q * n;
        const double *w = weights + (size_t)q * n;
        for (size_t k = n0; k < n; ++k) {
            row[k] = (xre[k] * w[k]) + I * (xim[k] * w[k]);
        }
    }
}

static void fill_prefix_only(fftw_complex *scratch, const double *weights,
                             const double *xre, const double *xim, size_t n,
                             unsigned terms, size_t n0) {
    for (unsigned q = 0; q < terms; ++q) {
        fftw_complex *row = scratch + (size_t)q * n;
        const double *w = weights + (size_t)q * n;
        memset(row, 0, n0 * sizeof(*row));
        for (size_t k = n0; k < n; ++k) {
            row[k] = (xre[k] * w[k]) + I * (xim[k] * w[k]);
        }
    }
}

static void reduce_rows(const fftw_complex *scratch, const double *scales,
                        size_t n, unsigned terms, size_t lo, size_t hi,
                        double *yre, double *yim, int m_major) {
    const double inv_sqrt2 = 1.0 / sqrt(2.0);
    for (size_t m = lo; m < hi; ++m) {
        size_t partner = n - m;
        double yr = yre[m], yi = yim[m];
        for (unsigned q = 0; q < terms; ++q) {
            const fftw_complex *row = scratch + (size_t)q * n;
            double ar = creal(row[m]), ai = cimag(row[m]);
            double br = creal(row[partner]), bi = cimag(row[partner]);
            double cr = 0.5 * (ar + br);
            double ci = 0.5 * (ai + bi);
            double sr = 0.5 * (ai - bi);
            double si = -0.5 * (ar - br);
            double hr, hi_value;
            if ((q & 1u) == 0u) {
                hr = (cr + sr) * inv_sqrt2;
                hi_value = (ci + si) * inv_sqrt2;
            } else {
                hr = (sr - cr) * inv_sqrt2;
                hi_value = (si - ci) * inv_sqrt2;
            }
            size_t index = m_major ? m * (size_t)terms + q
                                   : (size_t)q * n + m;
            double scale = scales[index];
            yr += scale * hr;
            yi += scale * hi_value;
        }
        yre[m] = yr;
        yim[m] = yi;
    }
}

static double measure_direct(size_t n, const size_t *offset,
                             const size_t *length, const double *kernel,
                             const double *xre, const double *xim, double *yre,
                             double *yim, unsigned reps, unsigned warmups) {
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    for (unsigned i = 0; i < warmups; ++i) {
        memset(yre, 0, n * sizeof(*yre));
        memset(yim, 0, n * sizeof(*yim));
        direct_current(n, offset, length, kernel, xre, xim, yre, yim);
        benchmark_sink += checksum(yre, yim, n);
    }
    for (unsigned i = 0; i < reps; ++i) {
        memset(yre, 0, n * sizeof(*yre));
        memset(yim, 0, n * sizeof(*yim));
        double begin = now_seconds();
        direct_current(n, offset, length, kernel, xre, xim, yre, yim);
        times[i] = now_seconds() - begin;
        benchmark_sink += checksum(yre, yim, n);
    }
    double result = median(times, reps);
    free(times);
    return result;
}

static double measure_fill(int prefix_only, fftw_complex *scratch,
                           const double *weights, const double *xre,
                           const double *xim, size_t n, unsigned terms,
                           const size_t *n0s, size_t block_count,
                           unsigned reps, unsigned warmups) {
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    for (unsigned i = 0; i < warmups; ++i) {
        for (size_t b = 0; b < block_count; ++b) {
            if (prefix_only) {
                fill_prefix_only(scratch, weights, xre, xim, n, terms,
                                 n0s[b]);
            } else {
                fill_current(scratch, weights, xre, xim, n, terms, n0s[b]);
            }
        }
    }
    for (unsigned i = 0; i < reps; ++i) {
        double begin = now_seconds();
        for (size_t b = 0; b < block_count; ++b) {
            if (prefix_only) {
                fill_prefix_only(scratch, weights, xre, xim, n, terms,
                                 n0s[b]);
            } else {
                fill_current(scratch, weights, xre, xim, n, terms, n0s[b]);
            }
        }
        times[i] = now_seconds() - begin;
    }
    double result = median(times, reps);
    free(times);
    return result;
}

static double measure_reduce(int m_major, const fftw_complex *scratch,
                            const double *scales, size_t n, unsigned terms,
                            const size_t *los, const size_t *his,
                            size_t block_count, double *yre, double *yim,
                            unsigned reps, unsigned warmups) {
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    for (unsigned i = 0; i < warmups; ++i) {
        for (size_t b = 0; b < block_count; ++b) {
            reduce_rows(scratch, scales, n, terms, los[b], his[b], yre, yim,
                        m_major);
        }
    }
    for (unsigned i = 0; i < reps; ++i) {
        double begin = now_seconds();
        for (size_t b = 0; b < block_count; ++b) {
            reduce_rows(scratch, scales, n, terms, los[b], his[b], yre, yim,
                        m_major);
        }
        times[i] = now_seconds() - begin;
    }
    double result = median(times, reps);
    free(times);
    return result;
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned terms = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 10;
    unsigned reps = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 9;
    unsigned warmups = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 2;
    if (n == 0 || terms == 0 || reps == 0) return 2;
    size_t *offset = (size_t *)calloc(n, sizeof(*offset));
    size_t *length = (size_t *)calloc(n, sizeof(*length));
    size_t direct_count = 0;
    make_rows(n, 64.0, 2, offset, length, &direct_count);
    double *kernel = (double *)malloc(direct_count * sizeof(*kernel));
    double *xre = (double *)malloc(n * sizeof(*xre));
    double *xim = (double *)malloc(n * sizeof(*xim));
    double *weights = (double *)malloc((size_t)terms * n * sizeof(*weights));
    double *scales_q = (double *)malloc((size_t)terms * n * sizeof(*scales_q));
    double *scales_m = (double *)malloc((size_t)terms * n * sizeof(*scales_m));
    double *yre = (double *)calloc(n, sizeof(*yre));
    double *yim = (double *)calloc(n, sizeof(*yim));
    fftw_complex *scratch = (fftw_complex *)fftw_malloc(
        (size_t)terms * n * sizeof(*scratch));
    if (!offset || !length || !kernel || !xre || !xim || !weights ||
        !scales_q || !scales_m || !yre || !yim || !scratch) return 2;
    for (size_t k = 0; k < n; ++k) {
        xre[k] = cos(0.00017 * (double)k);
        xim[k] = sin(0.00031 * (double)k);
    }
    double c = 2.0 * M_PI / (double)n;
    for (size_t m = 1; m < n; ++m) {
        for (size_t j = 0; j < length[m]; ++j) {
            kernel[offset[m] + j] = j0(c * (double)m * (double)(j + 1));
        }
    }
    for (unsigned q = 0; q < terms; ++q) {
        double exponent = (double)q + 0.5;
        for (size_t k = 0; k < n; ++k) {
            weights[(size_t)q * n + k] = k == 0 ? 0.0 : pow((double)k, -exponent);
        }
        for (size_t m = 0; m < n; ++m) {
            double value = m == 0 ? 0.0 : pow((double)m, -exponent);
            scales_q[(size_t)q * n + m] = value;
            scales_m[m * (size_t)terms + q] = value;
        }
    }
    for (size_t i = 0; i < (size_t)terms * n; ++i) {
        scratch[i] = cos(0.00023 * (double)i) + I * sin(0.00037 * (double)i);
    }
    size_t block_los[64], block_his[64], block_n0s[64];
    size_t block_count = 0;
    for (size_t lo = 1; lo < n;) {
        size_t hi = lo <= n / 2 ? lo * 2 : n;
        size_t n0 = (size_t)ceil(64.0 * (double)n /
                                 (2.0 * M_PI * (double)lo));
        if (n0 < n) {
            block_los[block_count] = lo;
            block_his[block_count] = hi;
            block_n0s[block_count] = n0;
            ++block_count;
        }
        lo = hi;
    }
    double direct_s = measure_direct(n, offset, length, kernel, xre, xim, yre,
                                     yim, reps, warmups);
    double fill_s = measure_fill(0, scratch, weights, xre, xim, n, terms,
                                 block_n0s, block_count, reps, warmups);
    double prefix_s = measure_fill(1, scratch, weights, xre, xim, n, terms,
                                   block_n0s, block_count, reps, warmups);
    double reduce_q_s = measure_reduce(0, scratch, scales_q, n, terms,
                                       block_los, block_his, block_count, yre,
                                       yim, reps, warmups);
    double reduce_m_s = measure_reduce(1, scratch, scales_m, n, terms,
                                       block_los, block_his, block_count, yre,
                                       yim, reps, warmups);
    printf("N=%zu terms=%u direct_entries=%zu active_blocks=%zu direct_kahan_s=%.9f fill_memset_s=%.9f fill_prefix_s=%.9f reduce_qmajor_s=%.9f reduce_mmajor_s=%.9f checksum=%.17g,%.17g\n",
           n, terms, direct_count, block_count, direct_s, fill_s, prefix_s,
           reduce_q_s, reduce_m_s, yre[n / 3], yim[n / 3]);
    if (benchmark_sink == 0.123456789) puts("unreachable");
    fftw_free(scratch);
    free(yim); free(yre); free(scales_m); free(scales_q); free(weights);
    free(xim); free(xre); free(kernel); free(length); free(offset);
    return 0;
}
