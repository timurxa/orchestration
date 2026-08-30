/*
 * Worker 9 scratch prototype.
 *
 * Exact-grid hybrid:
 *   z = 2*pi*m*k/N <= z_local : separable J0 power series;
 *   z_local < z < z_far       : setup-time direct J0 table;
 *   z >= z_far                 : Townsend-style masked asymptotic FFTs.
 *
 * This file deliberately includes the public production header only to make
 * a side-by-side benchmark possible.  It does not alter src/ or bench/.
 */

#include "../src/dht.h"

#include <complex.h>
#include <fftw3.h>
#include <inttypes.h>
#include <limits.h>
#include <math.h>
#include <mpfr.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    size_t n;
    unsigned local_terms;
    unsigned asym_terms;
    unsigned ratio;
    double z_local;
    double z_far;
    double alpha;
    double *taylor;
    double *weights;
    double *scales;
    double *direct_kernel;
    size_t *direct_offset;
    size_t *direct_start;
    size_t *direct_length;
    size_t direct_count;
    size_t local_count;
    size_t far_blocks;
    double *moment_re;
    double *moment_im;
    double *moment_cr;
    double *moment_ci;
    fftw_complex *scratch;
    fftw_plan fft_plan;
} hybrid_plan;

static void hybrid_destroy(hybrid_plan *p);

static volatile double benchmark_sink;
static uint64_t rng_state = UINT64_C(0x8f3c2d1e7a6b5948);

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

static int checked_mul_size(size_t a, size_t b, size_t *out) {
    if (a != 0 && b > SIZE_MAX / a) {
        return 0;
    }
    *out = a * b;
    return 1;
}

