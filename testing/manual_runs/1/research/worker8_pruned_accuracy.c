#define WORKER8_PRUNED_NO_MAIN
#include "worker8_pruned_bench.c"

#include <mpfr.h>

static void worker8_reference_dense(size_t n, const dht_complex *x,
                                    dht_complex *ref) {
    mpfr_t pi2, z, value, sumr, sumi, term, xr, xi;
    mpfr_inits2(256, pi2, z, value, sumr, sumi, term, xr, xi,
                (mpfr_ptr)0);
    mpfr_const_pi(pi2, MPFR_RNDN);
    mpfr_mul_ui(pi2, pi2, 2, MPFR_RNDN);
    for (size_t m = 0; m < n; ++m) {
        mpfr_set_zero(sumr, 0);
        mpfr_set_zero(sumi, 0);
        for (size_t k = 0; k < n; ++k) {
            mpfr_set_ui(z, m, MPFR_RNDN);
            mpfr_mul_ui(z, z, k, MPFR_RNDN);
            mpfr_mul(z, z, pi2, MPFR_RNDN);
            mpfr_div_ui(z, z, n, MPFR_RNDN);
            mpfr_j0(value, z, MPFR_RNDN);
            mpfr_set_d(xr, x[k].re, MPFR_RNDN);
            mpfr_set_d(xi, x[k].im, MPFR_RNDN);
            mpfr_mul(term, value, xr, MPFR_RNDN);
            mpfr_add(sumr, sumr, term, MPFR_RNDN);
            mpfr_mul(term, value, xi, MPFR_RNDN);
            mpfr_add(sumi, sumi, term, MPFR_RNDN);
        }
        ref[m].re = mpfr_get_d(sumr, MPFR_RNDN);
        ref[m].im = mpfr_get_d(sumi, MPFR_RNDN);
    }
    mpfr_clears(pi2, z, value, sumr, sumi, term, xr, xi, (mpfr_ptr)0);
}

static void worker8_reference_rows(size_t n, const dht_complex *x,
                                   const size_t *rows, size_t row_count,
                                   dht_complex *ref) {
    mpfr_t pi2, z, value, sumr, sumi, term, xr, xi;
    mpfr_inits2(256, pi2, z, value, sumr, sumi, term, xr, xi,
                (mpfr_ptr)0);
    mpfr_const_pi(pi2, MPFR_RNDN);
    mpfr_mul_ui(pi2, pi2, 2, MPFR_RNDN);
    for (size_t q = 0; q < row_count; ++q) {
        size_t m = rows[q];
        mpfr_set_zero(sumr, 0);
        mpfr_set_zero(sumi, 0);
        for (size_t k = 0; k < n; ++k) {
            mpfr_set_ui(z, m, MPFR_RNDN);
            mpfr_mul_ui(z, z, k, MPFR_RNDN);
            mpfr_mul(z, z, pi2, MPFR_RNDN);
            mpfr_div_ui(z, z, n, MPFR_RNDN);
            mpfr_j0(value, z, MPFR_RNDN);
            mpfr_set_d(xr, x[k].re, MPFR_RNDN);
            mpfr_set_d(xi, x[k].im, MPFR_RNDN);
            mpfr_mul(term, value, xr, MPFR_RNDN);
            mpfr_add(sumr, sumr, term, MPFR_RNDN);
            mpfr_mul(term, value, xi, MPFR_RNDN);
            mpfr_add(sumi, sumi, term, MPFR_RNDN);
        }
        ref[q].re = mpfr_get_d(sumr, MPFR_RNDN);
        ref[q].im = mpfr_get_d(sumi, MPFR_RNDN);
    }
    mpfr_clears(pi2, z, value, sumr, sumi, term, xr, xi, (mpfr_ptr)0);
}

static void worker8_reference_delta(size_t n, size_t at, dht_complex *ref) {
    mpfr_t pi2, z, value;
    mpfr_inits2(256, pi2, z, value, (mpfr_ptr)0);
    mpfr_const_pi(pi2, MPFR_RNDN);
    mpfr_mul_ui(pi2, pi2, 2, MPFR_RNDN);
    for (size_t m = 0; m < n; ++m) {
        mpfr_set_ui(z, m, MPFR_RNDN);
        mpfr_mul_ui(z, z, at, MPFR_RNDN);
        mpfr_mul(z, z, pi2, MPFR_RNDN);
        mpfr_div_ui(z, z, n, MPFR_RNDN);
        mpfr_j0(value, z, MPFR_RNDN);
        ref[m].re = mpfr_get_d(value, MPFR_RNDN);
        ref[m].im = -0.375 * ref[m].re;
    }
    mpfr_clears(pi2, z, value, (mpfr_ptr)0);
}

static void worker8_metrics(const dht_complex *got, const dht_complex *ref,
                            size_t n, double *l2, double *linf) {
    long double sum = 0.0L;
    long double refsum = 0.0L;
    double maxerr = 0.0;
    double maxref = 0.0;
    for (size_t i = 0; i < n; ++i) {
        long double dr = (long double)got[i].re - ref[i].re;
        long double di = (long double)got[i].im - ref[i].im;
        sum += dr * dr + di * di;
        refsum += (long double)ref[i].re * ref[i].re +
                  (long double)ref[i].im * ref[i].im;
        double error = hypot((double)dr, (double)di);
        double scale = hypot(ref[i].re, ref[i].im);
        if (error > maxerr) maxerr = error;
        if (scale > maxref) maxref = scale;
    }
    *l2 = sqrt((double)(sum / (refsum > 0.0L ? refsum : 1.0L)));
    *linf = maxerr / (maxref > 1e-300 ? maxref : 1e-300);
}

