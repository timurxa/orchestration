/* Research-only worker16 prototype.
 *
 * The production implementation is included read-only for its numerical
 * tables, exact direct-region construction, and output reduction.  This
 * translation unit owns a separate plan object whose first member is the
 * included dht_plan, so the private helpers can be reused without changing
 * src/ or bench/.
 */

#define dht_plan_create worker16_source_dht_plan_create
#define dht_plan_create_profile worker16_source_dht_plan_create_profile
#define dht_plan_create_profile_ex worker16_source_dht_plan_create_profile_ex
#define dht_plan_destroy worker16_source_dht_plan_destroy
#define dht_apply worker16_source_dht_apply
#define dht_size worker16_source_dht_size
#define dht_tolerance worker16_source_dht_tolerance
#define dht_asymptotic_terms worker16_source_dht_asymptotic_terms
#define dht_asymptotic_cutoff worker16_source_dht_asymptotic_cutoff
#define dht_direct_entries worker16_source_dht_direct_entries
#define dht_plan_bytes worker16_source_dht_plan_bytes
#define dht_block_ratio worker16_source_dht_block_ratio
#include "../src/dht_asym.c"
#undef dht_plan_create
#undef dht_plan_create_profile
#undef dht_plan_create_profile_ex
#undef dht_plan_destroy
#undef dht_apply
#undef dht_size
#undef dht_tolerance
#undef dht_asymptotic_terms
#undef dht_asymptotic_cutoff
#undef dht_direct_entries
#undef dht_plan_bytes
#undef dht_block_ratio

typedef struct {
    size_t lo;
    size_t hi;
    size_t n0;
} worker16_batch_band;

typedef struct {
    dht_plan base;
    worker16_batch_band *bands;
    size_t band_count;
    size_t fft_rows;
    fftw_complex *batch_scratch;
    fftw_plan batch_plan;
} worker16_batch_plan;

static void worker16_release_base(dht_plan *p) {
    if (p == NULL) {
        return;
    }
    free(p->small_kernel);
    free(p->row_length);
    free(p->row_offset);
    free(p->scales);
    free(p->weights);
    free(p->coeff);
    p->small_kernel = NULL;
    p->row_length = NULL;
    p->row_offset = NULL;
    p->scales = NULL;
    p->weights = NULL;
    p->coeff = NULL;
}

static int worker16_init_base(dht_plan *p, size_t n, double tol,
                              unsigned terms, double cutoff, unsigned threads,
                              unsigned block_ratio) {
    if (p == NULL || n < 2 || n > (size_t)INT32_MAX || terms == 0 ||
        block_ratio < 2 || !(cutoff > 0.0)) {
        return 0;
    }
    p->n = n;
    p->tol = tol;
    p->threads = threads == 0 ? 1u : threads;
    p->block_ratio = block_ratio;
    p->inv_sqrt2 = 1.0 / sqrt(2.0);
    p->terms = terms;
    p->z0 = cutoff;

    p->row_offset = (size_t *)calloc(n, sizeof(*p->row_offset));
    p->row_length = (size_t *)calloc(n, sizeof(*p->row_length));
    size_t nk;
    if (p->row_offset == NULL || p->row_length == NULL ||
        !checked_mul_size((size_t)terms, n, &nk) ||
        !build_weights_and_scales(p) || !build_direct_region(p)) {
        worker16_release_base(p);
        return 0;
    }
    return 1;
}

static size_t worker16_band_hi(const dht_plan *p, size_t lo) {
    return lo <= p->n / p->block_ratio ? lo * p->block_ratio : p->n;
}

static size_t worker16_band_n0(const dht_plan *p, size_t lo) {
    double threshold = p->z0 * (double)p->n / (2.0 * M_PI);
    size_t raw_n0 = (size_t)ceil(threshold / (double)lo);
    return raw_n0 < p->n ? raw_n0 : p->n;
}

