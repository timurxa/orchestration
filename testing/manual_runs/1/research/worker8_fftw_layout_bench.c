#include <complex.h>
#include <fftw3.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

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

static void worker8_fill(fftw_complex *a, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        double t = (double)i;
        a[i] = cos(0.00017 * t) + I * sin(0.00031 * t);
    }
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned terms = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 10;
    unsigned reps = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 9;
    unsigned warmups = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 2;
    unsigned threads = argc > 5 ? (unsigned)strtoul(argv[5], NULL, 10) : 1;
    unsigned layout = argc > 6 ? (unsigned)strtoul(argv[6], NULL, 10) : 0;
    unsigned flags_choice = argc > 7 ? (unsigned)strtoul(argv[7], NULL, 10) : 1;
    if (n < 2 || terms == 0 || reps == 0 || layout > 2 || flags_choice > 1) {
        return 2;
    }
    size_t count = n * (size_t)terms;
    fftw_complex *a = (fftw_complex *)fftw_malloc(count * sizeof(*a));
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    if (a == NULL || times == NULL) return 2;
    worker8_fill(a, count);
    fftw_init_threads();
    fftw_plan_with_nthreads((int)threads);
    unsigned flags = flags_choice == 0 ? FFTW_ESTIMATE : FFTW_MEASURE;
    int nn = (int)n;
    int howmany = (int)terms;
    double begin = worker8_now_seconds();
    fftw_plan plan = NULL;
    if (layout == 0) {
        plan = fftw_plan_many_dft(1, &nn, howmany, a, NULL, 1, nn, a, NULL, 1,
                                  nn, FFTW_BACKWARD, flags);
    } else if (layout == 1) {
        plan = fftw_plan_many_dft(1, &nn, howmany, a, NULL, (int)terms, 1, a,
                                  NULL, (int)terms, 1, FFTW_BACKWARD, flags);
    } else {
        plan = fftw_plan_dft_1d(nn, a, a, FFTW_BACKWARD, flags);
    }
    double setup = worker8_now_seconds() - begin;
    if (plan == NULL) return 2;
    for (unsigned i = 0; i < warmups; ++i) {
        if (layout == 2) {
            for (unsigned q = 0; q < terms; ++q) {
                fftw_execute_dft(plan, a + (size_t)q * n,
                                 a + (size_t)q * n);
            }
        } else {
            fftw_execute(plan);
        }
    }
    for (unsigned i = 0; i < reps; ++i) {
        double start = worker8_now_seconds();
        if (layout == 2) {
            for (unsigned q = 0; q < terms; ++q) {
                fftw_execute_dft(plan, a + (size_t)q * n,
                                 a + (size_t)q * n);
            }
        } else {
            fftw_execute(plan);
        }
        times[i] = worker8_now_seconds() - start;
    }
    double min_s = times[0], max_s = times[0];
    for (unsigned i = 1; i < reps; ++i) {
        if (times[i] < min_s) min_s = times[i];
        if (times[i] > max_s) max_s = times[i];
    }
    const char *layout_name = layout == 0 ? "qmajor-contiguous"
                             : layout == 1 ? "mmajor-strided" : "individual";
    printf("N=%zu terms=%u reps=%u warmups=%u threads=%u layout=%s flags=%s "
           "setup_s=%.9f median_s=%.9f min_s=%.9f max_s=%.9f "
           "checksum=%.17g,%.17g\n",
           n, terms, reps, warmups, threads, layout_name,
           flags_choice == 0 ? "estimate" : "measure", setup,
           worker8_median(times, reps), min_s, max_s, creal(a[count / 3]),
           cimag(a[count / 3]));
    fftw_destroy_plan(plan);
    fftw_free(a);
    free(times);
    return 0;
}
