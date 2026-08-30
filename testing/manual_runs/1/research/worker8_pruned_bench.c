#include "../src/dht_asym.c"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    size_t lo;
    size_t hi;
    size_t n0;
    size_t selected_count;
    size_t *selected;
} worker8_pruned_band;

typedef struct {
    size_t n;
    unsigned log2n;
    size_t band_count;
    worker8_pruned_band *bands;
    fftw_complex *twiddle;
    size_t *bitrev;
    size_t *work;
    size_t max_selected;
    size_t selected_total;
    size_t butterfly_total;
    size_t full_butterfly_total;
} worker8_pruned_context;

static uint64_t worker8_rng_state = UINT64_C(0x8f3c2d1e7a6b5948);

static uint64_t worker8_next_u64(void) {
    uint64_t x = worker8_rng_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    worker8_rng_state = x;
    return x * UINT64_C(2685821657736338717);
}

static double worker8_uniform_signed(void) {
    return 2.0 * (double)(worker8_next_u64() >> 11) * 0x1.0p-53 - 1.0;
}

static void worker8_fill_input(dht_complex *x, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        x[k].re = worker8_uniform_signed();
        x[k].im = worker8_uniform_signed();
    }
}

static double worker8_now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + 1e-9 * (double)ts.tv_nsec;
}