static int worker16_build_batch(worker16_batch_plan *s) {
    const dht_plan *p = &s->base;
    size_t count = 0;
    size_t lo = 1;
    while (lo < p->n) {
        size_t hi = worker16_band_hi(p, lo);
        if (worker16_band_n0(p, lo) < p->n) {
            ++count;
        }
        lo = hi;
    }

    s->band_count = count;
    if (count == 0) {
        return 1;
    }
    s->bands = (worker16_batch_band *)calloc(count, sizeof(*s->bands));
    if (s->bands == NULL) {
        return 0;
    }

    size_t at = 0;
    lo = 1;
    while (lo < p->n) {
        size_t hi = worker16_band_hi(p, lo);
        size_t n0 = worker16_band_n0(p, lo);
        if (n0 < p->n) {
            s->bands[at].lo = lo;
            s->bands[at].hi = hi;
            s->bands[at].n0 = n0;
            ++at;
        }
        lo = hi;
    }

    if (!checked_mul_size(s->band_count, (size_t)p->terms, &s->fft_rows) ||
        s->fft_rows > (size_t)INT_MAX ||
        !checked_mul_size(s->fft_rows, p->n, &at)) {
        return 0;
    }
    size_t bytes;
    if (!checked_mul_size(at, sizeof(*s->batch_scratch), &bytes)) {
        return 0;
    }
    s->batch_scratch = (fftw_complex *)fftw_malloc(bytes);
    if (s->batch_scratch == NULL) {
        return 0;
    }

    fftw_init_threads();
    fftw_plan_with_nthreads((int)p->threads);
    int nn = (int)p->n;
    int howmany = (int)s->fft_rows;
    s->batch_plan = fftw_plan_many_dft(
        1, &nn, howmany, s->batch_scratch, NULL, 1, nn, s->batch_scratch,
        NULL, 1, nn, FFTW_BACKWARD, FFTW_MEASURE);
    return s->batch_plan != NULL;
}

static void worker16_release_batch(worker16_batch_plan *s) {
    if (s == NULL) {
        return;
    }
    if (s->batch_plan != NULL) {
        fftw_destroy_plan(s->batch_plan);
        s->batch_plan = NULL;
    }
    if (s->batch_scratch != NULL) {
        fftw_free(s->batch_scratch);
        s->batch_scratch = NULL;
    }
    free(s->bands);
    s->bands = NULL;
    s->band_count = 0;
    s->fft_rows = 0;
}

static worker16_batch_plan *worker16_create_profile(
    size_t n, double tol, unsigned terms, double cutoff, unsigned threads,
    unsigned block_ratio) {
    worker16_batch_plan *s =
        (worker16_batch_plan *)calloc(1, sizeof(*s));
    if (s == NULL) {
        return NULL;
    }
    if (!worker16_init_base(&s->base, n, tol, terms, cutoff, threads,
                            block_ratio) || !worker16_build_batch(s)) {
        worker16_release_batch(s);
        worker16_release_base(&s->base);
        free(s);
        return NULL;
    }
    return s;
}

dht_plan *dht_plan_create(size_t n, double tol, unsigned threads) {
    unsigned terms;
    double cutoff;
    choose_profile(tol, &terms, &cutoff);
    worker16_batch_plan *s = worker16_create_profile(
        n, tol, terms, cutoff, threads, 4);
    return s == NULL ? NULL : &s->base;
}

dht_plan *dht_plan_create_profile(size_t n, double tol, unsigned terms,
                                   double cutoff, unsigned threads) {
    worker16_batch_plan *s = worker16_create_profile(
        n, tol, terms, cutoff, threads, 4);
    return s == NULL ? NULL : &s->base;
}

dht_plan *dht_plan_create_profile_ex(size_t n, double tol, unsigned terms,
                                      double cutoff, unsigned threads,
                                      unsigned block_ratio) {
    worker16_batch_plan *s = worker16_create_profile(
        n, tol, terms, cutoff, threads, block_ratio);
    return s == NULL ? NULL : &s->base;
}

void dht_plan_destroy(dht_plan *p) {
    if (p == NULL) {
        return;
    }
    worker16_batch_plan *s = (worker16_batch_plan *)p;
    worker16_release_batch(s);
    worker16_release_base(&s->base);
    free(s);
}

