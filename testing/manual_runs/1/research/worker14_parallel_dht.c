#include <dispatch/dispatch.h>

/* Keep the current implementation intact and replace only the public apply
 * entry point.  The renamed symbols let this translation unit link as an
 * isolated benchmark candidate without changing src/. */
#define dht_apply dht_apply_serial_reference
#define add_direct_rows add_direct_rows_serial_reference
#include "../src/dht_asym.c"
#undef add_direct_rows
#undef dht_apply

typedef struct {
    const dht_plan *p;
    const dht_complex *x;
    dht_complex *y;
    size_t tasks;
} worker14_direct_context;

static void worker14_direct_rows(void *opaque, size_t task) {
    worker14_direct_context *c = (worker14_direct_context *)opaque;
    size_t lo = 1 + (c->p->n - 1) * task / c->tasks;
    size_t hi = 1 + (c->p->n - 1) * (task + 1) / c->tasks;
    if (task + 1 == c->tasks) {
        hi = c->p->n;
    }
    for (size_t m = lo; m < hi; ++m) {
        size_t len = c->p->row_length[m];
        size_t off = c->p->row_offset[m];
        double sr = 0.0, si = 0.0, cr = 0.0, ci = 0.0;
        for (size_t j = 0; j < len; ++j) {
            size_t k = j + 1;
            double a = c->p->small_kernel[off + j];
            kahan_complex_add(a * c->x[k].re, a * c->x[k].im, &sr, &cr,
                              &si, &ci);
        }
        c->y[m].re += sr;
        c->y[m].im += si;
    }
}

int dht_apply(const dht_plan *p, const dht_complex *x, dht_complex *y) {
    if (p == NULL || x == NULL || y == NULL) {
        return -1;
    }
    for (size_t m = 0; m < p->n; ++m) {
        y[m].re = x[0].re;
        y[m].im = x[0].im;
    }
    add_zero_row(p, x, y);

    size_t lo = 1;
    while (lo < p->n) {
        size_t hi = lo <= p->n / p->block_ratio
                        ? lo * p->block_ratio
                        : p->n;
        add_asym_block(p, lo, hi, x, y);
        lo = hi;
    }

    size_t tasks = (size_t)p->threads * 4;
    if (tasks == 0) {
        tasks = 1;
    }
    worker14_direct_context context = {p, x, y, tasks};
    dispatch_apply_f(tasks, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0),
                     &context, worker14_direct_rows);
    return 0;
}

int worker14_apply_serial_reference(const dht_plan *p, const dht_complex *x,
                                    dht_complex *y) {
    return dht_apply_serial_reference(p, x, y);
}
