#ifndef DHT_H
#define DHT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double re;
    double im;
} dht_complex;

typedef struct dht_plan dht_plan;

/* Create a reusable plan for the direct-grid order-0 transform.
 * tol controls the asymptotic approximation profile; threads is the FFTW
 * worker count (0 selects one worker). */
dht_plan *dht_plan_create(size_t n, double tol, unsigned threads);
/* Experimental profile constructor used by the benchmark harness.  It keeps
 * the same API and lets the search compare asymptotic term/cutoff pairs. */
dht_plan *dht_plan_create_profile(size_t n, double tol, unsigned terms,
                                   double cutoff, unsigned threads);
dht_plan *dht_plan_create_profile_ex(size_t n, double tol, unsigned terms,
                                      double cutoff, unsigned threads,
                                      unsigned block_ratio);
void dht_plan_destroy(dht_plan *plan);

/* y[m] = sum_{k=0}^{n-1} x[k] J0(2*pi*m*k/n), m=0..n-1. */
int dht_apply(const dht_plan *plan, const dht_complex *x, dht_complex *y);

size_t dht_size(const dht_plan *plan);
double dht_tolerance(const dht_plan *plan);
unsigned dht_asymptotic_terms(const dht_plan *plan);
double dht_asymptotic_cutoff(const dht_plan *plan);
size_t dht_direct_entries(const dht_plan *plan);
size_t dht_plan_bytes(const dht_plan *plan);
unsigned dht_block_ratio(const dht_plan *plan);

#ifdef __cplusplus
}
#endif

#endif
