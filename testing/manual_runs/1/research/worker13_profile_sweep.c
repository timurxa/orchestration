#include "../src/dht.h"

#include <inttypes.h>
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
#define PROFILE_TOL 1.0e-13
#define BLOCK_RATIO 4u
#define GATE_L2 1.0e-13L
#define GATE_LINF 1.0e-12L

typedef struct {
    const char *name;
    unsigned terms;
    double cutoff;
} profile_spec;

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
    long double normalized_l2;
    long double scaled_linf;
    long double max_error;
    long double max_reference;
    size_t max_error_row;
} metrics;

static const profile_spec profiles[] = {
    {"K10_z30", 10u, 30.0},
    {"K11_z23", 11u, 23.0},
    {"K12_z20p5", 12u, 20.5},
    {"K12_z22", 12u, 22.0},
    {"K8_z48", 8u, 48.0},
};

static unsigned failures;

static void die(const char *message) {
    fprintf(stderr, "worker13_profile_sweep: %s\n", message);
    exit(2);
}

static void *checked_malloc(size_t bytes) {
    void *result = malloc(bytes);
    if (result == NULL) {
        die("out of memory");
    }
    return result;
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

/* Independent MPFR evaluator for the K-term expansion used by src/dht_asym.c. */
static void mp_asym_at(mp_workspace *w, size_t n, size_t m, size_t k,
                       unsigned terms) {
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
            mpfr_mul(w->term, w->term, w->sine, MPFR_RNDN);
        }
        mpfr_add(w->asym, w->asym, w->term, MPFR_RNDN);
        mpfr_mul(w->zpow, w->zpow, w->z, MPFR_RNDN);
    }
}

static size_t block_base(size_t m) {
    size_t result = 1;
    while (result <= m / BLOCK_RATIO) {
        result *= BLOCK_RATIO;
    }
    return result;
}

static size_t asym_start(size_t n, size_t m, double cutoff) {
    double threshold = cutoff * (double)n / (2.0 * M_PI);
    size_t lo = block_base(m);
    double raw = threshold / (double)lo;
    return raw >= (double)n ? n : (size_t)ceil(raw);
}

static size_t build_active_targets(size_t n, double cutoff, size_t *targets,
                                   size_t capacity) {
    size_t count = 0;
    for (size_t b = 1; b < n;) {
        if (asym_start(n, b, cutoff) < n && count < capacity) {
            targets[count++] = b;
        }
        if (b > SIZE_MAX / BLOCK_RATIO) {
            break;
        }
        b *= BLOCK_RATIO;
    }
    return count;
}

static size_t append_unique(size_t *rows, size_t count, size_t capacity,
                            size_t n, size_t row) {
    if (row >= n) {
        return count;
    }
    for (size_t q = 0; q < count; ++q) {
        if (rows[q] == row) {
            return count;
        }
    }
    if (count == capacity) {
        die("row-set capacity too small");
    }
    rows[count] = row;
    return count + 1;
}

