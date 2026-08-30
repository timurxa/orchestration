#include "../src/dht.h"

#include <math.h>
#include <mpfr.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PREC 256

static unsigned profile_terms = 12;
static double profile_cutoff = 18.0;

static void mp_argument(mpfr_t z, mpfr_t pi2, size_t n, size_t m,
                         size_t k) {
    mpfr_set_ui(z, m, MPFR_RNDN);
    mpfr_mul_ui(z, z, k, MPFR_RNDN);
    mpfr_mul(z, z, pi2, MPFR_RNDN);
    mpfr_div_ui(z, z, n, MPFR_RNDN);
}

static void mp_asym(mpfr_t out, mpfr_t z, mpfr_t angle, mpfr_t cosine,
                    mpfr_t sine, mpfr_t root, mpfr_t coeff, mpfr_t power,
                    mpfr_t term, mpfr_t pi2,
                    size_t n, size_t m, size_t k) {
    mp_argument(z, pi2, n, m, k);
    mpfr_sub_d(angle, z, M_PI / 4.0, MPFR_RNDN);
    mpfr_cos(cosine, angle, MPFR_RNDN);
    mpfr_sin(sine, angle, MPFR_RNDN);
    mpfr_mul(root, pi2, z, MPFR_RNDN);
    mpfr_div_ui(root, root, 2, MPFR_RNDN);
    mpfr_ui_div(root, 2, root, MPFR_RNDN);
    mpfr_sqrt(root, root, MPFR_RNDN);
    mpfr_set_ui(power, 1, MPFR_RNDN);
    mpfr_set_ui(coeff, 1, MPFR_RNDN);
    mpfr_set_zero(out, 0);
    for (unsigned q = 0; q < profile_terms; ++q) {
        if (q > 0) {
            unsigned odd = 2 * q - 1;
            mpfr_mul_ui(coeff, coeff, odd * odd, MPFR_RNDN);
            mpfr_div_ui(coeff, coeff, 8 * q, MPFR_RNDN);
        }
        mpfr_div(term, root, power, MPFR_RNDN);
        mpfr_mul(term, term, coeff, MPFR_RNDN);
        if ((q / 2) & 1u) mpfr_neg(term, term, MPFR_RNDN);
        if ((q & 1u) == 0) {
            mpfr_mul(term, term, cosine, MPFR_RNDN);
        } else {
            mpfr_mul(term, term, sine, MPFR_RNDN);
        }
        mpfr_add(out, out, term, MPFR_RNDN);
        mpfr_mul(power, power, z, MPFR_RNDN);
    }
}

static void fill_sign_aligned(dht_complex *x, size_t n, size_t target) {
    mpfr_t pi2, z, exact, asym, angle, cosine, sine, root, coeff, power;
    mpfr_t term, residual;
    mpfr_inits2(PREC, pi2, z, exact, asym, angle, cosine, sine, root, coeff,
                power, term, residual, (mpfr_ptr)0);
    mpfr_const_pi(pi2, MPFR_RNDN);
    mpfr_mul_ui(pi2, pi2, 2, MPFR_RNDN);
    size_t n0 = (size_t)ceil(profile_cutoff * (double)n /
                              (2.0 * M_PI * target));
    memset(x, 0, n * sizeof(*x));
    for (size_t k = n0; k < n; ++k) {
        mp_argument(z, pi2, n, target, k);
        mpfr_j0(exact, z, MPFR_RNDN);
        mp_asym(asym, z, angle, cosine, sine, root, coeff, power, term, pi2,
                n, target, k);
        mpfr_sub(residual, asym, exact, MPFR_RNDN);
        if (mpfr_sgn(residual) >= 0) {
            x[k].re = 1.0;
            x[k].im = -0.375;
        } else {
            x[k].re = -1.0;
            x[k].im = 0.375;
        }
    }
    mpfr_clears(pi2, z, exact, asym, angle, cosine, sine, root, coeff, power,
                term, residual, (mpfr_ptr)0);
}

