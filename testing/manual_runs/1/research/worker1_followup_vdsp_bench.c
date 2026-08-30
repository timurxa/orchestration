#include <Accelerate/Accelerate.h>
#include <math.h>
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

static void fill(double *re, double *im, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        double t = (double)i;
        re[i] = cos(0.00017 * t);
        im[i] = sin(0.00031 * t);
    }
}

static void run_zip(FFTSetupD setup, double *re, double *im, size_t n,
                    unsigned terms, unsigned log2n, int with_buffer,
                    DSPDoubleSplitComplex *buffer) {
    DSPDoubleSplitComplex z = {re, im};
    const double scale = (double)n;
    for (unsigned q = 0; q < terms; ++q) {
        DSPDoubleSplitComplex row = {z.realp + (size_t)q * n,
                                     z.imagp + (size_t)q * n};
        if (with_buffer) {
            vDSP_fft_ziptD(setup, &row, 1, buffer, log2n, FFT_INVERSE);
        } else {
            vDSP_fft_zipD(setup, &row, 1, log2n, FFT_INVERSE);
        }
        vDSP_vsmulD(row.realp, 1, &scale, row.realp, 1, n);
        vDSP_vsmulD(row.imagp, 1, &scale, row.imagp, 1, n);
    }
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned terms = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 10;
    unsigned reps = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 11;
    unsigned warmups = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 3;
    unsigned with_buffer = argc > 5 ? (unsigned)strtoul(argv[5], NULL, 10) : 0;
    if (n == 0 || terms == 0 || reps == 0 || (n & (n - 1)) != 0) return 2;

    unsigned log2n = 0;
    for (size_t v = n; v > 1; v >>= 1) ++log2n;
    size_t count = n * (size_t)terms;
    double *re = (double *)aligned_alloc(64, count * sizeof(*re));
    double *im = (double *)aligned_alloc(64, count * sizeof(*im));
    double *br = (double *)aligned_alloc(64, 2048 * sizeof(*br));
    double *bi = (double *)aligned_alloc(64, 2048 * sizeof(*bi));
    if (re == NULL || im == NULL || br == NULL || bi == NULL) return 2;
    FFTSetupD setup = vDSP_create_fftsetupD(log2n, kFFTRadix2);
    if (setup == NULL) return 2;
    DSPDoubleSplitComplex buffer = {br, bi};
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    if (times == NULL) return 2;

    for (unsigned i = 0; i < warmups; ++i) {
        fill(re, im, count);
        run_zip(setup, re, im, n, terms, log2n, with_buffer, &buffer);
    }
    for (unsigned i = 0; i < reps; ++i) {
        fill(re, im, count);
        double begin = now_seconds();
        run_zip(setup, re, im, n, terms, log2n, with_buffer, &buffer);
        times[i] = now_seconds() - begin;
    }
    double min_s = times[0], max_s = times[0];
    for (unsigned i = 1; i < reps; ++i) {
        if (times[i] < min_s) min_s = times[i];
        if (times[i] > max_s) max_s = times[i];
    }
    printf("N=%zu terms=%u mode=%s median_s=%.9f min_s=%.9f max_s=%.9f checksum=%.17g,%.17g\n",
           n, terms, with_buffer ? "ziptD" : "zipD", median(times, reps),
           min_s, max_s, re[count / 3], im[count / 3]);
    vDSP_destroy_fftsetupD(setup);
    free(times);
    free(bi);
    free(br);
    free(im);
    free(re);
    return 0;
}
