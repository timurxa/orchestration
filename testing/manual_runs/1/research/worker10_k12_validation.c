#include "../src/dht.h"

#include <math.h>
#include <mpfr.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.141592653589793238462643383279502884
#endif

#define MP_PREC 400
#define PROFILE_TERMS 12u
#define PROFILE_CUTOFF 18.0
#define PROFILE_RATIO 4u
#define PROFILE_TOL 1.0e-13

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
    mpfr_t sine;
    mpfr_t asym;
    mpfr_t residual;
    mpfr_t abs_residual;
} mp_workspace;

typedef struct {
    size_t n0;
    size_t positive;
    size_t negative;
    size_t zero;
    long double residual_l1;
    long double residual_max;
} sign_stats;

typedef struct {
    long double error_l2;
    long double normalized_l2;
    long double scaled_linf;
    long double max_error;
    long double max_reference;
    size_t max_error_row;
} metrics;

static void die(const char *message) {
    fprintf(stderr, "worker10_k12_validation: %s\n", message);
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
                w->root, w->zpow, w->coeff, w->tmp, w->cosine, w->sine,
                w->asym, w->residual, w->abs_residual, (mpfr_ptr)0);
    mpfr_const_pi(w->pi2, MPFR_RNDN);
    mpfr_mul_ui(w->pi2, w->pi2, 2, MPFR_RNDN);
    mpfr_div_ui(w->pi4, w->pi2, 8, MPFR_RNDN);
}

static void mp_workspace_clear(mp_workspace *w) {
    mpfr_clears(w->pi2, w->pi4, w->z, w->value, w->sumr, w->sumi,
                w->term, w->xr, w->xi, w->phase, w->denom, w->root,
                w->zpow, w->coeff, w->tmp, w->cosine, w->sine, w->asym,
                w->residual, w->abs_residual, (mpfr_ptr)0);
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

/* Independent MPFR evaluation of the K-term large-z expansion used by the
 * candidate.  The candidate's source is not included in this calculation. */
static void mp_asym_at(mp_workspace *w, size_t n, size_t m, size_t k) {
    mp_set_argument(w, n, m, k);
    mpfr_sub(w->phase, w->z, w->pi4, MPFR_RNDN);
    mpfr_cos(w->cosine, w->phase, MPFR_RNDN);
    mpfr_sin(w->sine, w->phase, MPFR_RNDN);

    mpfr_mul(w->denom, w->pi2, w->z, MPFR_RNDN);
    mpfr_div_ui(w->denom, w->denom, 2, MPFR_RNDN);
    mpfr_set_ui(w->tmp, 2, MPFR_RNDN);
    mpfr_div(w->tmp, w->tmp, w->denom, MPFR_RNDN);
    mpfr_sqrt(w->root, w->tmp, MPFR_RNDN);
    mpfr_set_ui(w->zpow, 1, MPFR_RNDN);
    mpfr_set_ui(w->coeff, 1, MPFR_RNDN);
    mpfr_set_zero(w->asym, 0);

    for (unsigned q = 0; q < PROFILE_TERMS; ++q) {
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
            mpfr_mul(w->term, w->term, w->sine, MPFR_RNDN);
        }
        mpfr_add(w->asym, w->asym, w->term, MPFR_RNDN);
        mpfr_mul(w->zpow, w->zpow, w->z, MPFR_RNDN);
    }
}

static size_t block_base(size_t x) {
    size_t p = 1;
    while (p <= x / PROFILE_RATIO) {
        p *= PROFILE_RATIO;
    }
    return p;
}

static size_t asym_start(size_t n, size_t m) {
    double threshold = PROFILE_CUTOFF * (double)n / (2.0 * M_PI);
    size_t lo = block_base(m);
    size_t n0 = (size_t)ceil(threshold / (double)lo);
    return n0 < n ? n0 : n;
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
        int exponent = (int)((37u * (unsigned)k + 17u) % 601u) - 300;
        double magnitude = ldexp(1.0, exponent);
        double sign = (k & 1u) ? -1.0 : 1.0;
        double t = n > 1 ? (double)k / (double)(n - 1) : 0.0;
        x[k].re = sign * magnitude;
        x[k].im = -sign * magnitude * (0.25 + 0.5 * t);
    }
}