static void reference(size_t n, const dht_complex *x, dht_complex *y) {
    mpfr_t pi2, z, value, xr, xi, term, sr, si;
    mpfr_inits2(PREC, pi2, z, value, xr, xi, term, sr, si, (mpfr_ptr)0);
    mpfr_const_pi(pi2, MPFR_RNDN);
    mpfr_mul_ui(pi2, pi2, 2, MPFR_RNDN);
    for (size_t m = 0; m < n; ++m) {
        mpfr_set_zero(sr, 0);
        mpfr_set_zero(si, 0);
        for (size_t k = 0; k < n; ++k) {
            mp_argument(z, pi2, n, m, k);
            mpfr_j0(value, z, MPFR_RNDN);
            mpfr_set_d(xr, x[k].re, MPFR_RNDN);
            mpfr_set_d(xi, x[k].im, MPFR_RNDN);
            mpfr_mul(term, value, xr, MPFR_RNDN);
            mpfr_add(sr, sr, term, MPFR_RNDN);
            mpfr_mul(term, value, xi, MPFR_RNDN);
            mpfr_add(si, si, term, MPFR_RNDN);
        }
        y[m].re = mpfr_get_d(sr, MPFR_RNDN);
        y[m].im = mpfr_get_d(si, MPFR_RNDN);
    }
    mpfr_clears(pi2, z, value, xr, xi, term, sr, si, (mpfr_ptr)0);
}

static void metrics(const dht_complex *a, const dht_complex *b, size_t n,
                    double *l2, double *linf) {
    long double e2 = 0.0L, r2 = 0.0L, em = 0.0L, rm = 0.0L;
    for (size_t i = 0; i < n; ++i) {
        long double dr = (long double)a[i].re - b[i].re;
        long double di = (long double)a[i].im - b[i].im;
        long double rr = b[i].re, ri = b[i].im;
        long double e = hypotl(dr, di), r = hypotl(rr, ri);
        e2 += e * e;
        r2 += r * r;
        if (e > em) em = e;
        if (r > rm) rm = r;
    }
    *l2 = (double)sqrtl(e2 / (r2 > 0 ? r2 : 1));
    *linf = (double)(em / (rm > 1e-300L ? rm : 1e-300L));
}

int main(int argc, char **argv) {
    if (argc > 1) profile_terms = (unsigned)strtoul(argv[1], NULL, 10);
    if (argc > 2) profile_cutoff = strtod(argv[2], NULL);
    if (profile_terms == 0 || !(profile_cutoff > 0.0)) return 2;
    const size_t sizes[] = {32, 64, 128, 256, 512};
    for (size_t si = 0; si < sizeof(sizes) / sizeof(sizes[0]); ++si) {
        size_t n = sizes[si];
        dht_complex *x = calloc(n, sizeof(*x));
        dht_complex *got = malloc(n * sizeof(*got));
        dht_complex *ref = malloc(n * sizeof(*ref));
        if (!x || !got || !ref) return 2;
        size_t target = 1;
        while (target < n &&
               (double)target <= profile_cutoff / (2.0 * M_PI)) {
            target *= 4;
        }
        if (target >= n) target = n - 1;
        fill_sign_aligned(x, n, target);
        dht_plan *p = dht_plan_create_profile_ex(n, 1e-13, profile_terms,
                                                  profile_cutoff, 1, 4);
        if (!p || dht_apply(p, x, got)) return 2;
        reference(n, x, ref);
        double l2, li;
        metrics(got, ref, n, &l2, &li);
        printf("N=%zu target=%zu K=%u z0=%.1f rel_l2=%.17e scaled_linf=%.17e %s\n",
               n, target, profile_terms, profile_cutoff, l2, li,
               l2 <= 1e-13 && li <= 1e-12 ? "PASS" : "FAIL");
        dht_plan_destroy(p);
        free(ref);
        free(got);
        free(x);
    }
    return 0;
}
