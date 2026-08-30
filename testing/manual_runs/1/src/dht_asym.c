#include "dht.h"

#include <complex.h>
#include <dispatch/dispatch.h>
#include <fftw3.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

struct dht_plan {
    size_t n;
    double tol;
    double z0;
    unsigned terms;
    unsigned threads;
    unsigned block_ratio;
    double inv_sqrt2;
    double *coeff;
    double *weights;
    double *scales;
    size_t *row_offset;
    size_t *row_length;
    double *small_kernel;
    size_t direct_count;
    size_t *direct_bounds;
    size_t direct_tasks;
    fftw_complex *scratch;
    fftw_plan fft_plan;
};

static size_t block_base(size_t x, unsigned ratio) {
    size_t p = 1;
    while (p <= x / ratio) {
        p *= ratio;
    }
    return p;
}

/* The profile is deliberately conservative.  The caller can benchmark
 * neighboring profiles through dht_plan_create_profile_ex.  These defaults
 * are the fastest profile retained after dense MPFR and residual-sign tests. */
static void choose_profile(double tol, unsigned *terms, double *cutoff) {
    if (!(tol > 0.0) || tol >= 1e-13) {
        *terms = 10;
        *cutoff = 30.0;
    } else {
        *terms = 10;
        *cutoff = 40.0;
    }
}

static int checked_mul_size(size_t a, size_t b, size_t *out) {
    if (a != 0 && b > SIZE_MAX / a) {
        return 0;
    }
    *out = a * b;
    return 1;
}

static int checked_add_size(size_t a, size_t b, size_t *out) {
    if (b > SIZE_MAX - a) {
        return 0;
    }
    *out = a + b;
    return 1;
}

