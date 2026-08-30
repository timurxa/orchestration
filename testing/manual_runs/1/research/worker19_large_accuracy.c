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

#define TEST_N 65536u
#define MP_PREC 400u
#define PROFILE_TOL 1.0e-13
#define BLOCK_RATIO 4u
#define MAX_ROWS 128u
#define GATE_L2 1.0e-13L
#define GATE_LINF 1.0e-12L

typedef struct {
    const char *name;
    unsigned terms;
    double cutoff;
} profile_spec;

typedef struct {
    mpfr_t two_pi;
    mpfr_t pi_over_four;
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

typedef struct {
    long double max_l2;
    long double max_linf;
    long double max_target_relative;
    const char *max_l2_case;
    const char *max_linf_case;
    size_t max_linf_row;
    int failed;
} profile_summary;

static const profile_spec profiles[] = {
    {"K10_z30", 10u, 30.0},
    {"K11_z23", 11u, 23.0},
    {"K12_z21", 12u, 21.0},
};

static unsigned failures;

static void die(const char *message) {
    fprintf(stderr, "worker19_large_accuracy: %s\n", message);
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
    mpfr_inits2(MP_PREC, w->two_pi, w->pi_over_four, w->z, w->value,
                w->sumr, w->sumi, w->term, w->xr, w->xi, w->phase,
                w->denom, w->root, w->zpow, w->coeff, w->tmp, w->cosine,
                w->sine, w->asym, w->residual, w->abs_residual,
                (mpfr_ptr)0);
    mpfr_const_pi(w->two_pi, MPFR_RNDN);
    mpfr_mul_ui(w->two_pi, w->two_pi, 2, MPFR_RNDN);
    mpfr_div_ui(w->pi_over_four, w->two_pi, 8, MPFR_RNDN);
}

static void mp_workspace_clear(mp_workspace *w) {
    mpfr_clears(w->two_pi, w->pi_over_four, w->z, w->value, w->sumr,
                w->sumi, w->term, w->xr, w->xi, w->phase, w->denom,
                w->root, w->zpow, w->coeff, w->tmp, w->cosine, w->sine,
                w->asym, w->residual, w->abs_residual, (mpfr_ptr)0);
}

static void mp_set_argument(mp_workspace *w, size_t n, size_t m, size_t k) {
    mpfr_set_ui(w->z, m, MPFR_RNDN);
    mpfr_mul_ui(w->z, w->z, k, MPFR_RNDN);
    mpfr_mul(w->z, w->z, w->two_pi, MPFR_RNDN);
    mpfr_div_ui(w->z, w->z, n, MPFR_RNDN);
}

static void mp_j0_at(mp_workspace *w, size_t n, size_t m, size_t k) {
    mp_set_argument(w, n, m, k);
    mpfr_j0(w->value, w->z, MPFR_RNDN);
}

/* Independent MPFR evaluation of the asymptotic series in src/dht_asym.c. */
static void mp_asym_at(mp_workspace *w, size_t n, size_t m, size_t k,
                       unsigned terms) {
    mp_set_argument(w, n, m, k);
    mpfr_sub(w->phase, w->z, w->pi_over_four, MPFR_RNDN);
    mpfr_cos(w->cosine, w->phase, MPFR_RNDN);
    mpfr_sin(w->sine, w->phase, MPFR_RNDN);

    mpfr_mul(w->denom, w->two_pi, w->z, MPFR_RNDN);
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

/* This intentionally mirrors the production source's double boundary math. */
static size_t asym_start(size_t n, size_t m, double cutoff) {
    double threshold = cutoff * (double)n / (2.0 * M_PI);
    size_t lo = block_base(m);
    double raw = threshold / (double)lo;
    return raw >= (double)n ? n : (size_t)ceil(raw);
}

static size_t first_active_row(size_t n, double cutoff) {
    for (size_t m = 1; m < n; ++m) {
        if (asym_start(n, m, cutoff) < n) {
            return m;
        }
    }
    return n;
}

static size_t append_row(size_t *rows, size_t count, size_t row, size_t n) {
    if (row >= n) {
        return count;
    }
    for (size_t q = 0; q < count; ++q) {
        if (rows[q] == row) {
            return count;
        }
    }
    if (count == MAX_ROWS) {
        die("row-set capacity too small");
    }
    rows[count] = row;
    return count + 1;
}

static size_t append_neighborhood(size_t *rows, size_t count, size_t center,
                                  size_t radius, size_t n) {
    for (long delta = -(long)radius; delta <= (long)radius; ++delta) {
        if (delta < 0 && center < (size_t)(-delta)) {
            continue;
        }
        size_t row = delta < 0 ? center - (size_t)(-delta)
                               : center + (size_t)delta;
        count = append_row(rows, count, row, n);
    }
    return count;
}

/* make_selected_rows stores the list for the simple C driver below. */
static size_t selected_rows[MAX_ROWS];

static size_t make_selected_rows(size_t n) {
    static const size_t random_rows[] = {
        733, 12023, 17489, 23111, 29491, 36523, 40127, 45119,
        50321, 55733, 61211, 65077, 65521,
    };
    size_t count = 0;
    for (size_t lo = 1; lo < n;) {
        size_t hi = lo <= n / BLOCK_RATIO ? lo * BLOCK_RATIO : n;
        count = append_neighborhood(selected_rows, count, lo, 1, n);
        count = append_neighborhood(selected_rows, count, hi, 1, n);
        if (hi == n) {
            break;
        }
        lo = hi;
    }
    for (size_t pi = 0; pi < sizeof(profiles) / sizeof(profiles[0]); ++pi) {
        count = append_neighborhood(
            selected_rows, count, first_active_row(n, profiles[pi].cutoff), 3,
            n);
    }
    for (size_t q = 0; q < sizeof(random_rows) / sizeof(random_rows[0]); ++q) {
        count = append_row(selected_rows, count, random_rows[q], n);
    }
    count = append_neighborhood(selected_rows, count, n / 2, 2, n);
    count = append_row(selected_rows, count, n - 1, n);
    return count;
}

static uint64_t next_u64(uint64_t *state) {
    uint64_t x = *state;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *state = x;
    return x * UINT64_C(2685821657736338717);
}

static double uniform_signed(uint64_t *state) {
    return 2.0 * (double)(next_u64(state) >> 11) * 0x1.0p-53 - 1.0;
}

static void fill_common_input(dht_complex *x, size_t n, unsigned kind) {
    uint64_t state = UINT64_C(0x8f3c2d1e7a6b5948);
    for (size_t k = 0; k < n; ++k) {
        double t = (double)k / (double)n;
        if (kind == 0) {
            x[k].re = uniform_signed(&state);
            x[k].im = uniform_signed(&state);
        } else if (kind == 1) {
            double sign = (k & 1u) ? -1.0 : 1.0;
            x[k].re = sign;
            x[k].im = -sign * (0.25 + 0.5 * t);
        } else if (kind == 2) {
            int exponent = (int)((37u * (unsigned)k + 17u) % 601u) - 300;
            double magnitude = ldexp(1.0, exponent);
            double sign = (k & 1u) ? -1.0 : 1.0;
            x[k].re = sign * magnitude;
            x[k].im = -sign * magnitude * (0.25 + 0.5 * t);
        } else {
            x[k].re = sin(2.0 * M_PI *
                          (0.125 * (double)k + 0.00031 * (double)k *
                           (double)k));
            x[k].im = cos(2.0 * M_PI *
                          (0.237 * (double)k - 0.00017 * (double)k *
                           (double)k));
        }
    }
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
        long double error = hypotl(dr, di);
        long double reference = hypotl((long double)ref[q].re,
                                       (long double)ref[q].im);
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
    return result.normalized_l2 <= GATE_L2 &&
           result.scaled_linf <= GATE_LINF;
}

static long double target_relative_error(const dht_complex *got,
                                         const dht_complex *ref, size_t target,
                                         const size_t *rows, size_t count) {
    for (size_t q = 0; q < count; ++q) {
        if (rows[q] == target) {
            long double dr = (long double)got[target].re - ref[q].re;
            long double di = (long double)got[target].im - ref[q].im;
            long double error = hypotl(dr, di);
            long double reference = hypotl((long double)ref[q].re,
                                           (long double)ref[q].im);
            return error /
                   (reference > 1.0e-300L ? reference : 1.0e-300L);
        }
    }
    die("target row missing from selected rows");
    return 0.0L;
}

static void update_summary(profile_summary *summary, const char *case_name,
                           metrics result, long double target_rel) {
    int pass = gate_passes(result);
    if (!pass) {
        ++failures;
        summary->failed = 1;
    }
    if (result.normalized_l2 > summary->max_l2) {
        summary->max_l2 = result.normalized_l2;
        summary->max_l2_case = case_name;
    }
    if (result.scaled_linf > summary->max_linf) {
        summary->max_linf = result.scaled_linf;
        summary->max_linf_case = case_name;
        summary->max_linf_row = result.max_error_row;
    }
    if (target_rel > summary->max_target_relative) {
        summary->max_target_relative = target_rel;
    }
}

static void print_result(const char *scope, const char *case_name,
                         const profile_spec *profile, const dht_plan *plan,
                         const size_t *rows, size_t row_count,
                         const dht_complex *got, const dht_complex *ref,
                         sign_stats stats, size_t target,
                         profile_summary *summary) {
    metrics result = compute_metrics(got, ref, rows, row_count);
    long double target_rel = target == SIZE_MAX
                                 ? 0.0L
                                 : target_relative_error(got, ref, target,
                                                         rows, row_count);
    int pass = gate_passes(result);
    update_summary(summary, case_name, result, target_rel);
    printf("RESULT,scope=%s,case=%s,profile=%s,N=%u,K=%u,z0=%.1f,ratio=%u,"
           "rows=%zu,target=%s,n0=%zu,rel_l2=%.18Le,scaled_linf=%.18Le,"
           "target_rel=%.18Le,max_error=%.18Le,max_ref=%.18Le,max_row=%zu,"
           "residual_l1=%.18Le,residual_max=%.18Le,sign_plus=%zu,"
           "sign_minus=%zu,sign_zero=%zu,gate=%s,direct=%zu,plan_bytes=%zu\n",
           scope, case_name, profile->name, TEST_N,
           dht_asymptotic_terms(plan), dht_asymptotic_cutoff(plan),
           dht_block_ratio(plan), row_count,
           target == SIZE_MAX ? "-" : "set", stats.n0,
           result.normalized_l2, result.scaled_linf, target_rel,
           result.max_error, result.max_reference, result.max_error_row,
           stats.residual_l1, stats.residual_max, stats.positive,
           stats.negative, stats.zero, pass ? "PASS" : "FAIL",
           dht_direct_entries(plan), dht_plan_bytes(plan));
}

static void run_common_case(const char *case_name, unsigned kind,
                            const size_t *rows, size_t row_count,
                            dht_complex *x, dht_complex *got,
                            dht_complex *ref, dht_plan **plans,
                            profile_summary *summaries, mp_workspace *w) {
    fill_common_input(x, TEST_N, kind);
    reference_rows(x, TEST_N, rows, row_count, ref, w);
    for (size_t pi = 0; pi < sizeof(profiles) / sizeof(profiles[0]); ++pi) {
        if (dht_apply(plans[pi], x, got) != 0) {
            die("common-case apply failed");
        }
        print_result("COMMON_ROWS", case_name, &profiles[pi], plans[pi], rows,
                     row_count, got, ref, (sign_stats){0}, SIZE_MAX,
                     &summaries[pi]);
    }
}

static void run_sign_case(const profile_spec *profile, dht_plan *plan,
                          const size_t *rows, size_t row_count,
                          size_t target, dht_complex *x, dht_complex *got,
                          dht_complex *ref, profile_summary *summary,
                          mp_workspace *w) {
    sign_stats stats = fill_sign_aligned(x, TEST_N, target, profile, w);
    reference_rows(x, TEST_N, rows, row_count, ref, w);
    if (dht_apply(plan, x, got) != 0) {
        die("sign-aligned apply failed");
    }
    char case_name[64];
    snprintf(case_name, sizeof(case_name), "residual_sign_m%zu", target);
    print_result("SIGN_ROWS", case_name, profile, plan, rows, row_count, got,
                 ref, stats, target, summary);
}

int main(void) {
    const size_t profile_count = sizeof(profiles) / sizeof(profiles[0]);
    const size_t row_count = make_selected_rows(TEST_N);
    dht_complex *x = alloc_complex(TEST_N);
    dht_complex *got = alloc_complex(TEST_N);
    dht_complex *ref = alloc_complex(row_count);
    dht_plan *plans[sizeof(profiles) / sizeof(profiles[0])];
    profile_summary summaries[sizeof(profiles) / sizeof(profiles[0])];
    mp_workspace w;

    memset(summaries, 0, sizeof(summaries));
    mp_workspace_init(&w);
    setvbuf(stdout, NULL, _IOLBF, 0);
    printf("# worker19 independent large-N checker\n");
    printf("# N=%u MPFR precision=%u bits MPFR=%s GMP=%s\n", TEST_N,
           MP_PREC, mpfr_get_version(), gmp_version);
    printf("# reference: MPFR mpfr_j0 plus 400-bit MPFR accumulation, rounded to binary64\n");
    printf("# profiles: K10/z0=30, K11/z0=23, K12/z0=21; block ratio=%u; threads=1\n",
           BLOCK_RATIO);
    printf("# selected rows include every ratio-4 edge neighborhood, transition neighborhoods, m=N/2, and fixed deterministic random rows\n");
    printf("# gates: normalized_l2 <= %.1Le and scaled_linf <= %.1Le\n",
           GATE_L2, GATE_LINF);

    for (size_t pi = 0; pi < profile_count; ++pi) {
        plans[pi] = dht_plan_create_profile_ex(
            TEST_N, PROFILE_TOL, profiles[pi].terms, profiles[pi].cutoff, 1,
            BLOCK_RATIO);
        if (plans[pi] == NULL) {
            die("plan creation failed");
        }
        printf("PLAN,profile=%s,K=%u,z0=%.1f,ratio=%u,direct=%zu,bytes=%zu,"
               "first_active=%zu,n0_at_first=%zu\n",
               profiles[pi].name, dht_asymptotic_terms(plans[pi]),
               dht_asymptotic_cutoff(plans[pi]), dht_block_ratio(plans[pi]),
               dht_direct_entries(plans[pi]), dht_plan_bytes(plans[pi]),
               first_active_row(TEST_N, profiles[pi].cutoff),
               asym_start(TEST_N, first_active_row(TEST_N, profiles[pi].cutoff),
                          profiles[pi].cutoff));
    }

    run_common_case("random", 0, selected_rows, row_count, x, got, ref,
                    plans, summaries, &w);
    run_common_case("alternating", 1, selected_rows, row_count, x, got, ref,
                    plans, summaries, &w);
    run_common_case("high_dynamic", 2, selected_rows, row_count, x, got, ref,
                    plans, summaries, &w);
    run_common_case("chirp", 3, selected_rows, row_count, x, got, ref, plans,
                    summaries, &w);

    /* One cutoff-adjacent target and one later block target per profile. */
    for (size_t pi = 0; pi < profile_count; ++pi) {
        size_t first = first_active_row(TEST_N, profiles[pi].cutoff);
        size_t later = first <= TEST_N / 64 ? first * 16 : first;
        run_sign_case(&profiles[pi], plans[pi], selected_rows, row_count, first,
                      x, got, ref, &summaries[pi], &w);
        if (later != first && later < TEST_N) {
            run_sign_case(&profiles[pi], plans[pi], selected_rows, row_count,
                          later, x, got, ref, &summaries[pi], &w);
        }
    }

    printf("SUMMARY,profile,K,z0,max_rel_l2,max_scaled_linf,max_target_rel,"
           "max_l2_case,max_linf_case,max_linf_row,gate\n");
    for (size_t pi = 0; pi < profile_count; ++pi) {
        printf("SUMMARY,%s,%u,%.1f,%.18Le,%.18Le,%.18Le,%s,%s,%zu,%s\n",
               profiles[pi].name, profiles[pi].terms, profiles[pi].cutoff,
               summaries[pi].max_l2, summaries[pi].max_linf,
               summaries[pi].max_target_relative,
               summaries[pi].max_l2_case == NULL ? "-"
                                                   : summaries[pi].max_l2_case,
               summaries[pi].max_linf_case == NULL
                   ? "-"
                   : summaries[pi].max_linf_case,
               summaries[pi].max_linf_row,
               summaries[pi].failed ? "FAIL" : "PASS");
    }

    for (size_t pi = 0; pi < profile_count; ++pi) {
        dht_plan_destroy(plans[pi]);
    }
    mp_workspace_clear(&w);
    free(ref);
    free(got);
    free(x);
    fprintf(stderr, "worker19_large_accuracy: gate_failures=%u\n", failures);
    return failures == 0 ? 0 : 1;
}