static size_t build_selected_rows(size_t n, size_t *rows, size_t capacity) {
    static const size_t fixed[] = {
        0, 1, 3, 4, 15, 16, 63, 64, 255, 256,
        1023, 1024, 4095, 4096, 16383, 16384, 32768,
    };
    size_t count = 0;
    for (size_t q = 0; q < sizeof(fixed) / sizeof(fixed[0]); ++q) {
        count = append_unique(rows, count, capacity, n, fixed[q]);
    }
    count = append_unique(rows, count, capacity, n, n / 2);
    count = append_unique(rows, count, capacity, n, n - 1);
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

static void fill_delta(dht_complex *x, size_t n, size_t at) {
    memset(x, 0, n * sizeof(*x));
    x[at].re = 1.0;
    x[at].im = -0.375;
}

static sign_stats fill_sign_aligned(dht_complex *x, size_t n, size_t target,
                                    const profile_spec *profile,
                                    mp_workspace *w) {
    sign_stats stats;
    memset(&stats, 0, sizeof(stats));
    memset(x, 0, n * sizeof(*x));
    stats.n0 = asym_start(n, target, profile->cutoff);
    for (size_t k = stats.n0; k < n; ++k) {
        mp_j0_at(w, n, target, k);
        mp_asym_at(w, n, target, k, profile->terms);
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

static void reference_full(const dht_complex *x, size_t n, dht_complex *ref,
                           mp_workspace *w) {
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

static void reference_delta_rows(size_t n, size_t at, const size_t *rows,
                                 size_t count, dht_complex *ref,
                                 mp_workspace *w) {
    for (size_t q = 0; q < count; ++q) {
        mp_j0_at(w, n, rows[q], at);
        ref[q].re = mpfr_get_d(w->value, MPFR_RNDN);
        mpfr_mul_d(w->term, w->value, -0.375, MPFR_RNDN);
        ref[q].im = mpfr_get_d(w->term, MPFR_RNDN);
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
    result.normalized_l2 =
        sqrtl(error2 / (reference2 > 0.0L ? reference2 : 1.0L));
    result.scaled_linf =
        result.max_error /
        (result.max_reference > 1.0e-300L ? result.max_reference : 1.0e-300L);
    return result;
}

static int gate_passes(metrics result) {
    return result.normalized_l2 <= GATE_L2 && result.scaled_linf <= GATE_LINF;
}

static void print_plan(const profile_spec *profile, size_t n,
                       const dht_plan *plan) {
    printf("PLAN,%zu,%s,%u,%.1f,%u,%zu,%zu\n", n, profile->name,
           dht_asymptotic_terms(plan), dht_asymptotic_cutoff(plan),
           dht_block_ratio(plan), dht_direct_entries(plan),
           dht_plan_bytes(plan));
}

static long double target_relative_error(const dht_complex *got,
                                         const dht_complex *ref,
                                         size_t target, size_t ref_index) {
    long double dr = (long double)got[target].re - (long double)ref[ref_index].re;
    long double di = (long double)got[target].im - (long double)ref[ref_index].im;
    long double error = hypotl(dr, di);
    long double reference = hypotl((long double)ref[ref_index].re,
                                   (long double)ref[ref_index].im);
    return error / (reference > 1.0e-300L ? reference : 1.0e-300L);
}

static void print_result(const char *scope, const char *case_name, size_t n,
                         const profile_spec *profile, const dht_plan *plan,
                         size_t target, size_t n0, size_t band_count,
                         sign_stats stats, metrics result,
                         long double target_rel) {
    int pass = gate_passes(result);
    if (!pass) {
        ++failures;
    }
    printf("RESULT,%s,%s,%zu,%s,%u,%.1f,%u,%zu,%zu,%zu,%zu,%zu,"
           "%.17Le,%.17Le,%.17Le,%.17Le,%.17Le,%zu,%s\n",
           scope, case_name, n, profile->name, dht_asymptotic_terms(plan),
           dht_asymptotic_cutoff(plan), dht_block_ratio(plan), target, n0,
           band_count, dht_direct_entries(plan), dht_plan_bytes(plan),
           result.normalized_l2, result.scaled_linf, target_rel,
           stats.residual_l1, stats.residual_max, result.max_error_row,
           pass ? "PASS" : "FAIL");
    if (target != 0) {
        printf("SIGN,%s,%zu,%s,%zu,%zu,%zu,%zu,%zu,%.17Le,%.17Le\n",
               scope, n, profile->name, target, n0, stats.positive,
               stats.negative, stats.zero, stats.residual_l1,
               stats.residual_max);
    }
}

static void run_small(size_t n, const profile_spec *profile,
                      mp_workspace *w) {
    dht_complex *x = alloc_complex(n);
    dht_complex *got = alloc_complex(n);
    dht_complex *ref = alloc_complex(n);
    dht_plan *plan = dht_plan_create_profile_ex(
        n, PROFILE_TOL, profile->terms, profile->cutoff, 1, BLOCK_RATIO);
    if (plan == NULL) {
        die("small plan creation failed");
    }
    print_plan(profile, n, plan);

    fill_alternating(x, n);
    reference_full(x, n, ref, w);
    if (dht_apply(plan, x, got) != 0) die("small alternating apply failed");
    print_result("SMALL_FULL", "alternating", n, profile, plan, 0, 0, 0,
                 (sign_stats){0}, compute_metrics(got, ref, NULL, n), 0.0L);

    fill_high_dynamic(x, n);
    reference_full(x, n, ref, w);
    if (dht_apply(plan, x, got) != 0) die("small dynamic apply failed");
    print_result("SMALL_FULL", "high_dynamic", n, profile, plan, 0, 0, 0,
                 (sign_stats){0}, compute_metrics(got, ref, NULL, n), 0.0L);

    fill_delta(x, n, 1);
    reference_full(x, n, ref, w);
    if (dht_apply(plan, x, got) != 0) die("small delta_n1 apply failed");
    print_result("SMALL_FULL", "delta_n1", n, profile, plan, 0, 0, 0,
                 (sign_stats){0}, compute_metrics(got, ref, NULL, n), 0.0L);

    fill_delta(x, n, n - 1);
    reference_full(x, n, ref, w);
    if (dht_apply(plan, x, got) != 0) die("small delta_nNm1 apply failed");
    print_result("SMALL_FULL", "delta_nNm1", n, profile, plan, 0, 0, 0,
                 (sign_stats){0}, compute_metrics(got, ref, NULL, n), 0.0L);

    size_t targets[32];
    size_t target_count =
        build_active_targets(n, profile->cutoff, targets, 32);
    for (size_t q = 0; q < target_count; ++q) {
        size_t target = targets[q];
        sign_stats stats = fill_sign_aligned(x, n, target, profile, w);
        reference_full(x, n, ref, w);
        if (dht_apply(plan, x, got) != 0) {
            die("small sign-aligned apply failed");
        }
        metrics result = compute_metrics(got, ref, NULL, n);
        print_result("SMALL_SIGN", "residual_sign", n, profile, plan,
                     target, stats.n0, target_count, stats, result,
                     target_relative_error(got, ref, target, target));
    }

    dht_plan_destroy(plan);
    free(ref);
    free(got);
    free(x);
}

static void run_large(size_t n, const profile_spec *profile,
                      mp_workspace *w) {
    size_t rows[32];
    size_t row_count = build_selected_rows(n, rows, 32);
    size_t targets[32];
    size_t target_count =
        build_active_targets(n, profile->cutoff, targets, 32);
    dht_complex *x = alloc_complex(n);
    dht_complex *got = alloc_complex(n);
    dht_complex *ref = alloc_complex(row_count);
    dht_plan *plan = dht_plan_create_profile_ex(
        n, PROFILE_TOL, profile->terms, profile->cutoff, 1, BLOCK_RATIO);
    if (plan == NULL) {
        die("large plan creation failed");
    }
    print_plan(profile, n, plan);

    fill_alternating(x, n);
    reference_rows(x, n, rows, row_count, ref, w);
    if (dht_apply(plan, x, got) != 0) die("large alternating apply failed");
    print_result("LARGE_ROWS", "alternating", n, profile, plan, 0, 0,
                 target_count, (sign_stats){0},
                 compute_metrics(got, ref, rows, row_count), 0.0L);

    fill_high_dynamic(x, n);
    reference_rows(x, n, rows, row_count, ref, w);
    if (dht_apply(plan, x, got) != 0) die("large dynamic apply failed");
    print_result("LARGE_ROWS", "high_dynamic", n, profile, plan, 0, 0,
                 target_count, (sign_stats){0},
                 compute_metrics(got, ref, rows, row_count), 0.0L);

    fill_delta(x, n, 1);
    reference_delta_rows(n, 1, rows, row_count, ref, w);
    if (dht_apply(plan, x, got) != 0) die("large delta_n1 apply failed");
    print_result("LARGE_ROWS", "delta_n1", n, profile, plan, 0, 0,
                 target_count, (sign_stats){0},
                 compute_metrics(got, ref, rows, row_count), 0.0L);

    fill_delta(x, n, n - 1);
    reference_delta_rows(n, n - 1, rows, row_count, ref, w);
    if (dht_apply(plan, x, got) != 0) die("large delta_nNm1 apply failed");
    print_result("LARGE_ROWS", "delta_nNm1", n, profile, plan, 0, 0,
                 target_count, (sign_stats){0},
                 compute_metrics(got, ref, rows, row_count), 0.0L);

    for (size_t q = 0; q < target_count; ++q) {
        size_t target = targets[q];
        sign_stats stats = fill_sign_aligned(x, n, target, profile, w);
        reference_rows(x, n, rows, row_count, ref, w);
        if (dht_apply(plan, x, got) != 0) {
            die("large sign-aligned apply failed");
        }
        size_t target_index = row_index(rows, row_count, target);
        if (target_index == row_count) {
            die("active band target missing from selected rows");
        }
        metrics result = compute_metrics(got, ref, rows, row_count);
        print_result("LARGE_SIGN", "residual_sign", n, profile, plan,
                     target, stats.n0, target_count, stats, result,
                     target_relative_error(got, ref, target, target_index));
    }

    dht_plan_destroy(plan);
    free(ref);
    free(got);
    free(x);
}

int main(void) {
    static const size_t small_sizes[] = {64, 128, 256, 512};
    static const size_t large_sizes[] = {1024, 4096, 16384, 65536};
    const size_t profile_count = sizeof(profiles) / sizeof(profiles[0]);
    mp_workspace w;
    mp_workspace_init(&w);
    setvbuf(stdout, NULL, _IOLBF, 0);

    printf("# worker13 ratio-4 candidate sweep; MPFR precision=%u bits\n",
           MP_PREC);
    printf("# profiles: K10/z0=30, K11/z0=23, K12/z0=20.5, K12/z0=22, K8/z0=48\n");
    printf("# residual-sign target rows are every active ratio-4 band lower endpoint\n");
    printf("# RESULT,scope,case,N,profile,K,z0,ratio,target,n0,active_bands,direct_entries,plan_bytes,normalized_l2,scaled_linf,target_rel,residual_l1,residual_max,max_error_row,gate\n");
    printf("# SIGN,scope,N,profile,target,n0,positive,negative,zero,residual_l1,residual_max\n");
    printf("# PLAN,N,profile,K,z0,ratio,direct_entries,plan_bytes\n");

    for (size_t pi = 0; pi < profile_count; ++pi) {
        for (size_t ni = 0; ni < sizeof(small_sizes) / sizeof(small_sizes[0]); ++ni) {
            run_small(small_sizes[ni], &profiles[pi], &w);
        }
    }
    for (size_t pi = 0; pi < profile_count; ++pi) {
        for (size_t ni = 0; ni < sizeof(large_sizes) / sizeof(large_sizes[0]); ++ni) {
            run_large(large_sizes[ni], &profiles[pi], &w);
        }
    }

    mp_workspace_clear(&w);
    fprintf(stderr, "worker13_profile_sweep: gate_failures=%u\n", failures);
    return 0;
}
