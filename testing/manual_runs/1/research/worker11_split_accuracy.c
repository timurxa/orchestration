#include "worker11_split_impl.h"

#include <mpfr.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t worker11_rng_state = UINT64_C(0x8f3c2d1e7a6b5948);

static uint64_t worker11_next_u64(void) {
    uint64_t x = worker11_rng_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    worker11_rng_state = x;
    return x * UINT64_C(2685821657736338717);
}

static double worker11_uniform_signed(void) {
    return 2.0 * (double)(worker11_next_u64() >> 11) * 0x1.0p-53 - 1.0;
}

static void worker11_fill_random(dht_complex *x, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        x[k].re = worker11_uniform_signed();
        x[k].im = worker11_uniform_signed();
    }
}

static void worker11_fill_delta(dht_complex *x, size_t n, size_t at) {
    memset(x, 0, n * sizeof(*x));
    x[at].re = 1.0;
    x[at].im = -0.375;
}

static void worker11_reference_dense(size_t n, const dht_complex *x,
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

typedef struct {
    double l2;
    double linf;
} worker11_metrics;

static worker11_metrics worker11_error(const dht_complex *got,
                                       const dht_complex *ref, size_t n) {
    long double sum = 0.0L;
    long double refsum = 0.0L;
    double maxerr = 0.0;
    double maxref = 0.0;
    for (size_t k = 0; k < n; ++k) {
        long double dr = (long double)got[k].re - ref[k].re;
        long double di = (long double)got[k].im - ref[k].im;
        sum += dr * dr + di * di;
        refsum += (long double)ref[k].re * ref[k].re +
                  (long double)ref[k].im * ref[k].im;
        double e = hypot((double)dr, (double)di);
        double r = hypot(ref[k].re, ref[k].im);
        if (e > maxerr) maxerr = e;
        if (r > maxref) maxref = r;
    }
    worker11_metrics result;
    result.l2 = sqrt((double)(sum / (refsum > 0.0L ? refsum : 1.0L)));
    result.linf = maxerr / (maxref > 1e-300 ? maxref : 1e-300);
    return result;
}

static worker11_metrics worker11_pair_difference(const dht_complex *a,
                                                 const dht_complex *b,
                                                 size_t n) {
    long double sum = 0.0L;
    long double refsum = 0.0L;
    double maxerr = 0.0;
    double maxref = 0.0;
    for (size_t k = 0; k < n; ++k) {
        long double dr = (long double)a[k].re - b[k].re;
        long double di = (long double)a[k].im - b[k].im;
        sum += dr * dr + di * di;
        refsum += (long double)b[k].re * b[k].re +
                  (long double)b[k].im * b[k].im;
        double e = hypot((double)dr, (double)di);
        double r = hypot(b[k].re, b[k].im);
        if (e > maxerr) maxerr = e;
        if (r > maxref) maxref = r;
    }
    worker11_metrics result;
    result.l2 = sqrt((double)(sum / (refsum > 0.0L ? refsum : 1.0L)));
    result.linf = maxerr / (maxref > 1e-300 ? maxref : 1e-300);
    return result;
}

static dht_plan *worker11_make_current(size_t n, unsigned profile) {
    if (profile == 0) {
        return dht_plan_create(n, 1e-13, 1);
    }
    return dht_plan_create_profile_ex(n, 1e-13, 12, 18.0, 1, 4);
}

static worker11_split_plan *worker11_make_split(size_t n, unsigned profile) {
    if (profile == 0) {
        return worker11_split_create(n, 1e-13, 10, 64.0, 1, 2);
    }
    return worker11_split_create(n, 1e-13, 12, 18.0, 1, 4);
}

static int worker11_check_case(size_t n, unsigned profile, const char *name,
                               const dht_complex *x) {
    dht_complex *ref = (dht_complex *)malloc(n * sizeof(*ref));
    dht_complex *current = (dht_complex *)malloc(n * sizeof(*current));
    dht_complex *split = (dht_complex *)malloc(n * sizeof(*split));
    if (ref == NULL || current == NULL || split == NULL) {
        free(ref); free(current); free(split);
        return 0;
    }
    worker11_reference_dense(n, x, ref);
    dht_plan *p = worker11_make_current(n, profile);
    worker11_split_plan *s = worker11_make_split(n, profile);
    int ok = p != NULL && s != NULL && dht_apply(p, x, current) == 0 &&
             worker11_split_apply(s, x, split) == 0;
    if (!ok) {
        printf("N=%zu profile=%u case=%s construction_or_apply=FAIL\n", n,
               profile, name);
        dht_plan_destroy(p);
        worker11_split_destroy(s);
        free(ref); free(current); free(split);
        return 0;
    }
    worker11_metrics em_current = worker11_error(current, ref, n);
    worker11_metrics em_split = worker11_error(split, ref, n);
    worker11_metrics em_pair = worker11_pair_difference(split, current, n);
    size_t split_bytes = worker11_split_bytes(s);
    int pass = em_split.l2 <= 1e-13 && em_split.linf <= 1e-12;
    printf("N=%zu profile=%u case=%s current_l2=%.4e current_linf=%.4e "
           "split_l2=%.4e split_linf=%.4e split_vs_current_l2=%.4e "
           "split_vs_current_linf=%.4e split_bytes=%zu %s\n",
           n, profile, name, em_current.l2, em_current.linf, em_split.l2,
           em_split.linf, em_pair.l2, em_pair.linf, split_bytes,
           pass ? "PASS" : "FAIL");
    dht_plan_destroy(p);
    worker11_split_destroy(s);
    free(ref); free(current); free(split);
    return pass;
}

int main(int argc, char **argv) {
    size_t max_n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 256;
    int all_ok = 1;
    for (unsigned profile = 0; profile < 2; ++profile) {
        for (size_t n = 32; n <= max_n; n *= 2) {
            dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
            if (x == NULL) return 2;
            worker11_fill_random(x, n);
            all_ok &= worker11_check_case(n, profile, "random", x);
            worker11_fill_delta(x, n, n / 3);
            all_ok &= worker11_check_case(n, profile, "delta", x);
            free(x);
        }
    }
    return all_ok ? 0 : 1;
}
