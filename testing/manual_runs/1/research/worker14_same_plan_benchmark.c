#include "../src/dht.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

int worker14_apply_serial_reference(const dht_plan *, const dht_complex *,
                                    dht_complex *);

typedef int (*worker14_apply_fn)(const dht_plan *, const dht_complex *,
                                 dht_complex *);

static uint64_t rng_state = UINT64_C(0x8f3c2d1e7a6b5948);

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

static void fill_input(dht_complex *x, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        x[k].re = uniform_signed();
        x[k].im = uniform_signed();
    }
}

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

static int call_parallel(const dht_plan *p, const dht_complex *x,
                         dht_complex *y) {
    return dht_apply(p, x, y);
}

static double measure(worker14_apply_fn fn, const dht_plan *p,
                      const dht_complex *x, dht_complex *y, unsigned reps,
                      unsigned warmups) {
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    if (times == NULL) return NAN;
    for (unsigned i = 0; i < warmups; ++i) {
        if (fn(p, x, y) != 0) return NAN;
    }
    for (unsigned i = 0; i < reps; ++i) {
        double begin = now_seconds();
        if (fn(p, x, y) != 0) return NAN;
        times[i] = now_seconds() - begin;
    }
    double value = median(times, reps);
    free(times);
    return value;
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned threads = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 10;
    unsigned reps = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 21;
    unsigned warmups = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 5;
    unsigned ratio = argc > 5 ? (unsigned)strtoul(argv[5], NULL, 10) : 2;
    if (n < 2 || reps == 0 || ratio < 2) return 2;
    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *y = (dht_complex *)malloc(n * sizeof(*y));
    if (x == NULL || y == NULL) return 2;
    fill_input(x, n);
    dht_plan *p = dht_plan_create_profile_ex(n, 1e-13, 10, 64.0, threads,
                                              ratio);
    if (p == NULL) return 2;
    double serial = measure(worker14_apply_serial_reference, p, x, y, reps,
                            warmups);
    double parallel = measure(call_parallel, p, x, y, reps, warmups);
    printf("N=%zu threads=%u ratio=%u reps=%u warmups=%u direct=%zu "
           "plan_bytes=%zu serial_median_s=%.9f parallel_median_s=%.9f "
           "speedup=%.6f\n",
           n, threads, ratio, reps, warmups, dht_direct_entries(p),
           dht_plan_bytes(p), serial, parallel, serial / parallel);
    dht_plan_destroy(p);
    free(y);
    free(x);
    return 0;
}
