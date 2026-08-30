#include "../src/dht_asym.c"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

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

static void worker8_fill_prefix(const dht_plan *p, size_t n0,
                                const dht_complex *x) {
    for (unsigned q = 0; q < p->terms; ++q) {
        fftw_complex *row = p->scratch + (size_t)q * p->n;
        const double *w = p->weights + (size_t)q * p->n;
        memset(row, 0, n0 * sizeof(*row));
        for (size_t k = n0; k < p->n; ++k) {
            row[k] = (x[k].re * w[k]) + I * (x[k].im * w[k]);
        }
    }
}

static void worker8_reduce_block(const dht_plan *p, size_t lo, size_t hi,
                                 const double *scales, const dht_complex *x,
                                 dht_complex *y, int prefix) {
    double threshold = p->z0 * (double)p->n / (2.0 * M_PI);
    size_t raw_n0 = (size_t)ceil(threshold / (double)lo);
    size_t n0 = raw_n0 < p->n ? raw_n0 : p->n;
    if (n0 >= p->n) return;
    if (prefix) {
        worker8_fill_prefix(p, n0, x);
    } else {
        fill_batch(p, n0, x);
    }
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
            yr += scales[(size_t)q * p->n + m] * hr;
            yi += scales[(size_t)q * p->n + m] * hi_value;
        }
        y[m].re = yr;
        y[m].im = yi;
    }
}

static void worker8_reduce_block_mmajor(const dht_plan *p, size_t lo,
                                        size_t hi, const double *scales_m,
                                        const dht_complex *x, dht_complex *y,
                                        int prefix) {
    double threshold = p->z0 * (double)p->n / (2.0 * M_PI);
    size_t raw_n0 = (size_t)ceil(threshold / (double)lo);
    size_t n0 = raw_n0 < p->n ? raw_n0 : p->n;
    if (n0 >= p->n) return;
    if (prefix) {
        worker8_fill_prefix(p, n0, x);
    } else {
        fill_batch(p, n0, x);
    }
    fftw_execute(p->fft_plan);
    for (size_t m = lo; m < hi; ++m) {
        size_t partner = m == 0 ? 0 : p->n - m;
        double yr = y[m].re;
        double yi = y[m].im;
        const double *sm = scales_m + m * (size_t)p->terms;
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
            yr += sm[q] * hr;
            yi += sm[q] * hi_value;
        }
        y[m].re = yr;
        y[m].im = yi;
    }
}

static void worker8_init_fused(const dht_plan *p, const dht_complex *x,
                               dht_complex *y) {
    double sr = x[0].re, si = x[0].im;
    double cr = 0.0, ci = 0.0;
    for (size_t m = 0; m < p->n; ++m) {
        y[m].re = x[0].re;
        y[m].im = x[0].im;
        if (m != 0) {
            kahan_add(x[m].re, &sr, &cr);
            kahan_add(x[m].im, &si, &ci);
        }
    }
    y[0].re = sr;
    y[0].im = si;
}

static int worker8_apply_variant(const dht_plan *p, const dht_complex *x,
                                 dht_complex *y, const double *scales_m,
                                 int prefix, int mmajor, int fused) {
    if (p == NULL || x == NULL || y == NULL) return -1;
    if (fused) {
        worker8_init_fused(p, x, y);
    } else {
        for (size_t m = 0; m < p->n; ++m) {
            y[m].re = x[0].re;
            y[m].im = x[0].im;
        }
        add_zero_row(p, x, y);
    }
    size_t lo = 1;
    while (lo < p->n) {
        size_t hi = lo <= p->n / p->block_ratio
                        ? lo * p->block_ratio
                        : p->n;
        if (mmajor) {
            worker8_reduce_block_mmajor(p, lo, hi, scales_m, x, y, prefix);
        } else {
            worker8_reduce_block(p, lo, hi, p->scales, x, y, prefix);
        }
        lo = hi;
    }
    add_direct_rows(p, x, y);
    return 0;
}

typedef struct {
    double axes;
    double fill;
    double fft;
    double reduce;
    double direct;
    double total;
} worker8_phase_times;

static double worker8_median_field(const worker8_phase_times *a, unsigned n,
                                   unsigned field) {
    double *values = (double *)malloc((size_t)n * sizeof(*values));
    if (values == NULL) return NAN;
    for (unsigned i = 0; i < n; ++i) {
        switch (field) {
        case 0: values[i] = a[i].axes; break;
        case 1: values[i] = a[i].fill; break;
        case 2: values[i] = a[i].fft; break;
        case 3: values[i] = a[i].reduce; break;
        case 4: values[i] = a[i].direct; break;
        default: values[i] = a[i].total; break;
        }
    }
    double result = worker8_median(values, n);
    free(values);
    return result;
}

static int worker8_apply_profile(const dht_plan *p, const dht_complex *x,
                                 dht_complex *y, worker8_phase_times *out) {
    double t0 = worker8_now_seconds();
    for (size_t m = 0; m < p->n; ++m) {
        y[m].re = x[0].re;
        y[m].im = x[0].im;
    }
    add_zero_row(p, x, y);
    out->axes = worker8_now_seconds() - t0;
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
            double begin = worker8_now_seconds();
            fill_batch(p, n0, x);
            out->fill += worker8_now_seconds() - begin;
            begin = worker8_now_seconds();
            fftw_execute(p->fft_plan);
            out->fft += worker8_now_seconds() - begin;
            begin = worker8_now_seconds();
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
            out->reduce += worker8_now_seconds() - begin;
        }
        lo = hi;
    }
    double begin = worker8_now_seconds();
    add_direct_rows(p, x, y);
    out->direct = worker8_now_seconds() - begin;
    out->total = worker8_now_seconds() - t0;
    return 0;
}

