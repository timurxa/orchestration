#include "../src/dht.h"

#include <math.h>
#include <mpfr.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MP_PREC 256

typedef struct {
    mpfr_t pi2;
    mpfr_t pi4;
    mpfr_t z;
    mpfr_t value;
    mpfr_t sumr;
    mpfr_t sumi;
    mpfr_t term;
    mpfr_t xr;
    mpfr_t xi;
    mpfr_t phase;
    mpfr_t denom;
    mpfr_t root;
    mpfr_t zpow;
    mpfr_t coeff;
    mpfr_t tmp;
    mpfr_t cosine;
    mpfr_t trig;
    mpfr_t asym;
    mpfr_t residual;
} mp_workspace;

typedef struct {
    const char *name;
    unsigned terms;
    double cutoff;
} profile_spec;

typedef struct {
    double l2;
    double linf;
    double maxerr;
    double maxref;
} metrics;

static const profile_spec profiles[] = {
    {"K8_z32", 8, 32.0},
    {"K8_z34", 8, 34.0},
    {"K8_z40", 8, 40.0},
    {"K8_z48", 8, 48.0},
    {"K10_z40", 10, 40.0},
    {"K6_z64", 6, 64.0},
};

static const size_t selected_rows[] = {
    0, 1, 2, 3, 4, 6, 7, 8, 10, 15, 16, 31, 32, 64, 1024, 32768, 65535
};

static void die(const char *message) {
    fprintf(stderr, "worker3_followup: %s\n", message);
    exit(2);
}

static void *checked_malloc(size_t bytes) {
    void *p = malloc(bytes);
    if (p == NULL) {
        die("out of memory");
    }
    return p;
}

static dht_complex *alloc_complex(size_t n) {
    return (dht_complex *)checked_malloc(n * sizeof(dht_complex));
}

static void mp_workspace_init(mp_workspace *w) {
    mpfr_inits2(MP_PREC, w->pi2, w->pi4, w->z, w->value, w->sumr,
                w->sumi, w->term, w->xr, w->xi, w->phase, w->denom,
                w->root, w->zpow, w->coeff, w->tmp, w->cosine, w->trig,
                w->asym,
                w->residual, (mpfr_ptr)0);
    mpfr_const_pi(w->pi2, MPFR_RNDN);
    mpfr_mul_ui(w->pi2, w->pi2, 2, MPFR_RNDN);
    mpfr_div_ui(w->pi4, w->pi2, 8, MPFR_RNDN);
}

static void mp_workspace_clear(mp_workspace *w) {
    mpfr_clears(w->pi2, w->pi4, w->z, w->value, w->sumr, w->sumi,
                w->term, w->xr, w->xi, w->phase, w->denom, w->root,
                w->zpow, w->coeff, w->tmp, w->cosine, w->trig, w->asym,
                w->residual, (mpfr_ptr)0);
}

static void mp_set_argument(mp_workspace *w, size_t n, size_t m, size_t k) {
    mpfr_set_ui(w->z, m, MPFR_RNDN);
    mpfr_mul_ui(w->z, w->z, k, MPFR_RNDN);
    mpfr_mul(w->z, w->z, w->pi2, MPFR_RNDN);
    mpfr_div_ui(w->z, w->z, n, MPFR_RNDN);
}

static void mp_j0_at(mp_workspace *w, size_t n, size_t m, size_t k) {
    mp_set_argument(w, n, m, k);
    mpfr_j0(w->value, w->z, MPFR_RNDN);
}

/* Independent MPFR implementation of the same K-term mathematical
 * asymptotic profile used by src/dht_asym.c.  Positive c_q are generated
 * recursively; the phase is z-pi/4 and q-even/q-odd terms use cos/sin. */
