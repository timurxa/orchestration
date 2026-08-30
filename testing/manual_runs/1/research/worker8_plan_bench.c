#include <complex.h>
#include <fftw3.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static unsigned worker8_plan_flags = FFTW_MEASURE;

static fftw_plan worker8_plan_many_dft(
    int rank, const int *n, int howmany, fftw_complex *in,
    const int *inembed, int istride, int idist, fftw_complex *out,
    const int *onembed, int ostride, int odist, int sign, unsigned flags) {
    (void)flags;
    return fftw_plan_many_dft(rank, n, howmany, in, inembed, istride, idist,
                              out, onembed, ostride, odist, sign,
                              worker8_plan_flags);
}

#define fftw_plan_many_dft worker8_plan_many_dft
#include "../src/dht_asym.c"
#undef fftw_plan_many_dft

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

static const char *worker8_flag_name(unsigned choice) {
    switch (choice) {
    case 0: return "estimate";
    case 1: return "measure";
    case 2: return "patient";
    case 3: return "exhaustive";
    default: return "unknown";
    }
}

static unsigned worker8_flag_value(unsigned choice) {
    switch (choice) {
    case 0: return FFTW_ESTIMATE;
    case 1: return FFTW_MEASURE;
    case 2: return FFTW_PATIENT;
    case 3: return FFTW_EXHAUSTIVE;
    default: return FFTW_MEASURE;
    }
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned reps = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 9;
    unsigned warmups = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 2;
    unsigned threads = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 1;
    unsigned choice = argc > 5 ? (unsigned)strtoul(argv[5], NULL, 10) : 1;
    if (n < 2 || reps == 0 || choice > 3) return 2;

    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *y = (dht_complex *)malloc(n * sizeof(*y));
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    if (x == NULL || y == NULL || times == NULL) return 2;
    worker8_fill_input(x, n);

    worker8_plan_flags = worker8_flag_value(choice);
    double begin_setup = worker8_now_seconds();
    dht_plan *p = dht_plan_create(n, 1e-13, threads);
    double setup = worker8_now_seconds() - begin_setup;
    if (p == NULL) return 2;
    for (unsigned i = 0; i < warmups; ++i) {
        if (dht_apply(p, x, y) != 0) return 2;
    }
    for (unsigned i = 0; i < reps; ++i) {
        double begin = worker8_now_seconds();
        if (dht_apply(p, x, y) != 0) return 2;
        times[i] = worker8_now_seconds() - begin;
    }
    double min_s = times[0], max_s = times[0];
    for (unsigned i = 1; i < reps; ++i) {
        if (times[i] < min_s) min_s = times[i];
        if (times[i] > max_s) max_s = times[i];
    }
    printf("N=%zu reps=%u warmups=%u threads=%u flags=%s setup_s=%.9f "
           "median_s=%.9f min_s=%.9f max_s=%.9f direct=%zu "
           "plan_bytes=%zu checksum=%.17g,%.17g\n",
           n, reps, warmups, threads, worker8_flag_name(choice), setup,
           worker8_median(times, reps), min_s, max_s, dht_direct_entries(p),
           dht_plan_bytes(p), y[n / 3].re, y[n / 3].im);
    dht_plan_destroy(p);
    free(times);
    free(y);
    free(x);
    return 0;
}
