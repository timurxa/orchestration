#include "dht.h"

#include <complex.h>
#include <fftw3.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifndef PARTITION_RATIO
#define PARTITION_RATIO 2u
#endif

#ifndef DIRECT_ROW_LIMIT
#define DIRECT_ROW_LIMIT 0u
#endif

#if PARTITION_RATIO < 2
#error "PARTITION_RATIO must be at least two"
#endif

struct dht_plan {
    size_t n;
    double tol;
    double z0;
    unsigned terms;
    unsigned threads;
    double phase_scale;
    double inv_sqrt2;
    double *coeff;
    double *weights;
    double *scales;
    size_t *row_offset;
    size_t *row_length;
    double *small_kernel;
    size_t direct_count;
    fftw_complex *scratch;
    fftw_plan fft_plan;
};

/* Row bands are [b, min(PARTITION_RATIO*b, n)).  The lower endpoint is
 * deliberately used for the shared cutoff: this keeps every asymptotic
 * entry in the band at z >= z0 and avoids any far/near subtraction. */
static size_t geometric_base(size_t x) {
    size_t p = 1;
    while (p <= x / PARTITION_RATIO) {
        p *= PARTITION_RATIO;
    }
    return p;
}

/* The profile is deliberately conservative.  The caller can benchmark
 * neighboring profiles through dht_plan_create_profile below in the harness
 * by changing these two values in the public experimental entry point. */
static void choose_profile(double tol, unsigned *terms, double *cutoff) {
    if (!(tol > 0.0) || tol >= 1e-12) {
        *terms = 8;
        *cutoff = 48.0;
    } else if (tol >= 3e-13) {
        *terms = 8;
        *cutoff = 56.0;
    } else if (tol >= 1e-13) {
        *terms = 10;
        *cutoff = 64.0;
    } else {
        *terms = 10;
        *cutoff = 80.0;
    }
}

static int checked_mul_size(size_t a, size_t b, size_t *out) {
    if (a != 0 && b > SIZE_MAX / a) {
        return 0;
    }
    *out = a * b;
    return 1;
}

static double asym_coeff(unsigned p) {
    double a = 1.0;
    for (unsigned j = 1; j <= p; ++j) {
        a *= -((double)(2 * j - 1) * (double)(2 * j - 1)) /
             (8.0 * (double)j);
    }
    if ((p & 1u) == 0u) {
        return (p & 2u) ? -a : a;
    }
    return ((p & 2u) != 0u) ? a : -a;
}

static void kahan_add(double value, double *sum, double *correction) {
    double y = value - *correction;
    double t = *sum + y;
    *correction = (t - *sum) - y;
    *sum = t;
}

static void kahan_complex_add(double ar, double ai, double *sr, double *cr,
                              double *si, double *ci) {
    kahan_add(ar, sr, cr);
    kahan_add(ai, si, ci);
}

static int build_direct_region(dht_plan *p) {
    size_t n = p->n;
    size_t count = 0;
    double threshold = p->z0 * (double)n / (2.0 * M_PI);

    for (size_t m = 1; m < n; ++m) {
        size_t n0;
        if (m < DIRECT_ROW_LIMIT) {
            n0 = n;
        } else {
            size_t lo = geometric_base(m);
            double raw = threshold / (double)lo;
            n0 = raw >= (double)n ? n : (size_t)ceil(raw);
        }
        if (n0 > n) {
            n0 = n;
        }
        size_t len = n0 > 1 ? n0 - 1 : 0;
        p->row_length[m] = len;
        p->row_offset[m] = count;
        if (len > SIZE_MAX - count) {
            return 0;
        }
        count += len;
    }
    p->row_offset[0] = 0;
    p->row_length[0] = 0;
    p->direct_count = count;
    if (count == 0) {
        return 1;
    }
    p->small_kernel = (double *)malloc(count * sizeof(*p->small_kernel));
    if (p->small_kernel == NULL) {
        return 0;
    }

    double c = 2.0 * M_PI / (double)n;
    for (size_t m = 1; m < n; ++m) {
        size_t len = p->row_length[m];
        size_t off = p->row_offset[m];
        for (size_t j = 0; j < len; ++j) {
            size_t k = j + 1;
            p->small_kernel[off + j] = j0(c * (double)m * (double)k);
        }
    }
    return 1;
}

