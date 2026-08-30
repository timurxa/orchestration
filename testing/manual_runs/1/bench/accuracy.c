#include "../src/dht.h"

#include <inttypes.h>
#include <math.h>
#include <mpfr.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t rng_state = UINT64_C(0x8f3c2d1e7a6b5948);
static const uint64_t base_seed = UINT64_C(0x8f3c2d1e7a6b5948);
static unsigned profile_terms = 0;
static double profile_cutoff = 0.0;
static unsigned profile_ratio = 2;

static dht_plan *make_plan(size_t n, double tol, unsigned threads) {
    if (profile_terms > 0 && profile_cutoff > 0.0) {
        return dht_plan_create_profile_ex(n, tol, profile_terms, profile_cutoff,
                                           threads, profile_ratio);
    }
    return dht_plan_create(n, tol, threads);
}

static uint64_t next_u64(void) {
    uint64_t x = rng_state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    rng_state = x;
    return x * UINT64_C(2685821657736338717);
}

static uint64_t mix_seed(uint64_t z) {
    z = (z ^ (z >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    z = (z ^ (z >> 27)) * UINT64_C(0x94d049bb133111eb);
    return z ^ (z >> 31);
}

static uint64_t input_seed(size_t n, unsigned kind) {
    return mix_seed(base_seed ^ (uint64_t)n * UINT64_C(0x9e3779b97f4a7c15) ^
                    (uint64_t)(kind + 1u) * UINT64_C(0xd1b54a32d192ed03));
}

static double uniform_signed(void) {
    return 2.0 * (double)(next_u64() >> 11) * 0x1.0p-53 - 1.0;
}

static void fill_input(dht_complex *x, size_t n, unsigned kind) {
    rng_state = input_seed(n, kind);
    for (size_t k = 0; k < n; ++k) {
        double t = (double)k / (double)n;
        if (kind == 0) {
            x[k].re = uniform_signed();
            x[k].im = uniform_signed();
        } else if (kind == 1) {
            double u = (t - 0.37) / 0.07;
            double g = exp(-0.5 * u * u);
            x[k].re = g;
            x[k].im = -0.7 * g;
        } else if (kind == 2) {
            double u = (t - 0.61) / 0.17;
            double bump = fabs(u) < 1.0 ? exp(-1.0 / (1.0 - u * u)) : 0.0;
            x[k].re = bump;
            x[k].im = sin(37.0 * t) * bump;
        } else if (kind == 3) {
            x[k].re = sin(2.0 * M_PI * (0.125 * k + 0.00031 * k * k));
            x[k].im = cos(2.0 * M_PI * (0.237 * k - 0.00017 * k * k));
        } else {
            double exponent = -12.0 + 24.0 * t;
            double magnitude = pow(10.0, exponent);
            double sign = (k & 1u) ? -1.0 : 1.0;
            x[k].re = sign * magnitude;
            x[k].im = -sign * magnitude * (0.25 + 0.5 * t);
        }
    }
}

static void fill_delta(dht_complex *x, size_t n, size_t at) {
    memset(x, 0, n * sizeof(*x));
    if (at < n) {
        x[at].re = 1.0;
        x[at].im = -0.375;
    }
}

static void reference_dense(size_t n, const dht_complex *x, dht_complex *y) {
    mpfr_t pi2, z, value, sumr, sumi, term, xr, xi;
    mpfr_inits2(256, pi2, z, value, sumr, sumi, term, xr, xi, (mpfr_ptr)0);
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
        y[m].re = mpfr_get_d(sumr, MPFR_RNDN);
        y[m].im = mpfr_get_d(sumi, MPFR_RNDN);
    }
    mpfr_clears(pi2, z, value, sumr, sumi, term, xr, xi, (mpfr_ptr)0);
}

static void reference_rows(size_t n, const dht_complex *x, dht_complex *y,
                           const size_t *rows, size_t count) {
    mpfr_t pi2, z, value, sumr, sumi, term, xr, xi;
    mpfr_inits2(256, pi2, z, value, sumr, sumi, term, xr, xi, (mpfr_ptr)0);
    mpfr_const_pi(pi2, MPFR_RNDN);
    mpfr_mul_ui(pi2, pi2, 2, MPFR_RNDN);
    for (size_t q = 0; q < count; ++q) {
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
        y[q].re = mpfr_get_d(sumr, MPFR_RNDN);
        y[q].im = mpfr_get_d(sumi, MPFR_RNDN);
    }
    mpfr_clears(pi2, z, value, sumr, sumi, term, xr, xi, (mpfr_ptr)0);
}

static void reference_delta(size_t n, size_t at, dht_complex *ref) {
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

static void error_metrics(const dht_complex *got, const dht_complex *ref,
                          size_t n, double *l2, double *linf) {
    long double sum = 0.0L;
    long double refsum = 0.0L;
    double maxerr = 0.0;
    double maxref = 0.0;
    for (size_t k = 0; k < n; ++k) {
        long double dr = (long double)got[k].re - ref[k].re;
        long double di = (long double)got[k].im - ref[k].im;
        long double rr = ref[k].re;
        long double ri = ref[k].im;
        sum += dr * dr + di * di;
        refsum += rr * rr + ri * ri;
        double e = hypot((double)dr, (double)di);
        double r = hypot(ref[k].re, ref[k].im);
        if (e > maxerr) {
            maxerr = e;
        }
        if (r > maxref) {
            maxref = r;
        }
    }
    *l2 = sqrt((double)(sum / (refsum > 0.0L ? refsum : 1.0L)));
    *linf = maxerr / (maxref > 1e-300 ? maxref : 1e-300);
}

static int check_case(size_t n, double tol, unsigned threads, unsigned kind,
                      int dense) {
    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *got = (dht_complex *)malloc(n * sizeof(*got));
    dht_complex *ref = (dht_complex *)malloc(n * sizeof(*ref));
    if (x == NULL || got == NULL || ref == NULL) {
        free(x); free(got); free(ref);
        return 0;
    }
    if (kind < 5) {
        fill_input(x, n, kind);
    } else {
        fill_delta(x, n, kind == 5 ? 1 : n - 1);
    }
    dht_plan *p = make_plan(n, tol, threads);
    if (p == NULL || dht_apply(p, x, got) != 0) {
        dht_plan_destroy(p); free(x); free(got); free(ref);
        return 0;
    }
    int pass = 1;
    if (dense) {
        reference_dense(n, x, ref);
        double l2, li;
        error_metrics(got, ref, n, &l2, &li);
        pass = l2 <= 1e-13 && li <= 1e-12;
        printf("dense N=%zu case=%u terms=%u z0=%.1f direct=%zu rel_l2=%.4e scaled_linf=%.4e %s\n",
               n, kind, dht_asymptotic_terms(p), dht_asymptotic_cutoff(p),
               dht_direct_entries(p), l2, li,
               pass ? "PASS" : "FAIL");
    }
    dht_plan_destroy(p);
    free(x); free(got); free(ref);
    return pass;
}

static int check_large_rows(size_t n, double tol, unsigned threads) {
    static const size_t row_template[] = {0, 1, 2, 3, 7, 31, 1024, 32768, 65535};
    size_t row_count = sizeof(row_template) / sizeof(row_template[0]);
    size_t *rows = (size_t *)malloc(row_count * sizeof(*rows));
    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *got = (dht_complex *)malloc(n * sizeof(*got));
    dht_complex *ref = (dht_complex *)malloc(row_count * sizeof(*ref));
    if (rows == NULL || x == NULL || got == NULL || ref == NULL) {
        free(rows); free(x); free(got); free(ref);
        return 0;
    }
    for (size_t i = 0; i < row_count; ++i) {
        rows[i] = row_template[i] < n ? row_template[i] : n - 1;
    }
    fill_input(x, n, 0);
    dht_plan *p = make_plan(n, tol, threads);
    if (p == NULL || dht_apply(p, x, got) != 0) {
        dht_plan_destroy(p); free(rows); free(x); free(got); free(ref);
        return 0;
    }
    reference_rows(n, x, ref, rows, row_count);
    double max_l2 = 0.0, max_li = 0.0;
    for (size_t i = 0; i < row_count; ++i) {
        double e = hypot(got[rows[i]].re - ref[i].re,
                         got[rows[i]].im - ref[i].im);
        double r = hypot(ref[i].re, ref[i].im);
        double scaled = e / (r > 1e-300 ? r : 1e-300);
        if (scaled > max_li) max_li = scaled;
        if (scaled > max_l2) max_l2 = scaled;
    }
    int pass = max_l2 <= 1e-11;
    printf("large-rows-diagnostic N=%zu terms=%u z0=%.1f direct=%zu max_row_rel=%.4e %s\n",
           n, dht_asymptotic_terms(p), dht_asymptotic_cutoff(p),
           dht_direct_entries(p), max_l2,
           pass ? "DIAGNOSTIC_PASS" : "DIAGNOSTIC_FAIL");
    dht_plan_destroy(p);
    free(rows); free(x); free(got); free(ref);
    return pass;
}

static int check_delta_full(size_t n, size_t at, double tol,
                            unsigned threads) {
    dht_complex *x = (dht_complex *)malloc(n * sizeof(*x));
    dht_complex *got = (dht_complex *)malloc(n * sizeof(*got));
    dht_complex *ref = (dht_complex *)malloc(n * sizeof(*ref));
    if (x == NULL || got == NULL || ref == NULL) {
        free(x); free(got); free(ref);
        return 0;
    }
    fill_delta(x, n, at);
    dht_plan *p = make_plan(n, tol, threads);
    if (p == NULL || dht_apply(p, x, got) != 0) {
        dht_plan_destroy(p); free(x); free(got); free(ref);
        return 0;
    }
    reference_delta(n, at, ref);
    double l2, li;
    error_metrics(got, ref, n, &l2, &li);
    int pass = l2 <= 1e-13 && li <= 1e-12;
    printf("delta-full N=%zu at=%zu terms=%u z0=%.1f direct=%zu rel_l2=%.4e scaled_linf=%.4e %s\n",
           n, at, dht_asymptotic_terms(p), dht_asymptotic_cutoff(p),
           dht_direct_entries(p), l2, li,
           pass ? "PASS" : "FAIL");
    dht_plan_destroy(p);
    free(x); free(got); free(ref);
    return pass;
}

int main(int argc, char **argv) {
    size_t large_n = argc > 1 ? (size_t)strtoull(argv[1], NULL, 10) : 65536;
    double tol = argc > 2 ? strtod(argv[2], NULL) : 1e-13;
    unsigned threads = argc > 3 ? (unsigned)strtoul(argv[3], NULL, 10) : 1;
    profile_terms = argc > 4 ? (unsigned)strtoul(argv[4], NULL, 10) : 0;
    profile_cutoff = argc > 5 ? strtod(argv[5], NULL) : 0.0;
    size_t max_dense = argc > 6 ? (size_t)strtoull(argv[6], NULL, 10) : 512;
    profile_ratio = argc > 7 ? (unsigned)strtoul(argv[7], NULL, 10) : 2;
    for (size_t n = 32; n <= max_dense; n *= 2) {
        for (unsigned kind = 0; kind < 5; ++kind) {
            if (!check_case(n, tol, threads, kind, 1)) return 2;
        }
    }
    if (!check_large_rows(large_n, tol, threads)) return 2;
    if (large_n >= 1024) {
        if (!check_delta_full(large_n, 1, tol, threads)) return 2;
        if (!check_delta_full(large_n, large_n - 1, tol, threads)) return 2;
    }
    return 0;
}