static void mp_asym_at(mp_workspace *w, size_t n, size_t m, size_t k,
                       unsigned terms) {
    mp_set_argument(w, n, m, k);
    mpfr_sub(w->phase, w->z, w->pi4, MPFR_RNDN);
    mpfr_cos(w->cosine, w->phase, MPFR_RNDN);
    mpfr_sin(w->trig, w->phase, MPFR_RNDN);

    mpfr_mul(w->denom, w->pi2, w->z, MPFR_RNDN);
    mpfr_div_ui(w->denom, w->denom, 2, MPFR_RNDN);
    mpfr_set_ui(w->tmp, 2, MPFR_RNDN);
    mpfr_div(w->tmp, w->tmp, w->denom, MPFR_RNDN);
    mpfr_sqrt(w->root, w->tmp, MPFR_RNDN);
    mpfr_set_ui(w->zpow, 1, MPFR_RNDN);
    mpfr_set_ui(w->coeff, 1, MPFR_RNDN);
    mpfr_set_zero(w->asym, 0);

    for (unsigned q = 0; q < terms; ++q) {
        if (q > 0) {
            unsigned odd = 2u * q - 1u;
            mpfr_mul_ui(w->coeff, w->coeff, odd * odd, MPFR_RNDN);
            mpfr_div_ui(w->coeff, w->coeff, 8u * q, MPFR_RNDN);
        }
        mpfr_div(w->term, w->root, w->zpow, MPFR_RNDN);
        mpfr_mul(w->term, w->term, w->coeff, MPFR_RNDN);
        if ((q / 2u) & 1u) {
            mpfr_neg(w->term, w->term, MPFR_RNDN);
        }
        if ((q & 1u) == 0u) {
            mpfr_mul(w->term, w->term, w->cosine, MPFR_RNDN);
        } else {
            mpfr_mul(w->term, w->term, w->trig, MPFR_RNDN);
        }
        mpfr_add(w->asym, w->asym, w->term, MPFR_RNDN);
        mpfr_mul(w->zpow, w->zpow, w->z, MPFR_RNDN);
    }
}

static size_t highest_power_of_two(size_t x) {
    size_t p = 1;
    while ((p << 1) <= x) {
        p <<= 1;
    }
    return p;
}

static size_t asym_start(size_t n, size_t m, double cutoff) {
    double threshold = cutoff * (double)n / (2.0 * M_PI);
    size_t lo = highest_power_of_two(m);
    size_t n0 = (size_t)ceil(threshold / (double)lo);
    return n0 < n ? n0 : n;
}

static size_t sign_target(size_t n, double cutoff) {
    size_t m = 1;
    while (m < n && (double)m <= cutoff / (2.0 * M_PI)) {
        m <<= 1;
    }
    if (m >= n) {
        m = highest_power_of_two(n - 1);
    }
    return m;
}

static void fill_delta(dht_complex *x, size_t n, size_t at) {
    memset(x, 0, n * sizeof(*x));
    x[at].re = 1.0;
    x[at].im = -0.375;
}

static void fill_alternating(dht_complex *x, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        double sign = (k & 1u) ? -1.0 : 1.0;
        double t = n > 1 ? (double)k / (double)(n - 1) : 0.0;
        x[k].re = sign;
        x[k].im = -sign * (0.25 + 0.5 * t);
    }
}

static void fill_high_dynamic(dht_complex *x, size_t n) {
    for (size_t k = 0; k < n; ++k) {
        /* A deterministic exponent permutation visits [-300,300] over each
         * 601-point cycle, while the alternating sign stresses cancellation. */
        int exponent = (int)((37u * (unsigned)k + 17u) % 601u) - 300;
        double magnitude = ldexp(1.0, exponent);
        double sign = (k & 1u) ? -1.0 : 1.0;
        double t = n > 1 ? (double)k / (double)(n - 1) : 0.0;
        x[k].re = sign * magnitude;
        x[k].im = -sign * magnitude * (0.25 + 0.5 * t);
    }
}

static void fill_sign_aligned(dht_complex *x, size_t n, size_t target_m,
                              const profile_spec *profile,
                              mp_workspace *w, size_t *n0_out,
                              size_t *positive_out, size_t *negative_out,
                              double *residual_l1_out) {
    memset(x, 0, n * sizeof(*x));
    size_t n0 = asym_start(n, target_m, profile->cutoff);
    size_t positive = 0;
    size_t negative = 0;
    long double residual_l1 = 0.0L;
    for (size_t k = n0; k < n; ++k) {
        mp_j0_at(w, n, target_m, k);
        mp_asym_at(w, n, target_m, k, profile->terms);
        mpfr_sub(w->residual, w->asym, w->value, MPFR_RNDN);
        int sign = mpfr_sgn(w->residual);
        if (sign >= 0) {
            x[k].re = 1.0;
            x[k].im = -0.375;
            ++positive;
        } else {
            x[k].re = -1.0;
            x[k].im = 0.375;
            ++negative;
        }
        residual_l1 += fabsl((long double)mpfr_get_d(w->residual, MPFR_RNDN));
    }
    *n0_out = n0;
    *positive_out = positive;
    *negative_out = negative;
    *residual_l1_out = (double)residual_l1;
}

