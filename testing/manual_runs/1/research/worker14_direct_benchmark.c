#include <dispatch/dispatch.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    double re;
    double im;
} worker14_pair;

typedef struct {
    size_t n;
    const size_t *offset;
    const size_t *length;
    const double *kernel;
    const worker14_pair *x;
    worker14_pair *y;
    size_t tasks;
} worker14_direct_context;

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

static size_t block_base(size_t x, unsigned ratio) {
    size_t p = 1;
    while (p <= x / ratio) p *= ratio;
    return p;
}

static void kahan_add(double value, double *sum, double *correction) {
    double y = value - *correction;
    double t = *sum + y;
    *correction = (t - *sum) - y;
    *sum = t;
}

static void work_rows(const worker14_direct_context *c, size_t lo,
                      size_t hi) {
    for (size_t m = lo; m < hi; ++m) {
        double sr = 0.0, si = 0.0, cr = 0.0, ci = 0.0;
        size_t off = c->offset[m];
        for (size_t j = 0; j < c->length[m]; ++j) {
            size_t k = j + 1;
            double a = c->kernel[off + j];
            kahan_add(a * c->x[k].re, &sr, &cr);
            kahan_add(a * c->x[k].im, &si, &ci);
        }
        c->y[m].re += sr;
        c->y[m].im += si;
    }
}

static void work_parallel(void *opaque, size_t task) {
    worker14_direct_context *c = (worker14_direct_context *)opaque;
    size_t lo = 1 + (c->n - 1) * task / c->tasks;
    size_t hi = 1 + (c->n - 1) * (task + 1) / c->tasks;
    if (task + 1 == c->tasks) hi = c->n;
    work_rows(c, lo, hi);
}

static double checksum(const worker14_pair *y, size_t n) {
    double sum = 0.0;
    for (size_t i = 0; i < n; ++i) sum += y[i].re + y[i].im;
    return sum;
}

static void fill_input(worker14_pair *x, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        x[k].re = cos(0.00017 * (double)k);
        x[k].im = sin(0.00031 * (double)k);
    }
}

static double measure(worker14_direct_context *c, unsigned parallel,
                      unsigned reps, unsigned warmups) {
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    if (times == NULL) return NAN;
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
    for (unsigned i = 0; i < warmups; ++i) {
        memset(c->y, 0, c->n * sizeof(*c->y));
        if (parallel) {
            dispatch_apply_f(c->tasks, queue, c, work_parallel);
        } else {
            work_rows(c, 1, c->n);
        }
    }
    for (unsigned i = 0; i < reps; ++i) {
        memset(c->y, 0, c->n * sizeof(*c->y));
        double begin = now_seconds();
        if (parallel) {
            dispatch_apply_f(c->tasks, queue, c, work_parallel);
        } else {
            work_rows(c, 1, c->n);
        }
        times[i] = now_seconds() - begin;
    }
    double value = median(times, reps);
    free(times);
    return value;
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned reps = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 21;
    unsigned warmups = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 5;
    unsigned ratio = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 2;
    if (n < 2 || reps == 0 || ratio < 2) return 2;

    size_t *offset = (size_t *)calloc(n, sizeof(*offset));
    size_t *length = (size_t *)calloc(n, sizeof(*length));
    worker14_pair *x = (worker14_pair *)malloc(n * sizeof(*x));
    worker14_pair *y = (worker14_pair *)malloc(n * sizeof(*y));
    if (offset == NULL || length == NULL || x == NULL || y == NULL) return 2;

    size_t count = 0;
    double threshold = 64.0 * (double)n / (2.0 * M_PI);
    for (size_t m = 1; m < n; ++m) {
        size_t lo = block_base(m, ratio);
        double raw = threshold / (double)lo;
        size_t n0 = raw >= (double)n ? n : (size_t)ceil(raw);
        if (n0 > n) n0 = n;
        offset[m] = count;
        length[m] = n0 > 1 ? n0 - 1 : 0;
        count += length[m];
    }
    double *kernel = (double *)malloc(count * sizeof(*kernel));
    if (kernel == NULL) return 2;
    fill_input(x, n);
    double cscale = 2.0 * M_PI / (double)n;
    for (size_t m = 1; m < n; ++m) {
        for (size_t j = 0; j < length[m]; ++j) {
            kernel[offset[m] + j] = j0(cscale * (double)m * (double)(j + 1));
        }
    }

    for (size_t workers = 1; workers <= 10; workers *= 2) {
        worker14_direct_context context = {
            n, offset, length, kernel, x, y, workers * 4
        };
        double serial = measure(&context, 0, reps, warmups);
        double parallel = measure(&context, 1, reps, warmups);
        printf("N=%zu ratio=%u requested_workers=%zu tasks=%zu direct_entries=%zu "
               "serial_median_s=%.9f parallel_median_s=%.9f speedup=%.6f "
               "checksum=%.17g\n",
               n, ratio, workers, context.tasks, count, serial, parallel,
               serial / parallel, checksum(y, n));
    }
    free(kernel);
    free(y);
    free(x);
    free(length);
    free(offset);
    return 0;
}
