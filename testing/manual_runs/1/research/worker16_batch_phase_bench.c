/* Research-only phase timing for worker16_batch_impl.c. */
#include "worker16_batch_impl.c"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

typedef struct {
    double axes;
    double fill;
    double fft;
    double reduce;
    double direct;
    double total;
} worker16_phase_times;

static uint64_t worker16_rng_state = UINT64_C(0x8f3c2d1e7a6b5948);

static uint64_t worker16_next_u64(void) {
    uint64_t x = worker16_rng_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    worker16_rng_state = x;
    return x * UINT64_C(2685821657736338717);
}

static void worker16_fill_input(dht_complex *x, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        x[k].re = 2.0 * (double)(worker16_next_u64() >> 11) * 0x1.0p-53 -
                  1.0;
        x[k].im = 2.0 * (double)(worker16_next_u64() >> 11) * 0x1.0p-53 -
                  1.0;
    }
}

static double worker16_now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + 1e-9 * (double)ts.tv_nsec;
}

static double worker16_median(double *a, unsigned n) {
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

static double worker16_phase_median(const worker16_phase_times *a,
                                    unsigned n, unsigned field) {
    double *v = (double *)malloc((size_t)n * sizeof(*v));
    if (v == NULL) {
        return NAN;
    }
    for (unsigned i = 0; i < n; ++i) {
        switch (field) {
        case 0: v[i] = a[i].axes; break;
        case 1: v[i] = a[i].fill; break;
        case 2: v[i] = a[i].fft; break;
        case 3: v[i] = a[i].reduce; break;
        case 4: v[i] = a[i].direct; break;
        default: v[i] = a[i].total; break;
        }
    }
    double result = worker16_median(v, n);
    free(v);
    return result;
}

static void worker16_apply_timed(const worker16_batch_plan *s,
                                 const dht_complex *x, dht_complex *y,
                                 worker16_phase_times *out) {
    const dht_plan *p = &s->base;
    double start = worker16_now_seconds();
    double begin = start;
    for (size_t m = 0; m < p->n; ++m) {
        y[m].re = x[0].re;
        y[m].im = x[0].im;
    }
    add_zero_row(p, x, y);
    out->axes = worker16_now_seconds() - begin;

    begin = worker16_now_seconds();
    worker16_fill_all(s, x);
    out->fill = worker16_now_seconds() - begin;

    begin = worker16_now_seconds();
    if (s->batch_plan != NULL) {
        fftw_execute(s->batch_plan);
    }
    out->fft = worker16_now_seconds() - begin;

    begin = worker16_now_seconds();
    for (size_t b = 0; b < s->band_count; ++b) {
        worker16_assemble_band(s, b, y);
    }
    out->reduce = worker16_now_seconds() - begin;

    begin = worker16_now_seconds();
    add_direct_rows(p, x, y);
    out->direct = worker16_now_seconds() - begin;
    out->total = worker16_now_seconds() - start;
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned reps = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 15;
    unsigned warmups = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 5;
    unsigned threads = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 10;
    unsigned profile = argc > 5 ? (unsigned)strtoul(argv[5], NULL, 10) : 0;
    unsigned terms = profile == 0 ? 11u : 12u;
    double cutoff = profile == 0 ? 23.0 : 18.0;
    unsigned ratio = 4u;
    if (n < 2 || reps == 0 || profile > 1) {
        return 2;
    }

    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *y = (dht_complex *)malloc(n * sizeof(*y));
    worker16_phase_times *times =
        (worker16_phase_times *)calloc(reps, sizeof(*times));
    if (x == NULL || y == NULL || times == NULL) {
        free(x); free(y); free(times);
        return 2;
    }
    worker16_fill_input(x, n);

    double begin = worker16_now_seconds();
    worker16_batch_plan *s = worker16_create_profile(
        n, 1e-13, terms, cutoff, threads, ratio);
    double setup = worker16_now_seconds() - begin;
    if (s == NULL) {
        free(x); free(y); free(times);
        return 2;
    }
    for (unsigned i = 0; i < warmups; ++i) {
        worker16_apply_timed(s, x, y, &times[0]);
    }
    for (unsigned i = 0; i < reps; ++i) {
        worker16_apply_timed(s, x, y, &times[i]);
    }
    double min_s = times[0].total;
    double max_s = times[0].total;
    for (unsigned i = 1; i < reps; ++i) {
        if (times[i].total < min_s) min_s = times[i].total;
        if (times[i].total > max_s) max_s = times[i].total;
    }
    printf("worker16 profile=%u N=%zu reps=%u warmups=%u threads=%u "
           "terms=%u z0=%.1f ratio=%u active_bands=%zu fft_rows=%zu "
           "setup_s=%.9f median_s=%.9f min_s=%.9f max_s=%.9f "
           "axes_s=%.9f fill_s=%.9f fft_s=%.9f reduce_s=%.9f "
           "direct_s=%.9f direct=%zu scratch_bytes=%zu plan_bytes=%zu "
           "checksum=%.17g,%.17g\n",
           profile, n, reps, warmups, threads, terms, cutoff, ratio,
           s->band_count, s->fft_rows, setup,
           worker16_phase_median(times, reps, 5), min_s, max_s,
           worker16_phase_median(times, reps, 0),
           worker16_phase_median(times, reps, 1),
           worker16_phase_median(times, reps, 2),
           worker16_phase_median(times, reps, 3),
           worker16_phase_median(times, reps, 4), s->base.direct_count,
           worker16_batch_scratch_bytes(&s->base),
           dht_plan_bytes(&s->base), y[n / 3].re, y[n / 3].im);
    worker16_release_batch(s);
    worker16_release_base(&s->base);
    free(s);
    free(x); free(y); free(times);
    return 0;
}