static void reference_full(const dht_complex *x, size_t n,
                           dht_complex *ref, mp_workspace *w) {
    for (size_t m = 0; m < n; ++m) {
        mpfr_set_zero(w->sumr, 0);
        mpfr_set_zero(w->sumi, 0);
        for (size_t k = 0; k < n; ++k) {
            mp_j0_at(w, n, m, k);
            mpfr_set_d(w->xr, x[k].re, MPFR_RNDN);
            mpfr_set_d(w->xi, x[k].im, MPFR_RNDN);
            mpfr_mul(w->term, w->value, w->xr, MPFR_RNDN);
            mpfr_add(w->sumr, w->sumr, w->term, MPFR_RNDN);
            mpfr_mul(w->term, w->value, w->xi, MPFR_RNDN);
            mpfr_add(w->sumi, w->sumi, w->term, MPFR_RNDN);
        }
        ref[m].re = mpfr_get_d(w->sumr, MPFR_RNDN);
        ref[m].im = mpfr_get_d(w->sumi, MPFR_RNDN);
    }
}

static void reference_rows(const dht_complex *x, size_t n,
                           const size_t *rows, size_t count,
                           dht_complex *ref, mp_workspace *w) {
    for (size_t q = 0; q < count; ++q) {
        size_t m = rows[q];
        mpfr_set_zero(w->sumr, 0);
        mpfr_set_zero(w->sumi, 0);
        for (size_t k = 0; k < n; ++k) {
            mp_j0_at(w, n, m, k);
            mpfr_set_d(w->xr, x[k].re, MPFR_RNDN);
            mpfr_set_d(w->xi, x[k].im, MPFR_RNDN);
            mpfr_mul(w->term, w->value, w->xr, MPFR_RNDN);
            mpfr_add(w->sumr, w->sumr, w->term, MPFR_RNDN);
            mpfr_mul(w->term, w->value, w->xi, MPFR_RNDN);
            mpfr_add(w->sumi, w->sumi, w->term, MPFR_RNDN);
        }
        ref[q].re = mpfr_get_d(w->sumr, MPFR_RNDN);
        ref[q].im = mpfr_get_d(w->sumi, MPFR_RNDN);
    }
}

static void reference_delta_full(size_t n, size_t at, dht_complex *ref,
                                 mp_workspace *w) {
    for (size_t m = 0; m < n; ++m) {
        mp_j0_at(w, n, m, at);
        ref[m].re = mpfr_get_d(w->value, MPFR_RNDN);
        mpfr_mul_d(w->term, w->value, -0.375, MPFR_RNDN);
        ref[m].im = mpfr_get_d(w->term, MPFR_RNDN);
    }
}

static metrics compute_metrics(const dht_complex *got, const dht_complex *ref,
                               size_t count) {
    long double err2 = 0.0L;
    long double ref2 = 0.0L;
    long double maxerr = 0.0L;
    long double maxref = 0.0L;
    for (size_t k = 0; k < count; ++k) {
        long double dr = (long double)got[k].re - ref[k].re;
        long double di = (long double)got[k].im - ref[k].im;
        long double rr = ref[k].re;
        long double ri = ref[k].im;
        long double e = hypotl(dr, di);
        long double r = hypotl(rr, ri);
        err2 += e * e;
        ref2 += r * r;
        if (e > maxerr) maxerr = e;
        if (r > maxref) maxref = r;
    }
    metrics result;
    result.l2 = (double)sqrtl(err2 / (ref2 > 0.0L ? ref2 : 1.0L));
    result.linf = (double)(maxerr / (maxref > 1.0e-300L ? maxref : 1.0e-300L));
    result.maxerr = (double)maxerr;
    result.maxref = (double)maxref;
    return result;
}