static size_t safe_prefix_length(double threshold, size_t lo, size_t n) {
    double raw = threshold / (double)lo;
    if (!isfinite(raw) || raw >= (double)n) {
        return n;
    }
    if (!(raw > 0.0)) {
        return 0;
    }
    double rounded = ceil(raw);
    if (rounded >= (double)n) {
        return n;
    }
    return (size_t)rounded;
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
        size_t lo = block_base(m, p->block_ratio);
        size_t n0 = safe_prefix_length(threshold, lo, n);
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
    size_t bytes;
    if (!checked_mul_size(count, sizeof(*p->small_kernel), &bytes)) {
        return 0;
    }
    p->small_kernel = (double *)malloc(bytes);
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

static int build_direct_schedule(dht_plan *p) {
    if (p->direct_count == 0) {
        return 1;
    }

    size_t band_count = 0;
    for (size_t b = 1; b < p->n;) {
        ++band_count;
        if (b > SIZE_MAX / p->block_ratio) {
            break;
        }
        b *= p->block_ratio;
    }
    size_t bytes;
    if (!checked_mul_size(band_count + 1, sizeof(size_t), &bytes)) {
        return 0;
    }
    size_t *starts = (size_t *)malloc(bytes);
    size_t *prefix = (size_t *)malloc(bytes);
    if (starts == NULL || prefix == NULL) {
        free(starts);
        free(prefix);
        return 0;
    }
    starts[0] = 1;
    size_t b = 1;
    for (size_t j = 0; j < band_count; ++j) {
        size_t next = b <= p->n / p->block_ratio
                          ? b * p->block_ratio
                          : p->n;
        if (next > p->n) {
            next = p->n;
        }
        starts[j + 1] = next;
        b = next;
    }
    prefix[0] = 0;
    for (size_t j = 0; j < band_count; ++j) {
        size_t lo = starts[j];
        size_t hi = starts[j + 1];
        size_t row_end;
        if (!checked_add_size(p->row_offset[hi - 1],
                              p->row_length[hi - 1], &row_end) ||
            row_end < p->row_offset[lo] ||
            !checked_add_size(prefix[j], row_end - p->row_offset[lo],
                              &prefix[j + 1])) {
            free(starts);
            free(prefix);
            return 0;
        }
    }

    size_t tasks = p->threads < band_count ? p->threads : band_count;
    if (tasks == 0) {
        tasks = 1;
    }
    if (!checked_mul_size(tasks + 1, sizeof(*p->direct_bounds), &bytes)) {
        free(starts);
        free(prefix);
        return 0;
    }
    p->direct_bounds = (size_t *)malloc(bytes);
    if (p->direct_bounds == NULL) {
        free(starts);
        free(prefix);
        return 0;
    }
    p->direct_tasks = tasks;
    p->direct_bounds[0] = 1;
    size_t previous_band = 0;
    for (size_t task = 1; task < tasks; ++task) {
        size_t target = (p->direct_count / tasks) * task +
                        (p->direct_count % tasks) * task / tasks;
        size_t min_band = previous_band + 1;
        size_t max_band = band_count - (tasks - task);
        size_t best_band = min_band;
        size_t best_distance = SIZE_MAX;
        for (size_t candidate = min_band; candidate <= max_band;
             ++candidate) {
            size_t value = prefix[candidate];
            size_t distance = value >= target ? value - target : target - value;
            if (distance < best_distance) {
                best_distance = distance;
                best_band = candidate;
            }
        }
        p->direct_bounds[task] = starts[best_band];
        previous_band = best_band;
    }
    p->direct_bounds[tasks] = p->n;
    free(starts);
    free(prefix);
    return 1;
}

static int build_weights_and_scales(dht_plan *p) {
    size_t nk;
    size_t data_bytes;
    size_t coeff_bytes;
    if (!checked_mul_size((size_t)p->terms, p->n, &nk)) {
        return 0;
    }
    if (!checked_mul_size(nk, sizeof(*p->weights), &data_bytes) ||
        !checked_mul_size((size_t)p->terms, sizeof(*p->coeff),
                          &coeff_bytes)) {
        return 0;
    }
    p->weights = (double *)malloc(data_bytes);
    p->scales = (double *)malloc(data_bytes);
    p->coeff = (double *)malloc(coeff_bytes);
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
                                double cutoff, unsigned threads,
                                unsigned block_ratio) {
    if (n == 0 || n > (size_t)INT_MAX || !isfinite(tol) || !(tol > 0.0) ||
        block_ratio < 2 || terms == 0 ||
        terms > (unsigned)INT_MAX || threads > (unsigned)INT_MAX ||
        !isfinite(cutoff) || !(cutoff > 0.0)) {
        return NULL;
    }
    dht_plan *p = (dht_plan *)calloc(1, sizeof(*p));
    if (p == NULL) {
        return NULL;
    }
    p->n = n;
    p->tol = tol;
    p->threads = threads == 0 ? 1u : threads;
    p->block_ratio = block_ratio;
    p->inv_sqrt2 = 1.0 / sqrt(2.0);
    p->terms = terms;
    p->z0 = cutoff;
    if (p->terms == 0 || !(p->z0 > 0.0)) {
        free(p);
        return NULL;
    }

    size_t row_bytes;
    size_t scratch_bytes;
    if (!checked_mul_size(n, sizeof(*p->row_offset), &row_bytes)) {
        free(p);
        return NULL;
    }
    p->row_offset = (size_t *)calloc(1, row_bytes);
    p->row_length = (size_t *)calloc(1, row_bytes);
    size_t nk;
    if (p->row_offset == NULL || p->row_length == NULL ||
        !checked_mul_size((size_t)p->terms, n, &nk) ||
        !checked_mul_size(nk, sizeof(*p->scratch), &scratch_bytes) ||
        !build_weights_and_scales(p) || !build_direct_region(p) ||
        !build_direct_schedule(p)) {
        dht_plan_destroy(p);
        return NULL;
    }

    p->scratch = (fftw_complex *)fftw_malloc(scratch_bytes);
    if (p->scratch == NULL) {
        dht_plan_destroy(p);
        return NULL;
    }
    /* FFTW's thread subsystem is process-global. It is initialized once per
     * plan here and intentionally left alive for the process lifetime so a
     * separately owned plan cannot be invalidated by another destructor. */
    if (fftw_init_threads() == 0) {
        dht_plan_destroy(p);
        return NULL;
    }
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
    return create_profile(n, tol, terms, cutoff, threads, 4);
}

dht_plan *dht_plan_create_profile(size_t n, double tol, unsigned terms,
                                   double cutoff, unsigned threads) {
    return create_profile(n, tol, terms, cutoff, threads, 4);
}

dht_plan *dht_plan_create_profile_ex(size_t n, double tol, unsigned terms,
                                      double cutoff, unsigned threads,
                                      unsigned block_ratio) {
    return create_profile(n, tol, terms, cutoff, threads, block_ratio);
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
    free(p->direct_bounds);
    free(p->row_length);
    free(p->row_offset);
    free(p->scales);
    free(p->weights);
    free(p->coeff);
    free(p);
}

typedef struct {
    const dht_plan *p;
    const dht_complex *x;
    dht_complex *y;
    size_t tasks;
} direct_context;

static void add_direct_rows_worker(void *opaque, size_t task) {
    direct_context *c = (direct_context *)opaque;
    size_t lo = c->p->direct_bounds[task];
    size_t hi = c->p->direct_bounds[task + 1];
    for (size_t m = lo; m < hi; ++m) {
        size_t len = c->p->row_length[m];
        size_t off = c->p->row_offset[m];
        double sr = 0.0, si = 0.0, cr = 0.0, ci = 0.0;
        for (size_t j = 0; j < len; ++j) {
            size_t k = j + 1;
            double a = c->p->small_kernel[off + j];
            kahan_complex_add(a * c->x[k].re, a * c->x[k].im, &sr, &cr,
                              &si, &ci);
        }
        c->y[m].re += sr;
        c->y[m].im += si;
    }
}

static void add_direct_rows(const dht_plan *p, const dht_complex *x,
                            dht_complex *y) {
    if (p->n < 2 || p->direct_count == 0) {
        return;
    }
    size_t tasks = p->direct_tasks;
    direct_context context = {p, x, y, tasks};
    dispatch_apply_f(tasks, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),
                     &context, add_direct_rows_worker);
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
    for (unsigned q = 0; q < p->terms; ++q) {
        fftw_complex *row = p->scratch + (size_t)q * p->n;
        const double *w = p->weights + (size_t)q * p->n;
        /* The suffix is completely overwritten below.  Clearing only the
         * prefix avoids rewriting K full scratch rows for every band. */
        memset(row, 0, n0 * sizeof(*row));
        for (size_t k = n0; k < p->n; ++k) {
            row[k] = (x[k].re * w[k]) + I * (x[k].im * w[k]);
        }
    }
}