static void worker8_metrics_rows(const dht_complex *got,
                                 const dht_complex *ref,
                                 const size_t *rows, size_t count, double *l2,
                                 double *linf) {
    long double sum = 0.0L;
    long double refsum = 0.0L;
    double maxerr = 0.0;
    double maxref = 0.0;
    for (size_t q = 0; q < count; ++q) {
        size_t i = rows[q];
        long double dr = (long double)got[i].re - ref[q].re;
        long double di = (long double)got[i].im - ref[q].im;
        sum += dr * dr + di * di;
        refsum += (long double)ref[q].re * ref[q].re +
                  (long double)ref[q].im * ref[q].im;
        double error = hypot((double)dr, (double)di);
        double scale = hypot(ref[q].re, ref[q].im);
        if (error > maxerr) maxerr = error;
        if (scale > maxref) maxref = scale;
    }
    *l2 = sqrt((double)(sum / (refsum > 0.0L ? refsum : 1.0L)));
    *linf = maxerr / (maxref > 1e-300 ? maxref : 1e-300);
}

static void worker8_difference(const dht_complex *a, const dht_complex *b,
                               size_t n, double *max_abs) {
    *max_abs = 0.0;
    for (size_t i = 0; i < n; ++i) {
        double error = hypot(a[i].re - b[i].re, a[i].im - b[i].im);
        if (error > *max_abs) *max_abs = error;
    }
}

int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 1024;
    unsigned threads = argc > 2 ? (unsigned)strtoul(argv[2], NULL, 10) : 1;
    if (n < 2 || worker8_log2_exact(n) == 0) return 2;
    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *pruned = (dht_complex *)malloc(n * sizeof(*pruned));
    dht_complex *current = (dht_complex *)malloc(n * sizeof(*current));
    dht_complex *ref = (dht_complex *)malloc(n * sizeof(*ref));
    if (x == NULL || pruned == NULL || current == NULL || ref == NULL) {
        free(ref); free(current); free(pruned); free(x);
        return 2;
    }
    worker8_fill_input(x, n);
    dht_plan *p = dht_plan_create(n, 1e-13, threads);
    if (p == NULL) return 2;
    worker8_pruned_context ctx;
    if (!worker8_make_context(p, &ctx) ||
        worker8_pruned_apply(p, &ctx, x, pruned) != 0 ||
        dht_apply(p, x, current) != 0) return 2;
    double pruned_l2, pruned_linf, current_l2, current_linf, max_diff;
    size_t rows[9] = {0, 1, 2, 3, 7, n / 4, n / 2, n - 2, n - 1};
    dht_complex row_ref[9];
    int full_reference = n <= 1024;
    if (full_reference) {
        worker8_reference_dense(n, x, ref);
        worker8_metrics(pruned, ref, n, &pruned_l2, &pruned_linf);
        worker8_metrics(current, ref, n, &current_l2, &current_linf);
    } else {
        worker8_reference_rows(n, x, rows, 9, row_ref);
        worker8_metrics_rows(pruned, row_ref, rows, 9, &pruned_l2,
                             &pruned_linf);
        worker8_metrics_rows(current, row_ref, rows, 9, &current_l2,
                             &current_linf);
    }
    worker8_difference(pruned, current, n, &max_diff);
    dht_complex delta_ref[n];
    memset(x, 0, n * sizeof(*x));
    x[1].re = 1.0;
    x[1].im = -0.375;
    if (worker8_pruned_apply(p, &ctx, x, pruned) != 0 ||
        dht_apply(p, x, current) != 0) return 2;
    worker8_reference_delta(n, 1, delta_ref);
    double delta_pruned_l2, delta_pruned_linf, delta_current_l2,
        delta_current_linf;
    worker8_metrics(pruned, delta_ref, n, &delta_pruned_l2,
                    &delta_pruned_linf);
    worker8_metrics(current, delta_ref, n, &delta_current_l2,
                    &delta_current_linf);
    if (full_reference) {
        printf("N=%zu threads=%u reference=full-mpfr256 "
               "random_pruned_rel_l2=%.6e random_pruned_scaled_linf=%.6e "
               "random_current_rel_l2=%.6e random_current_scaled_linf=%.6e "
               "random_max_abs_pruned_minus_current=%.6e "
               "delta_pruned_rel_l2=%.6e delta_pruned_scaled_linf=%.6e "
               "delta_current_rel_l2=%.6e delta_current_scaled_linf=%.6e\n",
               n, threads, pruned_l2, pruned_linf, current_l2, current_linf,
               max_diff, delta_pruned_l2, delta_pruned_linf,
               delta_current_l2, delta_current_linf);
    } else {
        printf("N=%zu threads=%u reference=random-rows-mpfr256 "
               "random_rows=9 pruned_rel_l2=%.6e pruned_scaled_linf=%.6e "
               "current_rel_l2=%.6e current_scaled_linf=%.6e "
               "random_max_abs_pruned_minus_current=%.6e "
               "delta_reference=full-mpfr256 "
               "delta_pruned_rel_l2=%.6e delta_pruned_scaled_linf=%.6e "
               "delta_current_rel_l2=%.6e delta_current_scaled_linf=%.6e\n",
               n, threads, pruned_l2, pruned_linf, current_l2, current_linf,
               max_diff, delta_pruned_l2, delta_pruned_linf,
               delta_current_l2, delta_current_linf);
    }
    worker8_destroy_context(&ctx);
    dht_plan_destroy(p);
    free(ref); free(current); free(pruned); free(x);
    return 0;
}
