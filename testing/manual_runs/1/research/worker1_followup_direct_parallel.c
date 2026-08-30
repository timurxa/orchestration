#include <dispatch/dispatch.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    double re;
    double im;
} complex_pair;

typedef struct {
    size_t n;
    const size_t *offset;
    const size_t *length;
    const double *kernel;
    const complex_pair *x;
    complex_pair *y;
    size_t tasks;
} direct_context;

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

static void kahan_add(double value, double *sum, double *correction) {
    double y = value - *correction;
    double t = *sum + y;
    *correction = (t - *sum) - y;
    *sum = t;
}

static size_t block_base(size_t x) {
    size_t p = 1;
    while (p <= x / 2) p *= 2;
    return p;
}

static void work_direct(void *opaque, size_t task) {
    direct_context *c = (direct_context *)opaque;
    size_t lo = 1 + (c->n - 1) * task / c->tasks;
    size_t hi = 1 + (c->n - 1) * (task + 1) / c->tasks;
    if (task + 1 == c->tasks) hi = c->n;
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

static void work_serial(void *opaque, size_t task) {
    direct_context *c = (direct_context *)opaque;
    if (task != 0) return;
    size_t saved_tasks = c->tasks;
    c->tasks = 1;
    work_direct(c, 0);
    c->tasks = saved_tasks;
}

static double checksum(const complex_pair *x, size_t n) {
    double sum = 0.0;
    for (size_t i = 0; i < n; ++i) sum += x[i].re + x[i].im;
    return sum;
}

static double measure(direct_context *c, dispatch_queue_t queue,
                      unsigned parallel, unsigned reps, unsigned warmups) {
    double *times = (double *)malloc((size_t)reps * sizeof(*times));
    for (unsigned i = 0; i < warmups; ++i) {
        memset(c->y, 0, c->n * sizeof(*c->y));
        if (parallel) {
            dispatch_apply_f(c->tasks, queue, c, work_direct);
        } else {
            dispatch_apply_f(1, queue, c, work_serial);
        }
    }
    for (unsigned i = 0; i < reps; ++i) {
        memset(c->y, 0, c->n * sizeof(*c->y));
        double begin = now_seconds();
        if (parallel) {
            dispatch_apply_f(c->tasks, queue, c, work_direct);
        } else {
            dispatch_apply_f(1, queue, c, work_serial);
        }
        times[i] = now_seconds() - begin;
        volatile double sink = checksum(c->y, c->n);
        (void)sink;
    }
    double result = median(times, reps);
    free(times);
    return result;
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    unsigned reps = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 11;
    unsigned warmups = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 3;
    size_t *offset = (size_t *)calloc(n, sizeof(*offset));
    size_t *length = (size_t *)calloc(n, sizeof(*length));
    complex_pair *x = (complex_pair *)malloc(n * sizeof(*x));
    complex_pair *y = (complex_pair *)malloc(n * sizeof(*y));
    if (!offset || !length || !x || !y) return 2;
    double threshold = 64.0 * (double)n / (2.0 * M_PI);
    size_t direct_count = 0;
    for (size_t m = 1; m < n; ++m) {
        size_t lo = block_base(m);
        double raw = threshold / (double)lo;
        size_t n0 = raw >= (double)n ? n : (size_t)ceil(raw);
        if (n0 > n) n0 = n;
        length[m] = n0 > 1 ? n0 - 1 : 0;
        offset[m] = direct_count;
        direct_count += length[m];
    }
    double *kernel = (double *)malloc(direct_count * sizeof(*kernel));
    if (!kernel) return 2;
    for (size_t k = 0; k < n; ++k) {
        x[k].re = cos(0.00017 * (double)k);
        x[k].im = sin(0.00031 * (double)k);
    }
    double c = 2.0 * M_PI / (double)n;
    for (size_t m = 1; m < n; ++m) {
        for (size_t j = 0; j < length[m]; ++j) {
            kernel[offset[m] + j] = j0(c * (double)m * (double)(j + 1));
        }
    }
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
    for (size_t threads = 1; threads <= 10; threads *= 2) {
        size_t task_count = threads * 4;
        direct_context context = {n, offset, length, kernel, x, y,
                                  task_count};
        double serial_s = measure(&context, queue, 0, reps, warmups);
        double parallel_s = measure(&context, queue, 1, reps, warmups);
        printf("N=%zu requested_workers=%zu tasks=%zu direct_entries=%zu serial_s=%.9f parallel_s=%.9f speedup=%.4f checksum=%.17g\n",
               n, threads, task_count, direct_count, serial_s, parallel_s,
               serial_s / parallel_s, checksum(y, n));
    }
    free(kernel); free(y); free(x); free(length); free(offset);
    return 0;
}