static size_t block_base(size_t x, unsigned ratio) {
    size_t p = 1;
    while (p <= x / ratio) {
        p *= ratio;
    }
    return p;
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

static size_t local_limit(const hybrid_plan *p, size_t m) {
    double raw = p->z_local / (p->alpha * (double)m);
    size_t limit = raw >= (double)(p->n - 1)
                       ? p->n - 1
                       : (size_t)floor(raw);
    while (limit > 0 &&
           p->alpha * (double)m * (double)limit > p->z_local) {
        --limit;
    }
    while (limit + 1 < p->n &&
           p->alpha * (double)m * (double)(limit + 1) <= p->z_local) {
        ++limit;
    }
    return limit;
}

static size_t first_far(const hybrid_plan *p, size_t lo) {
    double raw = p->z_far / (p->alpha * (double)lo);
    size_t first = raw >= (double)p->n ? p->n : (size_t)ceil(raw);
    while (first > 1 &&
           p->alpha * (double)lo * (double)(first - 1) >= p->z_far) {
        --first;
    }
    while (first < p->n &&
           p->alpha * (double)lo * (double)first < p->z_far) {
        ++first;
    }
    return first;
}

static int build_taylor(hybrid_plan *p) {
    p->taylor = (double *)malloc((size_t)p->local_terms * sizeof(*p->taylor));
    if (p->taylor == NULL) {
        return 0;
    }
    double magnitude = 1.0;
    for (unsigned r = 0; r < p->local_terms; ++r) {
        p->taylor[r] = (r & 1u) ? -magnitude : magnitude;
        magnitude /= 4.0 * (double)(r + 1) * (double)(r + 1);
    }
    return 1;
}

static int build_asym_tables(hybrid_plan *p) {
    size_t nk;
    if (!checked_mul_size((size_t)p->asym_terms, p->n, &nk)) {
        return 0;
    }
    p->weights = (double *)malloc(nk * sizeof(*p->weights));
    p->scales = (double *)malloc(nk * sizeof(*p->scales));
    if (p->weights == NULL || p->scales == NULL) {
        return 0;
    }

    double sqrt2overpi = sqrt(2.0 / M_PI);
    for (unsigned q = 0; q < p->asym_terms; ++q) {
        double exponent = (double)q + 0.5;
        double cscale = sqrt2overpi * pow(p->alpha, -exponent);
        double coeff = asym_coeff(q);
        for (size_t k = 0; k < p->n; ++k) {
            p->weights[(size_t)q * p->n + k] =
                k == 0 ? 0.0 : pow((double)k, -exponent);
        }
        for (size_t m = 0; m < p->n; ++m) {
            p->scales[(size_t)q * p->n + m] =
                m == 0 ? 0.0 : coeff * cscale * pow((double)m, -exponent);
        }
    }
    return 1;
}

static int build_split(hybrid_plan *p) {
    size_t count = 0;
    for (size_t m = 1; m < p->n; ++m) {
        size_t local = local_limit(p, m);
        size_t lo = block_base(m, p->ratio);
        size_t far = first_far(p, lo);
        size_t end = far > 0 ? far - 1 : 0;
        if (end >= p->n) {
            end = p->n - 1;
        }
        p->local_count += local;
        p->direct_start[m] = local + 1;
        p->direct_length[m] =
            end >= local + 1 ? end - (local + 1) + 1 : 0;
        if (p->direct_length[m] > SIZE_MAX - count) {
            return 0;
        }
        p->direct_offset[m] = count;
        count += p->direct_length[m];
    }
    p->direct_start[0] = 0;
    p->direct_length[0] = 0;
    p->direct_offset[0] = 0;
    p->direct_count = count;

    for (size_t lo = 1; lo < p->n;) {
        size_t hi = lo <= p->n / p->ratio ? lo * p->ratio : p->n;
        if (first_far(p, lo) < p->n) {
            ++p->far_blocks;
        }
        lo = hi;
    }
    return 1;
}

static int build_direct_kernel(hybrid_plan *p) {
    if (p->direct_count == 0) {
        return 1;
    }
    p->direct_kernel =
        (double *)malloc(p->direct_count * sizeof(*p->direct_kernel));
    if (p->direct_kernel == NULL) {
        return 0;
    }
    for (size_t m = 1; m < p->n; ++m) {
        size_t start = p->direct_start[m];
        size_t off = p->direct_offset[m];
        for (size_t j = 0; j < p->direct_length[m]; ++j) {
            size_t k = start + j;
            p->direct_kernel[off + j] =
                j0(p->alpha * (double)m * (double)k);
        }
    }
    return 1;
}

static hybrid_plan *hybrid_create(size_t n, unsigned local_terms,
                                  double z_local, unsigned asym_terms,
                                  double z_far, unsigned threads,
                                  unsigned ratio) {
    if (n < 2 || n > (size_t)INT32_MAX || local_terms == 0 ||
        asym_terms == 0 || !(z_local > 0.0) || !(z_far > z_local) ||
        ratio < 2) {
        return NULL;
    }
    hybrid_plan *p = (hybrid_plan *)calloc(1, sizeof(*p));
    if (p == NULL) {
        return NULL;
    }
    p->n = n;
    p->local_terms = local_terms;
    p->asym_terms = asym_terms;
    p->z_local = z_local;
    p->z_far = z_far;
    p->ratio = ratio;
    p->alpha = 2.0 * M_PI / (double)n;

    p->direct_start = (size_t *)calloc(n, sizeof(*p->direct_start));
    p->direct_length = (size_t *)calloc(n, sizeof(*p->direct_length));
    p->direct_offset = (size_t *)calloc(n, sizeof(*p->direct_offset));
    if (p->direct_start == NULL || p->direct_length == NULL ||
        p->direct_offset == NULL ||
        !build_taylor(p) || !build_asym_tables(p) || !build_split(p) ||
        !build_direct_kernel(p)) {
        hybrid_destroy(p);
        return NULL;
    }

    size_t nk;
    if (!checked_mul_size((size_t)p->asym_terms, n, &nk)) {
        hybrid_destroy(p);
        return NULL;
    }
    p->scratch = (fftw_complex *)fftw_malloc(nk * sizeof(*p->scratch));
    p->moment_re = (double *)calloc(local_terms, sizeof(*p->moment_re));
    p->moment_im = (double *)calloc(local_terms, sizeof(*p->moment_im));
    p->moment_cr = (double *)calloc(local_terms, sizeof(*p->moment_cr));
    p->moment_ci = (double *)calloc(local_terms, sizeof(*p->moment_ci));
    if (p->scratch == NULL || p->moment_re == NULL || p->moment_im == NULL ||
        p->moment_cr == NULL || p->moment_ci == NULL) {
        hybrid_destroy(p);
        return NULL;
    }

    fftw_init_threads();
    fftw_plan_with_nthreads((int)(threads == 0 ? 1u : threads));
    int nn = (int)n;
    int howmany = (int)p->asym_terms;
    p->fft_plan = fftw_plan_many_dft(1, &nn, howmany, p->scratch, NULL, 1,
                                     nn, p->scratch, NULL, 1, nn,
                                     FFTW_BACKWARD, FFTW_MEASURE);
    if (p->fft_plan == NULL) {
        hybrid_destroy(p);
        return NULL;
    }
    return p;
}

static void hybrid_destroy(hybrid_plan *p) {
    if (p == NULL) {
        return;
    }
    if (p->fft_plan != NULL) {
        fftw_destroy_plan(p->fft_plan);
    }
    if (p->scratch != NULL) {
        fftw_free(p->scratch);
    }
    free(p->moment_ci);
    free(p->moment_cr);
    free(p->moment_im);
    free(p->moment_re);
    free(p->direct_kernel);
    free(p->direct_offset);
    free(p->direct_length);
    free(p->direct_start);
    free(p->scales);
    free(p->weights);
    free(p->taylor);
    free(p);
}

static size_t hybrid_bytes(const hybrid_plan *p) {
    if (p == NULL) {
        return 0;
    }
    size_t nk = (size_t)p->asym_terms * p->n;
    size_t bytes = sizeof(*p) + 3 * p->n * sizeof(size_t);
    bytes += p->direct_count * sizeof(double);
    bytes += 2 * nk * sizeof(double) +
             (size_t)p->local_terms * 5 * sizeof(double);
    bytes += nk * sizeof(fftw_complex);
    bytes += (size_t)p->local_terms * sizeof(double);
    return bytes;
}

static void add_local_rows(hybrid_plan *p, const dht_complex *x,
                           dht_complex *y) {
    memset(p->moment_re, 0, (size_t)p->local_terms * sizeof(*p->moment_re));
    memset(p->moment_im, 0, (size_t)p->local_terms * sizeof(*p->moment_im));
    memset(p->moment_cr, 0, (size_t)p->local_terms * sizeof(*p->moment_cr));
    memset(p->moment_ci, 0, (size_t)p->local_terms * sizeof(*p->moment_ci));

    size_t next = 1;
    for (size_t m = p->n - 1; m > 0; --m) {
        size_t limit = local_limit(p, m);
        while (next <= limit) {
            double t = p->alpha * (double)next;
            double base = t * t;
            double power = 1.0;
            for (unsigned r = 0; r < p->local_terms; ++r) {
                kahan_complex_add(x[next].re * power, x[next].im * power,
                                  &p->moment_re[r], &p->moment_cr[r],
                                  &p->moment_im[r], &p->moment_ci[r]);
                power *= base;
            }
            ++next;
        }

        double sr = 0.0, si = 0.0, cr = 0.0, ci = 0.0;
        double m2 = (double)m * (double)m;
        double mpower = 1.0;
        for (unsigned r = 0; r < p->local_terms; ++r) {
            double factor = p->taylor[r] * mpower;
            kahan_complex_add(factor * p->moment_re[r],
                              factor * p->moment_im[r], &sr, &cr, &si, &ci);
            mpower *= m2;
        }
        y[m].re += sr;
        y[m].im += si;
    }
}

static void add_direct_rows(const hybrid_plan *p, const dht_complex *x,
                            dht_complex *y) {
    for (size_t m = 1; m < p->n; ++m) {
        double sr = 0.0, si = 0.0, cr = 0.0, ci = 0.0;
        size_t off = p->direct_offset[m];
        size_t start = p->direct_start[m];
        for (size_t j = 0; j < p->direct_length[m]; ++j) {
            double a = p->direct_kernel[off + j];
            size_t k = start + j;
            kahan_complex_add(a * x[k].re, a * x[k].im, &sr, &cr, &si,
                              &ci);
        }
        y[m].re += sr;
        y[m].im += si;
    }
}

static void add_zero_row(const hybrid_plan *p, const dht_complex *x,
                         dht_complex *y) {
    double sr = x[0].re, si = x[0].im, cr = 0.0, ci = 0.0;
    for (size_t k = 1; k < p->n; ++k) {
        kahan_add(x[k].re, &sr, &cr);
        kahan_add(x[k].im, &si, &ci);
    }
    y[0].re = sr;
    y[0].im = si;
}

static void fill_far_batch(const hybrid_plan *p, size_t first,
                           const dht_complex *x) {
    size_t total = (size_t)p->asym_terms * p->n;
    memset(p->scratch, 0, total * sizeof(*p->scratch));
    for (unsigned q = 0; q < p->asym_terms; ++q) {
        fftw_complex *row = p->scratch + (size_t)q * p->n;
        const double *weights = p->weights + (size_t)q * p->n;
        for (size_t k = first; k < p->n; ++k) {
            row[k] = (x[k].re * weights[k]) + I * (x[k].im * weights[k]);
        }
    }
}

static void reduce_far_rows(const hybrid_plan *p, size_t lo, size_t hi,
                            dht_complex *y) {
    const double inv_sqrt2 = 1.0 / sqrt(2.0);
    for (size_t m = lo; m < hi; ++m) {
        size_t partner = p->n - m;
        double yr = y[m].re, yi = y[m].im;
        for (unsigned q = 0; q < p->asym_terms; ++q) {
            const fftw_complex *row = p->scratch + (size_t)q * p->n;
            double ar = creal(row[m]), ai = cimag(row[m]);
            double br = creal(row[partner]), bi = cimag(row[partner]);
            double real_even = 0.5 * (ar + br);
            double imag_even = 0.5 * (ai + bi);
            double real_odd = 0.5 * (ai - bi);
            double imag_odd = -0.5 * (ar - br);
            double hr, hi_value;
            if ((q & 1u) == 0u) {
                hr = (real_even + real_odd) * inv_sqrt2;
                hi_value = (imag_even + imag_odd) * inv_sqrt2;
            } else {
                hr = (real_odd - real_even) * inv_sqrt2;
                hi_value = (imag_odd - imag_even) * inv_sqrt2;
            }
            double scale = p->scales[(size_t)q * p->n + m];
            yr += scale * hr;
            yi += scale * hi_value;
        }
        y[m].re = yr;
        y[m].im = yi;
    }
}

static void add_far_rows(const hybrid_plan *p, const dht_complex *x,
                         dht_complex *y) {
    for (size_t lo = 1; lo < p->n;) {
        size_t hi = lo <= p->n / p->ratio ? lo * p->ratio : p->n;
        size_t first = first_far(p, lo);
        if (first < p->n) {
            fill_far_batch(p, first, x);
            fftw_execute(p->fft_plan);
            reduce_far_rows(p, lo, hi, y);
        }
        lo = hi;
    }
}

static int hybrid_apply(const hybrid_plan *p_const, const dht_complex *x,
                        dht_complex *y) {
    if (p_const == NULL || x == NULL || y == NULL) {
        return -1;
    }
    hybrid_plan *p = (hybrid_plan *)p_const;
    for (size_t m = 0; m < p->n; ++m) {
        y[m].re = x[0].re;
        y[m].im = x[0].im;
    }
    add_zero_row(p, x, y);
    add_local_rows(p, x, y);
    add_direct_rows(p, x, y);
    add_far_rows(p, x, y);
    return 0;
}

static uint64_t next_u64(void) {
    uint64_t x = rng_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    rng_state = x;
    return x * UINT64_C(2685821657736338717);
}

static double uniform_signed(void) {
    return 2.0 * (double)(next_u64() >> 11) * 0x1.0p-53 - 1.0;
}

static void fill_input(dht_complex *x, size_t n, unsigned kind) {
    for (size_t k = 0; k < n; ++k) {
        double t = (double)k / (double)n;
        if (kind == 0) {
            x[k].re = uniform_signed();
            x[k].im = uniform_signed();
        } else if (kind == 1) {
            double u = (t - 0.37) / 0.07;
            double g = exp(-0.5 * u * u);
            x[k].re = g;
            x[k].im = -0.7 * g;
        } else if (kind == 2) {
            double u = (t - 0.61) / 0.17;
            double bump = fabs(u) < 1.0 ? exp(-1.0 / (1.0 - u * u)) : 0.0;
            x[k].re = bump;
            x[k].im = sin(37.0 * t) * bump;
        } else if (kind == 3) {
            x[k].re = sin(2.0 * M_PI * (0.125 * k + 0.00031 * k * k));
            x[k].im = cos(2.0 * M_PI * (0.237 * k - 0.00017 * k * k));
        } else {
            double exponent = -12.0 + 24.0 * t;
            double magnitude = pow(10.0, exponent);
            double sign = (k & 1u) ? -1.0 : 1.0;
            x[k].re = sign * magnitude;
            x[k].im = -sign * magnitude * (0.25 + 0.5 * t);
        }
    }
}

static void fill_delta(dht_complex *x, size_t n, size_t at) {
    memset(x, 0, n * sizeof(*x));
    if (at < n) {
        x[at].re = 1.0;
        x[at].im = -0.375;
    }
}

static void reference_dense(size_t n, const dht_complex *x, dht_complex *y) {
    mpfr_t pi2, z, value, sumr, sumi, term, xr, xi;
    mpfr_inits2(256, pi2, z, value, sumr, sumi, term, xr, xi,
                (mpfr_ptr)0);
    mpfr_const_pi(pi2, MPFR_RNDN);
    mpfr_mul_ui(pi2, pi2, 2, MPFR_RNDN);
    for (size_t m = 0; m < n; ++m) {
        mpfr_set_zero(sumr, 0);
        mpfr_set_zero(sumi, 0);
        for (size_t k = 0; k < n; ++k) {
            mpfr_set_ui(z, m, MPFR_RNDN);
            mpfr_mul_ui(z, z, k, MPFR_RNDN);
            mpfr_mul(z, z, pi2, MPFR_RNDN);
            mpfr_div_ui(z, z, n, MPFR_RNDN);
            mpfr_j0(value, z, MPFR_RNDN);
            mpfr_set_d(xr, x[k].re, MPFR_RNDN);
            mpfr_set_d(xi, x[k].im, MPFR_RNDN);
            mpfr_mul(term, value, xr, MPFR_RNDN);
            mpfr_add(sumr, sumr, term, MPFR_RNDN);
            mpfr_mul(term, value, xi, MPFR_RNDN);
            mpfr_add(sumi, sumi, term, MPFR_RNDN);
        }
        y[m].re = mpfr_get_d(sumr, MPFR_RNDN);
        y[m].im = mpfr_get_d(sumi, MPFR_RNDN);
    }
    mpfr_clears(pi2, z, value, sumr, sumi, term, xr, xi, (mpfr_ptr)0);
}

static void reference_delta(size_t n, size_t at, dht_complex *y) {
    mpfr_t pi2, z, value;
    mpfr_inits2(256, pi2, z, value, (mpfr_ptr)0);
    mpfr_const_pi(pi2, MPFR_RNDN);
    mpfr_mul_ui(pi2, pi2, 2, MPFR_RNDN);
    for (size_t m = 0; m < n; ++m) {
        mpfr_set_ui(z, m, MPFR_RNDN);
        mpfr_mul_ui(z, z, at, MPFR_RNDN);
        mpfr_mul(z, z, pi2, MPFR_RNDN);
        mpfr_div_ui(z, z, n, MPFR_RNDN);
        mpfr_j0(value, z, MPFR_RNDN);
        y[m].re = mpfr_get_d(value, MPFR_RNDN);
        y[m].im = -0.375 * y[m].re;
    }
    mpfr_clears(pi2, z, value, (mpfr_ptr)0);
}

static void error_metrics(const dht_complex *got, const dht_complex *ref,
                          size_t n, double *l2, double *linf) {
    long double sum = 0.0L;
    long double refsum = 0.0L;
    double maxerr = 0.0;
    double maxref = 0.0;
    for (size_t k = 0; k < n; ++k) {
        long double dr = (long double)got[k].re - ref[k].re;
        long double di = (long double)got[k].im - ref[k].im;
        sum += dr * dr + di * di;
        refsum += (long double)ref[k].re * ref[k].re +
                  (long double)ref[k].im * ref[k].im;
        double e = hypot((double)dr, (double)di);
        double r = hypot(ref[k].re, ref[k].im);
        if (e > maxerr) {
            maxerr = e;
        }
        if (r > maxref) {
            maxref = r;
        }
    }
    *l2 = sqrt((double)(sum / (refsum > 0.0L ? refsum : 1.0L)));
    *linf = maxerr / (maxref > 1e-300 ? maxref : 1e-300);
}

static int dense_checks(hybrid_plan *p, size_t max_n) {
    for (size_t n = 32; n <= max_n; n *= 2) {
        for (unsigned kind = 0; kind < 5; ++kind) {
            dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
            dht_complex *got = (dht_complex *)malloc(n * sizeof(*got));
            dht_complex *ref = (dht_complex *)malloc(n * sizeof(*ref));
            if (x == NULL || got == NULL || ref == NULL) {
                free(ref);
                free(got);
                free(x);
                return 0;
            }
            fill_input(x, n, kind);
            hybrid_plan *small = hybrid_create(
                n, p->local_terms, p->z_local, p->asym_terms, p->z_far, 1,
                p->ratio);
            int ok = small != NULL && hybrid_apply(small, x, got) == 0;
            if (ok) {
                reference_dense(n, x, ref);
                double l2, li;
                error_metrics(got, ref, n, &l2, &li);
                printf("dense N=%zu case=%u local=%u zL=%.1f asym=%u zF=%.1f "
                       "direct=%zu local_pairs=%zu rel_l2=%.4e "
                       "scaled_linf=%.4e %s\n",
                       n, kind, p->local_terms, p->z_local, p->asym_terms,
                       p->z_far, small->direct_count, small->local_count, l2,
                       li, (l2 <= 1e-13 && li <= 1e-12) ? "PASS" : "FAIL");
                ok = l2 <= 1e-13 && li <= 1e-12;
            }
            hybrid_destroy(small);
            free(ref);
            free(got);
            free(x);
            if (!ok) {
                return 0;
            }
        }
        if (n > max_n / 2) {
            break;
        }
    }
    return 1;
}

static int delta_check(size_t n, size_t at, const hybrid_plan *p) {
    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *got = (dht_complex *)malloc(n * sizeof(*got));
    dht_complex *ref = (dht_complex *)malloc(n * sizeof(*ref));
    if (x == NULL || got == NULL || ref == NULL) {
        free(ref);
        free(got);
        free(x);
        return 0;
    }
    fill_delta(x, n, at);
    int ok = hybrid_apply(p, x, got) == 0;
    if (ok) {
        reference_delta(n, at, ref);
        double l2, li;
        error_metrics(got, ref, n, &l2, &li);
        printf("delta N=%zu at=%zu rel_l2=%.4e scaled_linf=%.4e %s\n", n,
               at, l2, li,
               (l2 <= 1e-13 && li <= 1e-12) ? "PASS" : "FAIL");
        ok = l2 <= 1e-13 && li <= 1e-12;
    }
    free(ref);
    free(got);
    free(x);
    return ok;
}

static double checksum(const dht_complex *x, size_t n) {
    double sum = 0.0;
    for (size_t k = 0; k < n; ++k) {
        sum += x[k].re + x[k].im;
    }
    return sum;
}

static double measure_hybrid(hybrid_plan *p, const dht_complex *x,
                             dht_complex *y, unsigned reps,
                             unsigned warmups, double *min_out,
                             double *max_out) {
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    if (times == NULL) {
        return NAN;
    }
    for (unsigned i = 0; i < warmups; ++i) {
        hybrid_apply(p, x, y);
        benchmark_sink += checksum(y, p->n);
    }
    for (unsigned i = 0; i < reps; ++i) {
        double begin = now_seconds();
        hybrid_apply(p, x, y);
        times[i] = now_seconds() - begin;
        benchmark_sink += checksum(y, p->n);
    }
    double result = median(times, reps);
    double min_value = times[0], max_value = times[0];
    for (unsigned i = 1; i < reps; ++i) {
        if (times[i] < min_value) {
            min_value = times[i];
        }
        if (times[i] > max_value) {
            max_value = times[i];
        }
    }
    *min_out = min_value;
    *max_out = max_value;
    free(times);
    return result;
}

static double measure_baseline(dht_plan *p, const dht_complex *x,
                               dht_complex *y, unsigned reps,
                               unsigned warmups, double *min_out,
                               double *max_out) {
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    if (times == NULL) {
        return NAN;
    }
    for (unsigned i = 0; i < warmups; ++i) {
        dht_apply(p, x, y);
        benchmark_sink += checksum(y, dht_size(p));
    }
    for (unsigned i = 0; i < reps; ++i) {
        double begin = now_seconds();
        dht_apply(p, x, y);
        times[i] = now_seconds() - begin;
        benchmark_sink += checksum(y, dht_size(p));
    }
    double result = median(times, reps);
    double min_value = times[0], max_value = times[0];
    for (unsigned i = 1; i < reps; ++i) {
        if (times[i] < min_value) {
            min_value = times[i];
        }
        if (times[i] > max_value) {
            max_value = times[i];
        }
    }
    *min_out = min_value;
    *max_out = max_value;
    free(times);
    return result;
}

static int benchmark(size_t n, unsigned local_terms, double z_local,
                     unsigned asym_terms, double z_far, unsigned threads,
                     unsigned ratio, unsigned reps, unsigned warmups) {
    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *yh = (dht_complex *)malloc(n * sizeof(*yh));
    dht_complex *yb = (dht_complex *)malloc(n * sizeof(*yb));
    if (x == NULL || yh == NULL || yb == NULL) {
        free(yb);
        free(yh);
        free(x);
        return 0;
    }
    fill_input(x, n, 0);

    fftw_forget_wisdom();
    double begin = now_seconds();
    hybrid_plan *hp = hybrid_create(n, local_terms, z_local, asym_terms,
                                     z_far, threads, ratio);
    double hybrid_setup = now_seconds() - begin;
    fftw_forget_wisdom();
    begin = now_seconds();
    dht_plan *bp = dht_plan_create_profile_ex(
        n, 1e-13, asym_terms, z_far, threads, ratio);
    double baseline_setup = now_seconds() - begin;
    if (hp == NULL || bp == NULL) {
        hybrid_destroy(hp);
        dht_plan_destroy(bp);
        free(yb);
        free(yh);
        free(x);
        return 0;
    }

    double hmin, hmax, bmin, bmax;
    double hmed = measure_hybrid(hp, x, yh, reps, warmups, &hmin, &hmax);
    double bmed = measure_baseline(bp, x, yb, reps, warmups, &bmin, &bmax);
    printf("benchmark N=%zu local=%u zL=%.1f asym=%u zF=%.1f ratio=%u "
           "hybrid_direct=%zu hybrid_local=%zu far_blocks=%zu "
           "hybrid_setup_s=%.6f hybrid_median_s=%.6f hybrid_min_s=%.6f "
           "hybrid_max_s=%.6f hybrid_bytes=%zu "
           "baseline_direct=%zu baseline_setup_s=%.6f "
           "baseline_median_s=%.6f baseline_min_s=%.6f "
           "baseline_max_s=%.6f baseline_bytes=%zu speedup=%.4f "
           "checksums=%.17g,%.17g\n",
           n, local_terms, z_local, asym_terms, z_far, ratio, hp->direct_count,
           hp->local_count, hp->far_blocks, hybrid_setup, hmed, hmin, hmax,
           hybrid_bytes(hp), dht_direct_entries(bp), baseline_setup, bmed,
           bmin, bmax, dht_plan_bytes(bp), bmed / hmed, yh[n / 3].re,
           yb[n / 3].re);

    hybrid_destroy(hp);
    dht_plan_destroy(bp);
    free(yb);
    free(yh);
    free(x);
    return 1;
}

static void usage(const char *name) {
    fprintf(stderr,
            "usage: %s check [max_dense local_terms zL asym_terms zF ratio] |\n"
            "       %s bench [N reps warmups local_terms zL asym_terms zF ratio] |\n"
            "       %s all [max_dense N reps warmups local_terms zL asym_terms zF ratio]\n",
            name, name, name);
}

int main(int argc, char **argv) {
    unsigned local_terms = 20;
    double z_local = 6.0;
    unsigned asym_terms = 10;
    double z_far = 64.0;
    const unsigned threads = 1;
    unsigned ratio = 2;
    const size_t large_n = 65536;
    const char *mode = argc > 1 ? argv[1] : "all";
    size_t max_dense = 256;
    size_t bench_n = large_n;
    unsigned reps = 5;
    unsigned warmups = 2;
    int arg = 2;

    if (strcmp(mode, "check") == 0) {
        if (argc > arg) max_dense = (size_t)strtoull(argv[arg++], NULL, 10);
    } else if (strcmp(mode, "bench") == 0) {
        if (argc > arg) bench_n = (size_t)strtoull(argv[arg++], NULL, 10);
        if (argc > arg) reps = (unsigned)strtoul(argv[arg++], NULL, 10);
        if (argc > arg) warmups = (unsigned)strtoul(argv[arg++], NULL, 10);
    } else if (strcmp(mode, "all") == 0) {
        if (argc > arg) max_dense = (size_t)strtoull(argv[arg++], NULL, 10);
        if (argc > arg) bench_n = (size_t)strtoull(argv[arg++], NULL, 10);
        if (argc > arg) reps = (unsigned)strtoul(argv[arg++], NULL, 10);
        if (argc > arg) warmups = (unsigned)strtoul(argv[arg++], NULL, 10);
    }
    if (argc > arg) local_terms = (unsigned)strtoul(argv[arg++], NULL, 10);
    if (argc > arg) z_local = strtod(argv[arg++], NULL);
    if (argc > arg) asym_terms = (unsigned)strtoul(argv[arg++], NULL, 10);
    if (argc > arg) z_far = strtod(argv[arg++], NULL);
    if (argc > arg) ratio = (unsigned)strtoul(argv[arg++], NULL, 10);

    if (strcmp(mode, "check") == 0 || strcmp(mode, "all") == 0) {
        hybrid_plan *p = hybrid_create(large_n, local_terms, z_local,
                                        asym_terms, z_far, threads, ratio);
        if (p == NULL || !dense_checks(p, max_dense)) {
            hybrid_destroy(p);
            return 2;
        }
        size_t local_boundary = (size_t)floor(z_local * (double)large_n /
                                               (2.0 * M_PI * 257.0));
        if (!delta_check(large_n, 1, p) ||
            !delta_check(large_n, large_n - 1, p) ||
            !delta_check(large_n, local_boundary, p)) {
            hybrid_destroy(p);
            return 2;
        }
        printf("layout N=%zu local_terms=%u zL=%.1f asym_terms=%u zF=%.1f "
               "ratio=%u local_pairs=%zu direct_pairs=%zu far_blocks=%zu "
               "plan_bytes=%zu\n",
               large_n, p->local_terms, p->z_local, p->asym_terms, p->z_far,
               p->ratio, p->local_count, p->direct_count, p->far_blocks,
               hybrid_bytes(p));
        hybrid_destroy(p);
    }
    if (strcmp(mode, "bench") == 0 || strcmp(mode, "all") == 0) {
        if (!benchmark(bench_n, local_terms, z_local, asym_terms, z_far,
                       threads, ratio, reps, warmups)) {
            return 2;
        }
    } else if (strcmp(mode, "check") != 0) {
        usage(argv[0]);
        return 2;
    }
    if (benchmark_sink == 0.123456789) {
        puts("unreachable");
    }
    return 0;
}