static void worker8_make_mmajor(const dht_plan *p, double *scales_m) {
    for (size_t m = 0; m < p->n; ++m) {
        for (unsigned q = 0; q < p->terms; ++q) {
            scales_m[m * (size_t)p->terms + q] =
                p->scales[(size_t)q * p->n + m];
        }
    }
}

static const char *worker8_variant_name(unsigned choice) {
    switch (choice) {
    case 0: return "current";
    case 1: return "prefix-clear";
    case 2: return "mmajor-scales";
    case 3: return "prefix+mmajor";
    case 4: return "fused-axes";
    case 5: return "prefix+fused";
    case 6: return "phase-profile";
    default: return "unknown";
    }
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned reps = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 9;
    unsigned warmups = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 2;
    unsigned threads = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 1;
    unsigned choice = argc > 5 ? (unsigned)strtoul(argv[5], NULL, 10) : 0;
    if (n < 2 || reps == 0 || choice > 6) return 2;

    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *y = (dht_complex *)malloc(n * sizeof(*y));
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    if (x == NULL || y == NULL || times == NULL) return 2;
    worker8_fill_input(x, n);

    double begin_setup = worker8_now_seconds();
    dht_plan *p = dht_plan_create(n, 1e-13, threads);
    double setup = worker8_now_seconds() - begin_setup;
    if (p == NULL) return 2;

    int prefix = choice == 1 || choice == 3 || choice == 5;
    int mmajor = choice == 2 || choice == 3;
    int fused = choice == 4 || choice == 5;
    double extra_setup = 0.0;
    double *scales_m = NULL;
    if (mmajor) {
        scales_m = (double *)malloc((size_t)p->n * p->terms *
                                    sizeof(*scales_m));
        if (scales_m == NULL) return 2;
        double begin = worker8_now_seconds();
        worker8_make_mmajor(p, scales_m);
        extra_setup = worker8_now_seconds() - begin;
    }
    if (choice == 6) {
        worker8_phase_times *phase =
            (worker8_phase_times *)calloc(reps, sizeof(*phase));
        if (phase == NULL) return 2;
        for (unsigned i = 0; i < warmups; ++i) {
            if (worker8_apply_profile(p, x, y, &phase[0]) != 0) return 2;
        }
        for (unsigned i = 0; i < reps; ++i) {
            if (worker8_apply_profile(p, x, y, &phase[i]) != 0) return 2;
        }
        printf("N=%zu reps=%u warmups=%u threads=%u variant=phase-profile "
               "setup_s=%.9f median_total_s=%.9f median_axes_s=%.9f "
               "median_fill_s=%.9f median_fft_s=%.9f median_reduce_s=%.9f "
               "median_direct_s=%.9f direct=%zu plan_bytes=%zu "
               "checksum=%.17g,%.17g\n",
               n, reps, warmups, threads, setup,
               worker8_median_field(phase, reps, 5),
               worker8_median_field(phase, reps, 0),
               worker8_median_field(phase, reps, 1),
               worker8_median_field(phase, reps, 2),
               worker8_median_field(phase, reps, 3),
               worker8_median_field(phase, reps, 4), dht_direct_entries(p),
               dht_plan_bytes(p), y[n / 3].re, y[n / 3].im);
        free(phase);
        free(scales_m);
        dht_plan_destroy(p);
        free(times);
        free(y);
        free(x);
        return 0;
    }
    for (unsigned i = 0; i < warmups; ++i) {
        if (worker8_apply_variant(p, x, y, scales_m, prefix, mmajor, fused) !=
            0) return 2;
    }
    for (unsigned i = 0; i < reps; ++i) {
        double begin = worker8_now_seconds();
        if (worker8_apply_variant(p, x, y, scales_m, prefix, mmajor, fused) !=
            0) return 2;
        times[i] = worker8_now_seconds() - begin;
    }
    double min_s = times[0], max_s = times[0];
    for (unsigned i = 1; i < reps; ++i) {
        if (times[i] < min_s) min_s = times[i];
        if (times[i] > max_s) max_s = times[i];
    }
    printf("N=%zu reps=%u warmups=%u threads=%u variant=%s setup_s=%.9f "
           "extra_setup_s=%.9f median_s=%.9f min_s=%.9f max_s=%.9f "
           "direct=%zu plan_bytes=%zu extra_bytes=%zu checksum=%.17g,%.17g\n",
           n, reps, warmups, threads, worker8_variant_name(choice), setup,
           extra_setup, worker8_median(times, reps), min_s, max_s,
           dht_direct_entries(p), dht_plan_bytes(p),
           mmajor ? (size_t)p->n * p->terms * sizeof(double) : 0,
           y[n / 3].re, y[n / 3].im);
    free(scales_m);
    dht_plan_destroy(p);
    free(times);
    free(y);
    free(x);
    return 0;
}
