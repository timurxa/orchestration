#include <complex.h>
#include <fftw3.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

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

static void fill(fftw_complex *a, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        double t = (double)i;
        a[i] = cos(0.00017 * t) + I * sin(0.00031 * t);
    }
}

static double run_many(fftw_plan plan, fftw_complex *a, size_t count,
                       unsigned reps, unsigned warmups) {
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    if (times == NULL) return NAN;
    for (unsigned i = 0; i < warmups; ++i) fftw_execute(plan);
    for (unsigned i = 0; i < reps; ++i) {
        double begin = now_seconds();
        fftw_execute(plan);
        times[i] = now_seconds() - begin;
    }
    double result = median(times, reps);
    volatile double sink = creal(a[count / 3]);
    (void)sink;
    free(times);
    return result;
}

static double run_individual(fftw_plan *plans, fftw_complex *a, size_t count,
                             unsigned terms, unsigned reps, unsigned warmups) {
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    if (times == NULL) return NAN;
    for (unsigned i = 0; i < warmups; ++i) {
        for (unsigned q = 0; q < terms; ++q) fftw_execute(plans[q]);
    }
    for (unsigned i = 0; i < reps; ++i) {
        double begin = now_seconds();
        for (unsigned q = 0; q < terms; ++q) fftw_execute(plans[q]);
        times[i] = now_seconds() - begin;
    }
    double result = median(times, reps);
    volatile double sink = creal(a[count / 3]);
    (void)sink;
    free(times);
    return result;
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned terms = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 10;
    unsigned threads = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 1;
    unsigned reps = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 9;
    unsigned warmups = argc > 5 ? (unsigned)strtoul(argv[5], NULL, 10) : 2;
    unsigned layout = argc > 6 ? (unsigned)strtoul(argv[6], NULL, 10) : 0;
    unsigned flag_code = argc > 7 ? (unsigned)strtoul(argv[7], NULL, 10) : 0;
    if (n == 0 || terms == 0 || reps == 0) return 2;
    unsigned flags = flag_code == 1 ? FFTW_ESTIMATE
                                    : (flag_code == 2 ? FFTW_PATIENT
                                                      : FFTW_MEASURE);

    size_t count = n * (size_t)terms;
    fftw_complex *a = (fftw_complex *)fftw_malloc(count * sizeof(*a));
    if (a == NULL) return 2;
    fill(a, count);

    fftw_init_threads();
    fftw_plan_with_nthreads((int)threads);
    int nn = (int)n;
    int howmany = (int)terms;
    double many_begin = now_seconds();
    fftw_plan many = fftw_plan_many_dft(1, &nn, howmany, a, NULL, 1, nn, a,
                                        NULL, 1, nn, FFTW_BACKWARD,
                                        flags);
    double many_setup_s = now_seconds() - many_begin;
    if (layout != 0) {
        fftw_destroy_plan(many);
        many = fftw_plan_many_dft(1, &nn, howmany, a, NULL, (int)terms, 1,
                                  a, NULL, (int)terms, 1, FFTW_BACKWARD,
                                  flags);
    }
    if (many == NULL) return 2;
    if (layout != 0) {
        fill(a, count);
        double many_s = run_many(many, a, count, reps, warmups);
        printf("N=%zu terms=%u threads=%u flag=%u layout=strided many_setup_s=%.9f many_median_s=%.9f checksum=%.17g\n",
               n, terms, threads, flag_code, many_setup_s, many_s,
               creal(a[count / 3]));
        fftw_destroy_plan(many);
        fftw_free(a);
        fftw_cleanup_threads();
        return 0;
    }
    fftw_plan *individual =
        (fftw_plan *)calloc(terms, sizeof(*individual));
    if (individual == NULL) return 2;
    double individual_begin = now_seconds();
    for (unsigned q = 0; q < terms; ++q) {
        individual[q] = fftw_plan_dft_1d(
            nn, a + (size_t)q * n, a + (size_t)q * n, FFTW_BACKWARD,
            flags);
        if (individual[q] == NULL) return 2;
    }
    double individual_setup_s = now_seconds() - individual_begin;

    fill(a, count);
    double many_s = run_many(many, a, count, reps, warmups);
    fill(a, count);
    double individual_s =
        run_individual(individual, a, count, terms, reps, warmups);
    printf("N=%zu terms=%u threads=%u flag=%u many_setup_s=%.9f individual_setup_s=%.9f many_median_s=%.9f individual_median_s=%.9f individual_over_many=%.4f checksum=%.17g\n",
           n, terms, threads, flag_code, many_setup_s, individual_setup_s,
           many_s, individual_s, individual_s / many_s, creal(a[count / 3]));

    for (unsigned q = 0; q < terms; ++q) fftw_destroy_plan(individual[q]);
    free(individual);
    fftw_destroy_plan(many);
    fftw_free(a);
    fftw_cleanup_threads();
    return 0;
}