static metrics compute_selected_metrics(const dht_complex *got,
                                         const dht_complex *ref,
                                         const size_t *rows, size_t count) {
    dht_complex *picked = alloc_complex(count);
    for (size_t q = 0; q < count; ++q) {
        picked[q] = got[rows[q]];
    }
    metrics result = compute_metrics(picked, ref, count);
    free(picked);
    return result;
}

static const char *gate_label(metrics result) {
    return result.l2 <= 1.0e-13 && result.linf <= 1.0e-12 ? "PASS" : "FAIL";
}

static void run_full_case(size_t n, const char *case_name,
                          const dht_complex *x, const dht_complex *ref,
                          const profile_spec *profile, mp_workspace *w) {
    dht_plan *plan = dht_plan_create_profile(n, 1.0e-13, profile->terms,
                                              profile->cutoff, 1);
    if (plan == NULL) die("profile plan creation failed");
    dht_complex *got = alloc_complex(n);
    if (dht_apply(plan, x, got) != 0) die("dht_apply failed");
    metrics e = compute_metrics(got, ref, n);
    printf("SMALL,%s,%zu,%s,%u,%.1f,%zu,%.17e,%.17e,%.17e,%.17e,%s\n",
           case_name, n, profile->name, profile->terms, profile->cutoff,
           dht_direct_entries(plan), e.l2, e.linf, e.maxerr, e.maxref,
           gate_label(e));
    free(got);
    dht_plan_destroy(plan);
    (void)w;
}

static void run_high_rows(size_t n, const char *case_name,
                          const dht_complex *x, const dht_complex *ref,
                          const size_t *rows, size_t count,
                          const profile_spec *profile) {
    dht_plan *plan = dht_plan_create_profile(n, 1.0e-13, profile->terms,
                                              profile->cutoff, 1);
    if (plan == NULL) die("high-N profile plan creation failed");
    dht_complex *got = alloc_complex(n);
    if (dht_apply(plan, x, got) != 0) die("high-N dht_apply failed");
    metrics e = compute_selected_metrics(got, ref, rows, count);
    printf("HIGH_ROWS,%s,%zu,%s,%u,%.1f,%zu,%.17e,%.17e,%.17e,%.17e,%s\n",
           case_name, n, profile->name, profile->terms, profile->cutoff,
           dht_direct_entries(plan), e.l2, e.linf, e.maxerr, e.maxref,
           gate_label(e));
    if (strcmp(case_name, "sign_aligned") == 0) {
        size_t target = sign_target(n, profile->cutoff);
        size_t q = 0;
        while (q < count && rows[q] != target) ++q;
        if (q < count) {
            double er = hypot(got[target].re - ref[q].re,
                              got[target].im - ref[q].im);
            double rr = hypot(ref[q].re, ref[q].im);
            printf("HIGH_TARGET,%s,%s,%zu,%zu,%.17e,%.17e,%.17e\n",
                   case_name, profile->name, target, asym_start(n, target,
                   profile->cutoff), er, rr, er / (rr > 1.0e-300 ? rr : 1.0e-300));
        }
    }
    free(got);
    dht_plan_destroy(plan);
}

static void run_high_full(size_t n, const char *case_name,
                          const dht_complex *x, const dht_complex *ref,
                          const profile_spec *profile) {
    dht_plan *plan = dht_plan_create_profile(n, 1.0e-13, profile->terms,
                                              profile->cutoff, 1);
    if (plan == NULL) die("high-N full profile plan creation failed");
    dht_complex *got = alloc_complex(n);
    if (dht_apply(plan, x, got) != 0) die("high-N full dht_apply failed");
    metrics e = compute_metrics(got, ref, n);
    printf("HIGH_FULL,%s,%zu,%s,%u,%.1f,%zu,%.17e,%.17e,%.17e,%.17e,%s\n",
           case_name, n, profile->name, profile->terms, profile->cutoff,
           dht_direct_entries(plan), e.l2, e.linf, e.maxerr, e.maxref,
           gate_label(e));
    free(got);
    dht_plan_destroy(plan);
}

