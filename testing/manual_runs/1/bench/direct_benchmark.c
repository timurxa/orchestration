#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    double re;
    double im;
} complex_pair;

static uint64_t state = UINT64_C(0x8f3c2d1e7a6b5948);

static uint64_t next_u64(void) {
    uint64_t x = state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    state = x;
    return x * UINT64_C(2685821657736338717);
}

static double uniform_signed(void) {
    return 2.0 * (double)(next_u64() >> 11) * 0x1.0p-53 - 1.0;
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

static void fill_input(complex_pair *x, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        x[k].re = uniform_signed();
        x[k].im = uniform_signed();
    }
}

static void direct_apply(size_t n, const complex_pair *x, complex_pair *y) {
    double c = 2.0 * M_PI / (double)n;
    for (size_t m = 0; m < n; ++m) {
        double sr = 0.0, si = 0.0;
        for (size_t k = 0; k < n; ++k) {
            double a = j0(c * (double)m * (double)k);
            sr += a * x[k].re;
            si += a * x[k].im;
        }
        y[m].re = sr;
        y[m].im = si;
    }
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 512;
    unsigned reps = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 5;
    unsigned warmups = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 1;
    if (n == 0 || reps == 0) return 2;
    complex_pair *x = (complex_pair *)malloc(n * sizeof(*x));
    complex_pair *y = (complex_pair *)malloc(n * sizeof(*y));
    double *times = (double *)malloc(reps * sizeof(*times));
    if (x == NULL || y == NULL || times == NULL) return 2;
    fill_input(x, n);
    for (unsigned i = 0; i < warmups; ++i) direct_apply(n, x, y);
    for (unsigned i = 0; i < reps; ++i) {
        double begin = now_seconds();
        direct_apply(n, x, y);
        times[i] = now_seconds() - begin;
    }
    double min = times[0], max = times[0];
    for (unsigned i = 1; i < reps; ++i) {
        if (times[i] < min) min = times[i];
        if (times[i] > max) max = times[i];
    }
    printf("direct_j0,N=%zu,reps=%u,warmups=%u,median_s=%.9f,min_s=%.9f,max_s=%.9f,checksum=%.17g,%.17g\n",
           n, reps, warmups, median(times, reps), min, max, y[n / 3].re,
           y[n / 3].im);
    free(times);
    free(y);
    free(x);
    return 0;
}
