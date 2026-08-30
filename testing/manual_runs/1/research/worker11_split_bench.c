#include "worker11_split_impl.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    double axes;
    double fill;
    double fft;
    double reduce;
    double direct;
    double total;
} worker11_phase_times;

static uint64_t worker11_rng_state = UINT64_C(0x8f3c2d1e7a6b5948);

static uint64_t worker11_next_u64(void) {
    uint64_t x = worker11_rng_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    worker11_rng_state = x;
    return x * UINT64_C(2685821657736338717);
}

static double worker11_uniform_signed(void) {
    return 2.0 * (double)(worker11_next_u64() >> 11) * 0x1.0p-53 - 1.0;
}

static void worker11_fill_input(dht_complex *x, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        x[k].re = worker11_uniform_signed();
        x[k].im = worker11_uniform_signed();
    }
}

static double worker11_now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + 1e-9 * (double)ts.tv_nsec;
}

static double worker11_median(double *a, unsigned n) {
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

static double worker11_phase_median(const worker11_phase_times *a,
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
    double result = worker11_median(v, n);
    free(v);
    return result;
}

static void worker11_profile(unsigned profile, unsigned *terms, double *z0,
                             unsigned *ratio) {
    if (profile == 0) {
        *terms = 10;
        *z0 = 64.0;
        *ratio = 2;
    } else {
        *terms = 12;
        *z0 = 18.0;
        *ratio = 4;
    }
}

static size_t worker11_active_blocks(const dht_plan *p) {
    size_t count = 0;
    size_t lo = 1;
    while (lo < p->n) {
        size_t hi = lo <= p->n / p->block_ratio
                        ? lo * p->block_ratio
                        : p->n;
        double threshold = p->z0 * (double)p->n / (2.0 * M_PI);
        size_t raw_n0 = (size_t)ceil(threshold / (double)lo);
        if ((raw_n0 < p->n ? raw_n0 : p->n) < p->n) {
            ++count;
        }
        lo = hi;
    }
    return count;
}

static dht_plan *worker11_current_create(size_t n, unsigned profile,
                                         unsigned threads) {
    unsigned terms, ratio;
    double z0;
    worker11_profile(profile, &terms, &z0, &ratio);
    if (profile == 0) {
        return dht_plan_create(n, 1e-13, threads);
    }
    return dht_plan_create_profile_ex(n, 1e-13, terms, z0, threads, ratio);
}

static void worker11_current_apply_timed(const dht_plan *p,
                                         const dht_complex *x,
                                         dht_complex *y,
                                         worker11_phase_times *out) {
    double start = worker11_now_seconds();
    double begin = start;
    for (size_t m = 0; m < p->n; ++m) {
        y[m].re = x[0].re;
        y[m].im = x[0].im;
    }
    add_zero_row(p, x, y);
    out->axes = worker11_now_seconds() - begin;
    out->fill = 0.0;
    out->fft = 0.0;
    out->reduce = 0.0;

    size_t lo = 1;
    while (lo < p->n) {
        size_t hi = lo <= p->n / p->block_ratio
                        ? lo * p->block_ratio
                        : p->n;
        double threshold = p->z0 * (double)p->n / (2.0 * M_PI);
        size_t raw_n0 = (size_t)ceil(threshold / (double)lo);
        size_t n0 = raw_n0 < p->n ? raw_n0 : p->n;
        if (n0 < p->n) {
            begin = worker11_now_seconds();
            fill_batch(p, n0, x);
            out->fill += worker11_now_seconds() - begin;
            begin = worker11_now_seconds();
            fftw_execute(p->fft_plan);
            out->fft += worker11_now_seconds() - begin;
            begin = worker11_now_seconds();
            for (size_t m = lo; m < hi; ++m) {
                size_t partner = m == 0 ? 0 : p->n - m;
                double yr = y[m].re;
                double yi = y[m].im;
                for (unsigned q = 0; q < p->terms; ++q) {
                    const fftw_complex *row =
                        p->scratch + (size_t)q * p->n;
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
            out->reduce += worker11_now_seconds() - begin;
        }
        lo = hi;
    }
    begin = worker11_now_seconds();
    add_direct_rows(p, x, y);
    out->direct = worker11_now_seconds() - begin;
    out->total = worker11_now_seconds() - start;
}

static void worker11_split_apply_timed(const worker11_split_plan *s,
                                       const dht_complex *x, dht_complex *y,
                                       worker11_phase_times *out) {
    const dht_plan *p = s->p;
    double start = worker11_now_seconds();
    double begin = start;
    for (size_t m = 0; m < p->n; ++m) {
        y[m].re = x[0].re;
        y[m].im = x[0].im;
    }
    add_zero_row(p, x, y);
    out->axes = worker11_now_seconds() - begin;
    out->fill = 0.0;
    out->fft = 0.0;
    out->reduce = 0.0;

    size_t lo = 1;
    while (lo < p->n) {
        size_t hi = lo <= p->n / p->block_ratio
                        ? lo * p->block_ratio
                        : p->n;
        double threshold = p->z0 * (double)p->n / (2.0 * M_PI);
        size_t raw_n0 = (size_t)ceil(threshold / (double)lo);
        size_t n0 = raw_n0 < p->n ? raw_n0 : p->n;
        if (n0 < p->n) {
            begin = worker11_now_seconds();
            worker11_split_fill(s, n0, x);
            out->fill += worker11_now_seconds() - begin;
            begin = worker11_now_seconds();
            fftw_execute(s->real_plan);
            fftw_execute(s->imag_plan);
            out->fft += worker11_now_seconds() - begin;
            begin = worker11_now_seconds();
            for (size_t m = lo; m < hi; ++m) {
                double yr = y[m].re;
                double yi = y[m].im;
                for (unsigned q = 0; q < p->terms; ++q) {
                    double cr, ci, sr, si;
                    worker11_split_spectrum(s, m, q, &cr, &ci, &sr, &si);
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
            out->reduce += worker11_now_seconds() - begin;
        }
        lo = hi;
    }
    begin = worker11_now_seconds();
    add_direct_rows(p, x, y);
    out->direct = worker11_now_seconds() - begin;
    out->total = worker11_now_seconds() - start;
}

static int worker11_run(size_t n, unsigned reps, unsigned warmups,
                        unsigned threads, unsigned profile, int split) {
    unsigned terms, ratio;
    double z0;
    worker11_profile(profile, &terms, &z0, &ratio);
    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *y = (dht_complex *)malloc(n * sizeof(*y));
    worker11_phase_times *times =
        (worker11_phase_times *)calloc(reps, sizeof(*times));
    double *raw_times = (double *)malloc((size_t)reps * sizeof(*raw_times));
    if (x == NULL || y == NULL || times == NULL || raw_times == NULL) {
        free(x); free(y); free(times); free(raw_times);
        return 2;
    }
    worker11_fill_input(x, n);

    double setup_begin = worker11_now_seconds();
    dht_plan *current = NULL;
    worker11_split_plan *split_plan = NULL;
    if (split) {
        split_plan = worker11_split_create(n, 1e-13, terms, z0, threads,
                                           ratio);
    } else {
        current = worker11_current_create(n, profile, threads);
    }
    double setup = worker11_now_seconds() - setup_begin;
    if ((split && split_plan == NULL) || (!split && current == NULL)) {
        worker11_split_destroy(split_plan);
        dht_plan_destroy(current);
        free(x); free(y); free(times); free(raw_times);
        return 2;
    }
    for (unsigned i = 0; i < warmups; ++i) {
        if (split) {
            worker11_split_apply(split_plan, x, y);
        } else {
            dht_apply(current, x, y);
        }
    }
    for (unsigned i = 0; i < reps; ++i) {
        double begin = worker11_now_seconds();
        if (split) {
            worker11_split_apply(split_plan, x, y);
        } else {
            dht_apply(current, x, y);
        }
        raw_times[i] = worker11_now_seconds() - begin;
    }
    for (unsigned i = 0; i < reps; ++i) {
        if (split) {
            worker11_split_apply_timed(split_plan, x, y, &times[i]);
        } else {
            worker11_current_apply_timed(current, x, y, &times[i]);
        }
    }

    size_t plan_bytes = split ? worker11_split_bytes(split_plan)
                              : dht_plan_bytes(current);
    const dht_plan *p = split ? split_plan->p : current;
    double min_s = times[0].total;
    double max_s = times[0].total;
    double min_apply_s = raw_times[0];
    double max_apply_s = raw_times[0];
    for (unsigned i = 1; i < reps; ++i) {
        if (times[i].total < min_s) min_s = times[i].total;
        if (times[i].total > max_s) max_s = times[i].total;
        if (raw_times[i] < min_apply_s) min_apply_s = raw_times[i];
        if (raw_times[i] > max_apply_s) max_apply_s = raw_times[i];
    }
    printf("worker11 mode=%s profile=%u N=%zu reps=%u warmups=%u threads=%u "
           "terms=%u z0=%.1f ratio=%u fft_1d_transforms=%zu setup_s=%.9f "
           "median_apply_s=%.9f min_apply_s=%.9f max_apply_s=%.9f "
           "median_profile_s=%.9f min_profile_s=%.9f max_profile_s=%.9f "
           "axes_s=%.9f fill_s=%.9f "
           "fft_s=%.9f reduce_s=%.9f direct_s=%.9f direct=%zu plan_bytes=%zu "
           "checksum=%.17g,%.17g\n",
           split ? "split-r2c" : "complex", profile, n, reps, warmups,
           threads, p->terms, p->z0, p->block_ratio,
           worker11_active_blocks(p) * (size_t)p->terms *
               (split ? 2u : 1u),
           setup, worker11_median(raw_times, reps), min_apply_s, max_apply_s,
           worker11_phase_median(times, reps, 5),
           min_s, max_s,
           worker11_phase_median(times, reps, 0),
           worker11_phase_median(times, reps, 1),
           worker11_phase_median(times, reps, 2),
           worker11_phase_median(times, reps, 3),
           worker11_phase_median(times, reps, 4), p->direct_count, plan_bytes,
           y[n / 3].re, y[n / 3].im);

    if (split) {
        worker11_split_destroy(split_plan);
    } else {
        dht_plan_destroy(current);
    }
    free(x); free(y); free(times); free(raw_times);
    return 0;
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned reps = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 9;
    unsigned warmups = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 2;
    unsigned threads = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 1;
    unsigned profile = argc > 5 ? (unsigned)strtoul(argv[5], NULL, 10) : 0;
    int split = argc > 6 ? atoi(argv[6]) : 0;
    if (n < 2 || reps == 0 || profile > 1 || (split != 0 && split != 1)) {
        return 2;
    }
    return worker11_run(n, reps, warmups, threads, profile, split);
}