static int build_weights_and_scales(dht_plan *p) {
    size_t nk;
    if (!checked_mul_size((size_t)p->terms, p->n, &nk)) {
        return 0;
    }
    p->weights = (double *)malloc(nk * sizeof(*p->weights));
    p->scales = (double *)malloc(nk * sizeof(*p->scales));
    p->coeff = (double *)malloc((size_t)p->terms * sizeof(*p->coeff));
    if (p->weights == NULL || p->scales == NULL || p->coeff == NULL) {
        return 0;
    }

    double c = 2.0 * M_PI / (double)p->n;
    double sqrt2overpi = sqrt(2.0 / M_PI);
    for (unsigned q = 0; q < p->terms; ++q) {
        p->coeff[q] = asym_coeff(q);
        double exponent = (double)q + 0.5;
        double cscale = sqrt2overpi * pow(c, -exponent);
        for (size_t k = 0; k < p->n; ++k) {
            if (k == 0) {
                p->weights[(size_t)q * p->n + k] = 0.0;
            } else {
                p->weights[(size_t)q * p->n + k] = pow((double)k, -exponent);
            }
        }
        for (size_t m = 0; m < p->n; ++m) {
            if (m == 0) {
                p->scales[(size_t)q * p->n + m] = 0.0;
            } else {
                p->scales[(size_t)q * p->n + m] =
                    p->coeff[q] * cscale * pow((double)m, -exponent);
            }
        }
    }
    return 1;
}

static dht_plan *create_profile(size_t n, double tol, unsigned terms,
                                double cutoff, unsigned threads) {
    if (n < 2 || n > (size_t)INT32_MAX) {
        return NULL;
    }
    dht_plan *p = (dht_plan *)calloc(1, sizeof(*p));
    if (p == NULL) {
        return NULL;
    }
    p->n = n;
    p->tol = tol;
    p->threads = threads == 0 ? 1u : threads;
    p->inv_sqrt2 = 1.0 / sqrt(2.0);
    p->terms = terms;
    p->z0 = cutoff;
    if (p->terms == 0 || !(p->z0 > 0.0)) {
        free(p);
        return NULL;
    }

    p->row_offset = (size_t *)calloc(n, sizeof(*p->row_offset));
    p->row_length = (size_t *)calloc(n, sizeof(*p->row_length));
    size_t nk;
    if (p->row_offset == NULL || p->row_length == NULL ||
        !checked_mul_size((size_t)p->terms, n, &nk) ||
        !build_weights_and_scales(p) || !build_direct_region(p)) {
        dht_plan_destroy(p);
        return NULL;
    }

    p->scratch = (fftw_complex *)fftw_malloc(nk * sizeof(*p->scratch));
    if (p->scratch == NULL) {
        dht_plan_destroy(p);
        return NULL;
    }
    fftw_init_threads();
    fftw_plan_with_nthreads((int)p->threads);
    int nn = (int)n;
    int howmany = (int)p->terms;
    p->fft_plan = fftw_plan_many_dft(1, &nn, howmany, p->scratch, NULL, 1,
                                     nn, p->scratch, NULL, 1, nn,
                                     FFTW_BACKWARD, FFTW_MEASURE);
    if (p->fft_plan == NULL) {
        dht_plan_destroy(p);
        return NULL;
    }
    return p;
}

dht_plan *dht_plan_create(size_t n, double tol, unsigned threads) {
    unsigned terms;
    double cutoff;
    choose_profile(tol, &terms, &cutoff);
    return create_profile(n, tol, terms, cutoff, threads);
}

dht_plan *dht_plan_create_profile(size_t n, double tol, unsigned terms,
                                   double cutoff, unsigned threads) {
    return create_profile(n, tol, terms, cutoff, threads);
}

void dht_plan_destroy(dht_plan *p) {
    if (p == NULL) {
        return;
    }
    if (p->fft_plan != NULL) {
        fftw_destroy_plan(p->fft_plan);
    }
    if (p->scratch != NULL) {
        fftw_free(p->scratch);
    }
    free(p->small_kernel);
    free(p->row_length);
    free(p->row_offset);
    free(p->scales);
    free(p->weights);
    free(p->coeff);
    free(p);
}

static void add_direct_rows(const dht_plan *p, const dht_complex *x,
                            dht_complex *y) {
    for (size_t m = 1; m < p->n; ++m) {
        size_t len = p->row_length[m];
        size_t off = p->row_offset[m];
        double sr = 0.0, si = 0.0, cr = 0.0, ci = 0.0;
        for (size_t j = 0; j < len; ++j) {
            size_t k = j + 1;
            double a = p->small_kernel[off + j];
            kahan_complex_add(a * x[k].re, a * x[k].im, &sr, &cr, &si, &ci);
        }
        y[m].re += sr;
        y[m].im += si;
    }
}

static void add_zero_row(const dht_plan *p, const dht_complex *x,
                         dht_complex *y) {
    double sr = x[0].re, si = x[0].im;
    double cr = 0.0, ci = 0.0;
    for (size_t k = 1; k < p->n; ++k) {
        kahan_add(x[k].re, &sr, &cr);
        kahan_add(x[k].im, &si, &ci);
    }
    y[0].re = sr;
    y[0].im = si;
}