static void worker16_fill_all(const worker16_batch_plan *s,
                              const dht_complex *x) {
    const dht_plan *p = &s->base;
    for (size_t b = 0; b < s->band_count; ++b) {
        size_t n0 = s->bands[b].n0;
        for (unsigned q = 0; q < p->terms; ++q) {
            size_t row_index = b * (size_t)p->terms + q;
            fftw_complex *row = s->batch_scratch + row_index * p->n;
            const double *w = p->weights + (size_t)q * p->n;
            /* Match the current mask exactly: [0,n0) is zero and the
             * product-safe suffix [n0,n) is weighted input. */
            memset(row, 0, n0 * sizeof(*row));
            for (size_t k = n0; k < p->n; ++k) {
                row[k] = (x[k].re * w[k]) + I * (x[k].im * w[k]);
            }
        }
    }
}

static void worker16_assemble_band(const worker16_batch_plan *s, size_t b,
                                   dht_complex *y) {
    const dht_plan *p = &s->base;
    const worker16_batch_band *band = &s->bands[b];
    for (size_t m = band->lo; m < band->hi; ++m) {
        size_t partner = m == 0 ? 0 : p->n - m;
        double yr = y[m].re;
        double yi = y[m].im;
        for (unsigned q = 0; q < p->terms; ++q) {
            size_t row_index = b * (size_t)p->terms + q;
            const fftw_complex *row = s->batch_scratch + row_index * p->n;
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
    const worker16_batch_plan *s = (const worker16_batch_plan *)p;
    for (size_t m = 0; m < p->n; ++m) {
        y[m].re = x[0].re;
        y[m].im = x[0].im;
    }
    add_zero_row(p, x, y);
    worker16_fill_all(s, x);
    if (s->batch_plan != NULL) {
        fftw_execute(s->batch_plan);
    }
    for (size_t b = 0; b < s->band_count; ++b) {
        worker16_assemble_band(s, b, y);
    }
    /* The included implementation's direct-row kernel is the current
     * direct-parallel path, including its Kahan accumulation order. */
    add_direct_rows(p, x, y);
    return 0;
}

size_t dht_size(const dht_plan *p) { return p == NULL ? 0 : p->n; }
double dht_tolerance(const dht_plan *p) {
    return p == NULL ? NAN : p->tol;
}
unsigned dht_asymptotic_terms(const dht_plan *p) {
    return p == NULL ? 0 : p->terms;
}
double dht_asymptotic_cutoff(const dht_plan *p) {
    return p == NULL ? NAN : p->z0;
}
size_t dht_direct_entries(const dht_plan *p) {
    return p == NULL ? 0 : p->direct_count;
}
unsigned dht_block_ratio(const dht_plan *p) {
    return p == NULL ? 0 : p->block_ratio;
}

size_t dht_plan_bytes(const dht_plan *p) {
    if (p == NULL) {
        return 0;
    }
    const worker16_batch_plan *s = (const worker16_batch_plan *)p;
    size_t nk = (size_t)p->terms * p->n;
    return sizeof(*s) + 2 * p->n * sizeof(size_t) +
           p->direct_count * sizeof(double) +
           2 * nk * sizeof(double) + (size_t)p->terms * sizeof(double) +
           s->band_count * sizeof(*s->bands) +
           s->fft_rows * p->n * sizeof(*s->batch_scratch);
}

/* Extra research introspection for the report/spot-check driver. */
size_t worker16_batch_active_bands(const dht_plan *p) {
    if (p == NULL) {
        return 0;
    }
    return ((const worker16_batch_plan *)p)->band_count;
}

size_t worker16_batch_fft_rows(const dht_plan *p) {
    if (p == NULL) {
        return 0;
    }
    return ((const worker16_batch_plan *)p)->fft_rows;
}

size_t worker16_batch_scratch_bytes(const dht_plan *p) {
    if (p == NULL) {
        return 0;
    }
    const worker16_batch_plan *s = (const worker16_batch_plan *)p;
    return s->fft_rows * p->n * sizeof(*s->batch_scratch);
}