int main(void) {
    const size_t small_sizes[] = {32, 64, 128, 256};
    const size_t profile_count = sizeof(profiles) / sizeof(profiles[0]);
    const size_t row_count = sizeof(selected_rows) / sizeof(selected_rows[0]);
    mp_workspace w;
    mp_workspace_init(&w);

    printf("# SMALL,case,N,profile,K,z0,direct,normalized_l2,scaled_linf,max_abs_err,max_ref,gate\n");
    printf("# HIGH_ROWS,case,N,profile,K,z0,direct,selected_l2,selected_linf,max_abs_err,max_ref,row_gate\n");
    printf("# HIGH_FULL,case,N,profile,K,z0,direct,normalized_l2,scaled_linf,max_abs_err,max_ref,gate\n");
    printf("# HIGH_TARGET,case,profile,target_m,n0,abs_err,ref_abs,relative_row_err\n");

    for (size_t si = 0; si < sizeof(small_sizes) / sizeof(small_sizes[0]); ++si) {
        size_t n = small_sizes[si];
        dht_complex *x = alloc_complex(n);
        dht_complex *ref = alloc_complex(n);
        const char *common_names[] = {"alternating", "high_dynamic",
                                      "delta_n1", "delta_nNm1"};
        for (unsigned common = 0; common < 4; ++common) {
            if (common == 0) {
                fill_alternating(x, n);
            } else if (common == 1) {
                fill_high_dynamic(x, n);
            } else {
                fill_delta(x, n, common == 2 ? 1 : n - 1);
            }
            reference_full(x, n, ref, &w);
            for (size_t pi = 0; pi < profile_count; ++pi) {
                run_full_case(n, common_names[common], x, ref,
                              &profiles[pi], &w);
            }
        }

        for (size_t pi = 0; pi < profile_count; ++pi) {
            size_t target = sign_target(n, profiles[pi].cutoff);
            size_t n0, positive, negative;
            double residual_l1;
            fill_sign_aligned(x, n, target, &profiles[pi], &w, &n0,
                              &positive, &negative, &residual_l1);
            printf("SIGN,small,%zu,%s,%zu,%zu,%zu,%zu,%.17e\n", n,
                   profiles[pi].name, target, n0, positive, negative,
                   residual_l1);
            reference_full(x, n, ref, &w);
            run_full_case(n, "sign_aligned", x, ref, &profiles[pi], &w);
        }
        free(ref);
        free(x);
    }

    const size_t n = 65536;
    dht_complex *x = alloc_complex(n);
    dht_complex *ref_rows = alloc_complex(row_count);
    dht_complex *ref_full = alloc_complex(n);

    fill_alternating(x, n);
    reference_rows(x, n, selected_rows, row_count, ref_rows, &w);
    for (size_t pi = 0; pi < profile_count; ++pi) {
        run_high_rows(n, "alternating", x, ref_rows, selected_rows,
                      row_count, &profiles[pi]);
    }

    fill_high_dynamic(x, n);
    reference_rows(x, n, selected_rows, row_count, ref_rows, &w);
    for (size_t pi = 0; pi < profile_count; ++pi) {
        run_high_rows(n, "high_dynamic", x, ref_rows, selected_rows,
                      row_count, &profiles[pi]);
    }

    fill_delta(x, n, 1);
    reference_delta_full(n, 1, ref_full, &w);
    for (size_t pi = 0; pi < profile_count; ++pi) {
        run_high_full(n, "delta_n1", x, ref_full, &profiles[pi]);
    }

    fill_delta(x, n, n - 1);
    reference_delta_full(n, n - 1, ref_full, &w);
    for (size_t pi = 0; pi < profile_count; ++pi) {
        run_high_full(n, "delta_nNm1", x, ref_full, &profiles[pi]);
    }

    for (size_t pi = 0; pi < profile_count; ++pi) {
        size_t target = sign_target(n, profiles[pi].cutoff);
        size_t n0, positive, negative;
        double residual_l1;
        fill_sign_aligned(x, n, target, &profiles[pi], &w, &n0,
                          &positive, &negative, &residual_l1);
        printf("SIGN,high,%zu,%s,%zu,%zu,%zu,%zu,%.17e\n", n,
               profiles[pi].name, target, n0, positive, negative,
               residual_l1);
        reference_rows(x, n, selected_rows, row_count, ref_rows, &w);
        run_high_rows(n, "sign_aligned", x, ref_rows, selected_rows,
                      row_count, &profiles[pi]);
    }

    free(ref_full);
    free(ref_rows);
    free(x);
    mp_workspace_clear(&w);
    return 0;
}