static sign_stats fill_sign_aligned(dht_complex *x, size_t n, size_t target_m,
                                    mp_workspace *w) {
    sign_stats stats;
    memset(&stats, 0, sizeof(stats));
    memset(x, 0, n * sizeof(*x));
    stats.n0 = asym_start(n, target_m);
    for (size_t k = stats.n0; k < n; ++k) {
        mp_j0_at(w, n, target_m, k);
        mp_asym_at(w, n, target_m, k);
        mpfr_sub(w->residual, w->asym, w->value, MPFR_RNDN);
        mpfr_abs(w->abs_residual, w->residual, MPFR_RNDN);
        long double magnitude = mpfr_get_ld(w->abs_residual, MPFR_RNDN);
        stats.residual_l1 += magnitude;
        if (magnitude > stats.residual_max) {
            stats.residual_max = magnitude;
        }
        int sign = mpfr_sgn(w->residual);
        if (sign < 0) {
            x[k].re = -1.0;
            x[k].im = 0.375;
            ++stats.negative;
        } else {
            x[k].re = 1.0;
            x[k].im = -0.375;
            if (sign == 0) {
                ++stats.zero;
            } else {
                ++stats.positive;
            }
        }
    }
    return stats;
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
                               const size_t *rows, size_t count) {
    long double error2 = 0.0L;
    long double reference2 = 0.0L;
    metrics result;
    result.max_error = 0.0L;
    result.max_reference = 0.0L;
    result.max_error_row = 0;
    for (size_t q = 0; q < count; ++q) {
        size_t row = rows == NULL ? q : rows[q];
        long double dr = (long double)got[row].re - (long double)ref[q].re;
        long double di = (long double)got[row].im - (long double)ref[q].im;
        long double rr = (long double)ref[q].re;
        long double ri = (long double)ref[q].im;
        long double error = hypotl(dr, di);
        long double reference = hypotl(rr, ri);
        error2 += error * error;
        reference2 += reference * reference;
        if (error > result.max_error) {
            result.max_error = error;
            result.max_error_row = row;
        }
        if (reference > result.max_reference) {
            result.max_reference = reference;
        }
    }
    result.error_l2 = sqrtl(error2);
    result.normalized_l2 =
        sqrtl(error2 / (reference2 > 0.0L ? reference2 : 1.0L));
    result.scaled_linf =
        result.max_error /
        (result.max_reference > 1.0e-300L ? result.max_reference : 1.0e-300L);
    return result;
}

static int gate_passes(metrics e) {
    return e.normalized_l2 <= 1.0e-13L && e.scaled_linf <= 1.0e-12L;
}

static void print_plan(const dht_plan *plan, size_t n) {
    printf("PLAN,%zu,%u,%.1f,%u,%zu,%zu\n", n,
           dht_asymptotic_terms(plan), dht_asymptotic_cutoff(plan),
           dht_block_ratio(plan), dht_direct_entries(plan),
           dht_plan_bytes(plan));
}

static void apply_and_print(const dht_plan *plan, size_t n, const char *scope,
                            const char *case_name, const dht_complex *x,
                            dht_complex *got, const dht_complex *ref,
                            const size_t *rows, size_t count) {
    if (dht_apply(plan, x, got) != 0) {
        die("dht_apply failed");
    }
    metrics e = compute_metrics(got, ref, rows, count);
    printf("RESULT,%s,%zu,%s,%zu,%u,%.1f,%u,%zu,%zu,%.17Le,%.17Le,%.17Le,%.17Le,%.17Le,%zu,%s\n",
           scope, n, case_name, count, dht_asymptotic_terms(plan),
           dht_asymptotic_cutoff(plan), dht_block_ratio(plan),
           dht_direct_entries(plan), dht_plan_bytes(plan), e.error_l2,
           e.normalized_l2, e.scaled_linf, e.max_error, e.max_reference,
           e.max_error_row, gate_passes(e) ? "PASS" : "FAIL");
}

