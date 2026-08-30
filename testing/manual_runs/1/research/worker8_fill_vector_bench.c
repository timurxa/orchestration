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

static void worker8_fill_split(const dht_plan *p, size_t n0,
                               const dht_complex *x) {
    size_t total = (size_t)p->terms * p->n;
    memset(p->scratch, 0, total * sizeof(*p->scratch));
    for (unsigned q = 0; q < p->terms; ++q) {
        fftw_complex *row = p->scratch + (size_t)q * p->n;
        const double *w = p->weights + (size_t)q * p->n;
#pragma clang loop vectorize(enable)
        for (size_t k = n0; k < p->n; ++k) {
            double weight = w[k];
            double real = x[k].re * weight;
            double imag = x[k].im * weight;
            row[k] = real + I * imag;
        }
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

static double worker8_measure(const dht_plan *p, const dht_complex *x,
                              int split, unsigned reps, unsigned warmups) {
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    if (times == NULL) return NAN;
    for (unsigned warm = 0; warm < warmups; ++warm) {
        size_t lo = 1;
        while (lo < p->n) {
            size_t hi = lo <= p->n / p->block_ratio
                            ? lo * p->block_ratio
                            : p->n;
            double threshold = p->z0 * (double)p->n / (2.0 * M_PI);
            size_t n0 = (size_t)ceil(threshold / (double)lo);
            if (n0 < p->n) {
                if (split) worker8_fill_split(p, n0, x);
                else fill_batch(p, n0, x);
            }
            lo = hi;
        }
    }
    for (unsigned rep = 0; rep < reps; ++rep) {
        double begin = worker8_now_seconds();
        size_t lo = 1;
        while (lo < p->n) {
            size_t hi = lo <= p->n / p->block_ratio
                            ? lo * p->block_ratio
                            : p->n;
            double threshold = p->z0 * (double)p->n / (2.0 * M_PI);
            size_t n0 = (size_t)ceil(threshold / (double)lo);
            if (n0 < p->n) {
                if (split) worker8_fill_split(p, n0, x);
                else fill_batch(p, n0, x);
            }
            lo = hi;
        }
        times[rep] = worker8_now_seconds() - begin;
    }
    double result = worker8_median(times, reps);
    volatile double sink = creal(p->scratch[p->n / 3]);
    (void)sink;
    free(times);
    return result;
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned reps = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 11;
    unsigned warmups = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 3;
    unsigned threads = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 1;
    if (n < 2 || reps == 0) return 2;
    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    if (x == NULL) return 2;
    worker8_fill_input(x, n);
    dht_plan *p = dht_plan_create(n, 1e-13, threads);
    if (p == NULL) return 2;
    double current = worker8_measure(p, x, 0, reps, warmups);
    double split = worker8_measure(p, x, 1, reps, warmups);
    printf("N=%zu reps=%u warmups=%u threads=%u current_fill_s=%.9f "
           "split_vector_fill_s=%.9f ratio=%.6f checksum=%.17g,%.17g\n",
           n, reps, warmups, threads, current, split, split / current,
           creal(p->scratch[n / 3]), cimag(p->scratch[n / 3]));
    dht_plan_destroy(p);
    free(x);
    return 0;
}