static double worker8_median(double *a, unsigned n) {
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

static unsigned worker8_log2_exact(size_t n) {
    unsigned result = 0;
    while (n > 1) {
        if ((n & 1u) != 0u) return 0;
        n >>= 1;
        ++result;
    }
    return result;
}

static size_t worker8_bit_reverse(size_t value, unsigned bits) {
    size_t result = 0;
    for (unsigned i = 0; i < bits; ++i) {
        result = (result << 1) | (value & 1u);
        value >>= 1;
    }
    return result;
}

static size_t worker8_partition(size_t *items, size_t count, unsigned bit);

static size_t worker8_count_pruned_butterflies(size_t *selected,
                                               size_t count, size_t n,
                                               unsigned bit) {
    if (count == 0 || n <= 1) return 0;
    size_t split = worker8_partition(selected, count, bit);
    return n / 2 +
           worker8_count_pruned_butterflies(selected, split, n / 2,
                                            bit + 1) +
           worker8_count_pruned_butterflies(selected + split, count - split,
                                            n / 2, bit + 1);
}

static int worker8_make_context(const dht_plan *p,
                                worker8_pruned_context *ctx) {
    memset(ctx, 0, sizeof(*ctx));
    ctx->n = p->n;
    ctx->log2n = worker8_log2_exact(p->n);
    if (ctx->log2n == 0) return 0;
    ctx->full_butterfly_total =
        p->n / 2 * (size_t)ctx->log2n;
    ctx->twiddle = (fftw_complex *)fftw_malloc(
        p->n / 2 * sizeof(*ctx->twiddle));
    ctx->bitrev = (size_t *)malloc(p->n * sizeof(*ctx->bitrev));
    ctx->bands = (worker8_pruned_band *)calloc(p->n, sizeof(*ctx->bands));
    unsigned char *mark = (unsigned char *)calloc(p->n, sizeof(*mark));
    if (ctx->twiddle == NULL || ctx->bitrev == NULL || ctx->bands == NULL ||
        mark == NULL) {
        free(mark);
        return 0;
    }
    for (size_t i = 0; i < p->n / 2; ++i) {
        double angle = 2.0 * M_PI * (double)i / (double)p->n;
        ctx->twiddle[i] = cos(angle) + I * sin(angle);
    }
    for (size_t i = 0; i < p->n; ++i) {
        ctx->bitrev[i] = worker8_bit_reverse(i, ctx->log2n);
    }

    double threshold = p->z0 * (double)p->n / (2.0 * M_PI);
    size_t lo = 1;
    while (lo < p->n) {
        size_t hi = lo <= p->n / p->block_ratio
                        ? lo * p->block_ratio
                        : p->n;
        size_t raw_n0 = (size_t)ceil(threshold / (double)lo);
        size_t n0 = raw_n0 < p->n ? raw_n0 : p->n;
        if (n0 < p->n) {
            worker8_pruned_band *band = &ctx->bands[ctx->band_count++];
            band->lo = lo;
            band->hi = hi;
            band->n0 = n0;
            memset(mark, 0, p->n * sizeof(*mark));
            for (size_t m = lo; m < hi; ++m) {
                mark[m] = 1;
                mark[p->n - m] = 1;
            }
            for (size_t i = 0; i < p->n; ++i) {
                if (mark[i] != 0) ++band->selected_count;
            }
            band->selected = (size_t *)malloc(
                band->selected_count * sizeof(*band->selected));
            if (band->selected == NULL) {
                free(mark);
                return 0;
            }
            size_t at = 0;
            for (size_t i = 0; i < p->n; ++i) {
                if (mark[i] != 0) band->selected[at++] = i;
            }
            ctx->selected_total += band->selected_count;
            if (band->selected_count > ctx->max_selected) {
                ctx->max_selected = band->selected_count;
            }
            ctx->butterfly_total += worker8_count_pruned_butterflies(
                band->selected, band->selected_count, p->n, 0);
        }
        lo = hi;
    }
    ctx->work = (size_t *)malloc(ctx->max_selected * sizeof(*ctx->work));
    if (ctx->work == NULL) {
        free(mark);
        return 0;
    }
    free(mark);
    return 1;
}

static void worker8_destroy_context(worker8_pruned_context *ctx) {
    if (ctx == NULL) return;
    for (size_t i = 0; i < ctx->band_count; ++i) {
        free(ctx->bands[i].selected);
    }
    free(ctx->work);
    free(ctx->bands);
    free(ctx->bitrev);
    if (ctx->twiddle != NULL) fftw_free(ctx->twiddle);
    memset(ctx, 0, sizeof(*ctx));
}

static size_t worker8_partition(size_t *items, size_t count, unsigned bit) {
    size_t left = 0;
    size_t right = count;
    while (left < right) {
        if (((items[left] >> bit) & 1u) == 0u) {
            ++left;
        } else {
            --right;
            size_t temp = items[left];
            items[left] = items[right];
            items[right] = temp;
        }
    }
    return left;
}

/* Decimation-in-frequency radix-2 FFT with exact output pruning.  The
 * selected list contains natural-frequency indices.  DIF leaves results in
 * bit-reversed positions, which the reduction reads through ctx->bitrev. */
static void worker8_pruned_dif(fftw_complex *a, size_t n, size_t *selected,
                               size_t count, unsigned bit,
                               const worker8_pruned_context *ctx) {
    if (count == 0 || n <= 1) return;
    size_t step = ctx->n / n;
    for (size_t j = 0; j < n / 2; ++j) {
        fftw_complex u = a[j];
        fftw_complex v = a[j + n / 2];
        a[j] = u + v;
        a[j + n / 2] = (u - v) * ctx->twiddle[j * step];
    }
    size_t split = worker8_partition(selected, count, bit);
    worker8_pruned_dif(a, n / 2, selected, split, bit + 1, ctx);
    worker8_pruned_dif(a + n / 2, n / 2, selected + split,
                       count - split, bit + 1, ctx);
}

static void worker8_reduce_pruned_band(const dht_plan *p,
                                       const worker8_pruned_context *ctx,
                                       const worker8_pruned_band *band,
                                       const dht_complex *x, dht_complex *y) {
    fill_batch(p, band->n0, x);
    for (unsigned q = 0; q < p->terms; ++q) {
        memcpy(ctx->work, band->selected,
               band->selected_count * sizeof(*ctx->work));
        worker8_pruned_dif(p->scratch + (size_t)q * p->n, p->n, ctx->work,
                           band->selected_count, 0, ctx);
    }
    for (size_t m = band->lo; m < band->hi; ++m) {
        size_t partner = p->n - m;
        double yr = y[m].re;
        double yi = y[m].im;
        for (unsigned q = 0; q < p->terms; ++q) {
            const fftw_complex *row = p->scratch + (size_t)q * p->n;
            double ar = creal(row[ctx->bitrev[m]]);
            double ai = cimag(row[ctx->bitrev[m]]);
            double br = creal(row[ctx->bitrev[partner]]);
            double bi = cimag(row[ctx->bitrev[partner]]);
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

static int worker8_pruned_apply(const dht_plan *p,
                                const worker8_pruned_context *ctx,
                                const dht_complex *x, dht_complex *y) {
    if (p == NULL || ctx == NULL || x == NULL || y == NULL) return -1;
    for (size_t m = 0; m < p->n; ++m) {
        y[m].re = x[0].re;
        y[m].im = x[0].im;
    }
    add_zero_row(p, x, y);
    for (size_t i = 0; i < ctx->band_count; ++i) {
        worker8_reduce_pruned_band(p, ctx, &ctx->bands[i], x, y);
    }
    add_direct_rows(p, x, y);
    return 0;
}

static const char *worker8_mode_name(unsigned mode) {
    return mode == 0 ? "current-full-fftw" : "output-pruned-radix2";
}

#ifndef WORKER8_PRUNED_NO_MAIN
int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 4096;
    unsigned reps = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 9;
    unsigned warmups = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 2;
    unsigned threads = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 1;
    unsigned mode = argc > 5 ? (unsigned)strtoul(argv[5], NULL, 10) : 1;
    unsigned details = argc > 6 ? (unsigned)strtoul(argv[6], NULL, 10) : 0;
    if (n < 2 || reps == 0 || mode > 1 || worker8_log2_exact(n) == 0) {
        return 2;
    }
    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *y = (dht_complex *)malloc(n * sizeof(*y));
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    if (x == NULL || y == NULL || times == NULL) return 2;
    worker8_fill_input(x, n);

    double begin = worker8_now_seconds();
    dht_plan *p = dht_plan_create(n, 1e-13, threads);
    double plan_setup = worker8_now_seconds() - begin;
    if (p == NULL) return 2;
    worker8_pruned_context ctx;
    begin = worker8_now_seconds();
    if (!worker8_make_context(p, &ctx)) return 2;
    double context_setup = worker8_now_seconds() - begin;
    if (details != 0) {
        for (size_t i = 0; i < ctx.band_count; ++i) {
            const worker8_pruned_band *band = &ctx.bands[i];
            printf("band lo=%zu hi=%zu n0=%zu selected=%zu butterflies=%zu\n",
                   band->lo, band->hi, band->n0, band->selected_count,
                   worker8_count_pruned_butterflies(
                       band->selected, band->selected_count, n, 0));
        }
    }
    for (unsigned i = 0; i < warmups; ++i) {
        int status = mode == 0 ? dht_apply(p, x, y)
                               : worker8_pruned_apply(p, &ctx, x, y);
        if (status != 0) return 2;
    }
    for (unsigned i = 0; i < reps; ++i) {
        begin = worker8_now_seconds();
        int status = mode == 0 ? dht_apply(p, x, y)
                               : worker8_pruned_apply(p, &ctx, x, y);
        if (status != 0) return 2;
        times[i] = worker8_now_seconds() - begin;
    }
    double min_s = times[0], max_s = times[0];
    for (unsigned i = 1; i < reps; ++i) {
        if (times[i] < min_s) min_s = times[i];
        if (times[i] > max_s) max_s = times[i];
    }
    size_t pruned_bytes = ctx.band_count * sizeof(*ctx.bands) +
                          ctx.selected_total * sizeof(size_t) +
                          n * sizeof(*ctx.bitrev) +
                          n / 2 * sizeof(*ctx.twiddle) +
                          ctx.max_selected * sizeof(*ctx.work);
    printf("N=%zu reps=%u warmups=%u threads=%u mode=%s plan_setup_s=%.9f "
           "context_setup_s=%.9f median_s=%.9f min_s=%.9f max_s=%.9f "
           "active_bands=%zu selected_total=%zu butterfly_total=%zu "
           "full_butterflies=%zu plan_bytes=%zu pruned_bytes=%zu "
           "checksum=%.17g,%.17g\n",
           n, reps, warmups, threads, worker8_mode_name(mode), plan_setup,
           context_setup, worker8_median(times, reps), min_s, max_s,
           ctx.band_count, ctx.selected_total, ctx.butterfly_total,
           ctx.full_butterfly_total, dht_plan_bytes(p), pruned_bytes,
           y[n / 3].re, y[n / 3].im);
    worker8_destroy_context(&ctx);
    dht_plan_destroy(p);
    free(times);
    free(y);
    free(x);
    return 0;
}
#endif