static void print_sign(size_t n, const char *scope, size_t target_m,
                       sign_stats stats) {
    printf("SIGN,%s,%zu,%zu,%zu,%zu,%zu,%zu,%.17Le,%.17Le\n", scope, n,
           target_m, stats.n0, stats.positive, stats.negative, stats.zero,
           stats.residual_l1, stats.residual_max);
}

static void print_target(size_t n, const char *scope, size_t target_m,
                         size_t n0, const dht_complex *got,
                         const dht_complex *ref, size_t ref_index) {
    long double dr = (long double)got[target_m].re - ref[ref_index].re;
    long double di = (long double)got[target_m].im - ref[ref_index].im;
    long double error = hypotl(dr, di);
    long double reference =
        hypotl((long double)ref[ref_index].re, (long double)ref[ref_index].im);
    long double relative =
        error / (reference > 1.0e-300L ? reference : 1.0e-300L);
    printf("TARGET,%s,%zu,%zu,%zu,%zu,%.17Le,%.17Le,%.17Le\n", scope, n,
           target_m, n0, ref_index, error, reference, relative);
}

static size_t append_row(size_t *rows, size_t count, size_t n, size_t row) {
    if (row >= n) {
        return count;
    }
    for (size_t q = 0; q < count; ++q) {
        if (rows[q] == row) {
            return count;
        }
    }
    rows[count] = row;
    return count + 1;
}

static size_t build_large_rows(size_t n, size_t *rows) {
    static const size_t fixed[] = {
        0, 1, 3, 4, 15, 16, 63, 64, 255, 256,
        1023, 1024, 4095, 4096, 16383, 16384, 32768,
    };
    size_t count = 0;
    for (size_t q = 0; q < sizeof(fixed) / sizeof(fixed[0]); ++q) {
        count = append_row(rows, count, n, fixed[q]);
    }
    count = append_row(rows, count, n, n / 2);
    count = append_row(rows, count, n, n - 1);
    return count;
}

static size_t row_index(const size_t *rows, size_t count, size_t target) {
    for (size_t q = 0; q < count; ++q) {
        if (rows[q] == target) {
            return q;
        }
    }
    return count;
}

static void run_small(size_t n, mp_workspace *w) {
    dht_complex *x = alloc_complex(n);
    dht_complex *got = alloc_complex(n);
    dht_complex *ref = alloc_complex(n);
    dht_plan *plan = dht_plan_create_profile_ex(
        n, PROFILE_TOL, PROFILE_TERMS, PROFILE_CUTOFF, 1, PROFILE_RATIO);
    if (plan == NULL) {
        die("small plan creation failed");
    }
    print_plan(plan, n);

    fill_alternating(x, n);
    reference_full(x, n, ref, w);
    apply_and_print(plan, n, "SMALL_FULL", "alternating", x, got, ref,
                    NULL, n);

    fill_high_dynamic(x, n);
    reference_full(x, n, ref, w);
    apply_and_print(plan, n, "SMALL_FULL", "high_dynamic", x, got, ref,
                    NULL, n);

    fill_delta(x, n, 1);
    reference_full(x, n, ref, w);
    apply_and_print(plan, n, "SMALL_FULL", "delta_n1", x, got, ref, NULL,
                    n);

    fill_delta(x, n, n - 1);
    reference_full(x, n, ref, w);
    apply_and_print(plan, n, "SMALL_FULL", "delta_nNm1", x, got, ref, NULL,
                    n);

    sign_stats stats = fill_sign_aligned(x, n, 4, w);
    print_sign(n, "small", 4, stats);
    reference_full(x, n, ref, w);
    apply_and_print(plan, n, "SMALL_FULL", "sign_m4", x, got, ref, NULL,
                    n);
    print_target(n, "small", 4, stats.n0, got, ref, 4);

    dht_plan_destroy(plan);
    free(ref);
    free(got);
    free(x);
}