static void add_asym_block(const dht_plan *p, size_t lo, size_t hi,
                           const dht_complex *x, dht_complex *y) {
    double threshold = p->z0 * (double)p->n / (2.0 * M_PI);
    size_t n0 = safe_prefix_length(threshold, lo, p->n);

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

    size_t lo = 1;
    while (lo < p->n) {
        size_t hi = lo <= p->n / p->block_ratio
                        ? lo * p->block_ratio
                        : p->n;
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
    size_t nk, bytes, total = sizeof(*p);
    if (!checked_mul_size((size_t)p->terms, p->n, &nk) ||
        !checked_mul_size(p->n, sizeof(*p->row_offset), &bytes) ||
        !checked_mul_size(bytes, 2, &bytes) ||
        !checked_add_size(total, bytes, &total) ||
        !checked_mul_size(p->direct_count, sizeof(*p->small_kernel),
                          &bytes) ||
        !checked_add_size(total, bytes, &total) ||
        !checked_mul_size(nk, sizeof(*p->weights), &bytes) ||
        !checked_mul_size(bytes, 2, &bytes) ||
        !checked_add_size(total, bytes, &total) ||
        !checked_mul_size((size_t)p->terms, sizeof(*p->coeff), &bytes) ||
        !checked_add_size(total, bytes, &total) ||
        !checked_mul_size(nk, sizeof(*p->scratch), &bytes) ||
        !checked_add_size(total, bytes, &total)) {
        return 0;
    }
    if (p->direct_tasks != 0) {
        if (!checked_add_size(p->direct_tasks, 1, &bytes) ||
            !checked_mul_size(bytes, sizeof(*p->direct_bounds), &bytes) ||
            !checked_add_size(total, bytes, &total)) {
            return 0;
        }
    }
    return total;
}

unsigned dht_block_ratio(const dht_plan *p) {
    return p == NULL ? 0 : p->block_ratio;
}