static void fill_batch(const dht_plan *p, size_t n0, const dht_complex *x) {
    size_t total = (size_t)p->terms * p->n;
    memset(p->scratch, 0, total * sizeof(*p->scratch));
    for (unsigned q = 0; q < p->terms; ++q) {
        fftw_complex *row = p->scratch + (size_t)q * p->n;
        const double *w = p->weights + (size_t)q * p->n;
        for (size_t k = n0; k < p->n; ++k) {
            row[k] = (x[k].re * w[k]) + I * (x[k].im * w[k]);
        }
    }
}

static void add_asym_block(const dht_plan *p, size_t lo, size_t hi,
                           const dht_complex *x, dht_complex *y) {
    double threshold = p->z0 * (double)p->n / (2.0 * M_PI);
    size_t raw_n0 = (size_t)ceil(threshold / (double)lo);
    size_t n0 = raw_n0 < p->n ? raw_n0 : p->n;

    /* The direct portion is added separately.  This block is omitted when
     * every input index is below the asymptotic threshold. */
    if (n0 >= p->n) {
        return;
    }
    fill_batch(p, n0, x);
    fftw_execute(p->fft_plan);

    for (size_t m = lo; m < hi; ++m) {
        size_t partner = m == 0 ? 0 : p->n - m;
        double yr = y[m].re;
        double yi = y[m].im;
        for (unsigned q = 0; q < p->terms; ++q) {
            const fftw_complex *row = p->scratch + (size_t)q * p->n;
            double ar = creal(row[m]), ai = cimag(row[m]);
            double br = creal(row[partner]), bi = cimag(row[partner]);
            double cr = 0.5 * (ar + br);
            double ci = 0.5 * (ai + bi);
            double sr = 0.5 * (ai - bi);
            double si = -0.5 * (ar - br);
            double hr, hi_value;
            if ((q & 1u) == 0u) {
                hr = (cr + sr) * p->inv_sqrt2;
                hi_value = (ci + si) * p->inv_sqrt2;
            } else {
                hr = (sr - cr) * p->inv_sqrt2;
                hi_value = (si - ci) * p->inv_sqrt2;
            }
            double scale = p->scales[(size_t)q * p->n + m];
            yr += scale * hr;
            yi += scale * hi_value;
        }
        y[m].re = yr;
        y[m].im = yi;
    }
}

int dht_apply(const dht_plan *p, const dht_complex *x, dht_complex *y) {
    if (p == NULL || x == NULL || y == NULL) {
        return -1;
    }
    for (size_t m = 0; m < p->n; ++m) {
        y[m].re = x[0].re;
        y[m].im = x[0].im;
    }
    add_zero_row(p, x, y);

    size_t lo = DIRECT_ROW_LIMIT > 1u ? DIRECT_ROW_LIMIT : 1u;
    while (lo < p->n) {
        size_t hi = lo > (p->n - 1) / PARTITION_RATIO
                        ? p->n
                        : lo * PARTITION_RATIO;
        add_asym_block(p, lo, hi, x, y);
        lo = hi;
    }
    add_direct_rows(p, x, y);
    return 0;
}

size_t dht_size(const dht_plan *p) { return p == NULL ? 0 : p->n; }
double dht_tolerance(const dht_plan *p) { return p == NULL ? NAN : p->tol; }
unsigned dht_asymptotic_terms(const dht_plan *p) { return p == NULL ? 0 : p->terms; }
double dht_asymptotic_cutoff(const dht_plan *p) { return p == NULL ? NAN : p->z0; }
size_t dht_direct_entries(const dht_plan *p) { return p == NULL ? 0 : p->direct_count; }

size_t dht_plan_bytes(const dht_plan *p) {
    if (p == NULL) {
        return 0;
    }
    size_t nk = (size_t)p->terms * p->n;
    return sizeof(*p) + 2 * p->n * sizeof(size_t) +
           p->direct_count * sizeof(double) +
           2 * nk * sizeof(double) + (size_t)p->terms * sizeof(double) +
           nk * sizeof(fftw_complex);
}

/* Compatibility hooks for the workspace benchmark, whose read-only copy may
 * request a runtime ratio.  Each scratch binary is compiled for one ratio;
 * rejecting a mismatched request prevents an accidentally mislabeled result. */
dht_plan *dht_plan_create_profile_ex(size_t n, double tol, unsigned terms,
                                      double cutoff, unsigned threads,
                                      unsigned block_ratio) {
    if (block_ratio != PARTITION_RATIO) {
        return NULL;
    }
    return create_profile(n, tol, terms, cutoff, threads);
}

unsigned dht_block_ratio(const dht_plan *p) {
    return p == NULL ? 0u : PARTITION_RATIO;
}