static void run_large(size_t n, mp_workspace *w) {
    size_t rows[32];
    size_t row_count = build_large_rows(n, rows);
    dht_complex *x = alloc_complex(n);
    dht_complex *got = alloc_complex(n);
    dht_complex *ref_rows = alloc_complex(row_count);
    dht_complex *ref_full = alloc_complex(n);
    dht_plan *plan = dht_plan_create_profile_ex(
        n, PROFILE_TOL, PROFILE_TERMS, PROFILE_CUTOFF, 1, PROFILE_RATIO);
    if (plan == NULL) {
        die("large plan creation failed");
    }
    print_plan(plan, n);

    fill_alternating(x, n);
    reference_rows(x, n, rows, row_count, ref_rows, w);
    apply_and_print(plan, n, "LARGE_ROWS", "alternating", x, got, ref_rows,
                    rows, row_count);

    fill_high_dynamic(x, n);
    reference_rows(x, n, rows, row_count, ref_rows, w);
    apply_and_print(plan, n, "LARGE_ROWS", "high_dynamic", x, got, ref_rows,
                    rows, row_count);

    sign_stats stats = fill_sign_aligned(x, n, 4, w);
    print_sign(n, "large", 4, stats);
    reference_rows(x, n, rows, row_count, ref_rows, w);
    apply_and_print(plan, n, "LARGE_ROWS", "sign_m4", x, got, ref_rows,
                    rows, row_count);
    size_t target_index = row_index(rows, row_count, 4);
    if (target_index == row_count) {
        die("target row missing from large row set");
    }
    print_target(n, "large", 4, stats.n0, got, ref_rows, target_index);

    fill_delta(x, n, 1);
    reference_delta_full(n, 1, ref_full, w);
    apply_and_print(plan, n, "LARGE_FULL", "delta_n1", x, got, ref_full,
                    NULL, n);

    fill_delta(x, n, n - 1);
    reference_delta_full(n, n - 1, ref_full, w);
    apply_and_print(plan, n, "LARGE_FULL", "delta_nNm1", x, got, ref_full,
                    NULL, n);

    dht_plan_destroy(plan);
    free(ref_full);
    free(ref_rows);
    free(got);
    free(x);
}

int main(void) {
    static const size_t small_sizes[] = {64, 128, 256, 512};
    static const size_t large_sizes[] = {
        1024, 2048, 4096, 8192, 16384, 32768, 65536,
    };
    mp_workspace w;
    mp_workspace_init(&w);
    setvbuf(stdout, NULL, _IOLBF, 0);

    printf("# worker10 candidate validation; MPFR precision=%u bits; approx 120 decimal digits\n",
           MP_PREC);
    printf("# candidate terms=%u cutoff=%.1f block_ratio=%u tol=%.1e threads=1\n",
           PROFILE_TERMS, PROFILE_CUTOFF, PROFILE_RATIO, PROFILE_TOL);
    printf("# MPFR exact reference is rounded to binary64 before metrics\n");
    printf("# PLAN,N,terms,cutoff,block_ratio,direct_entries,plan_bytes\n");
    printf("# SIGN,scope,N,target_m,n0,positive,negative,zero,residual_l1,residual_max\n");
    printf("# TARGET,scope,N,target_m,n0,ref_index,abs_error,ref_abs,relative_error\n");
    printf("# RESULT,scope,N,case,row_count,terms,cutoff,block_ratio,direct_entries,plan_bytes,error_l2,normalized_l2,scaled_linf,max_abs_error,max_ref_abs,max_error_row,gate\n");

    for (size_t q = 0; q < sizeof(small_sizes) / sizeof(small_sizes[0]); ++q) {
        run_small(small_sizes[q], &w);
    }
    for (size_t q = 0; q < sizeof(large_sizes) / sizeof(large_sizes[0]); ++q) {
        run_large(large_sizes[q], &w);
    }

    mp_workspace_clear(&w);
    return 0;
}
