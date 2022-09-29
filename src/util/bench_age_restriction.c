/**
 * @file util/bench_age_restriction.c
 * @brief Measure Commit, Attest, Verify, Derive and Compare
 * @author Özgür Kesim
 *
 * compile in exchange/src/util with
 *
 * gcc benc_age_restriction.c \
 *    -lgnunetutil -lgnunetjson -lsodium -ljansson \
 *    -L/usr/lib/x86_64-linux-gnu -lmicrohttpd -ltalerutil \
 *    -I../include \
 *    -o bench_age_restriction
 *
 */
#include "platform.h"
#include <math.h>
#include <gnunet/gnunet_util_lib.h>
#include <taler/taler_util.h>
#include <taler/taler_crypto_lib.h>

static struct TALER_AgeMask
  age_mask = { .bits = 1
                       | 1 << 8 | 1 << 10 | 1 << 12
                       | 1 << 14 | 1 << 16 | 1 << 18 | 1 << 21 };

extern uint8_t
get_age_group (
  const struct TALER_AgeMask *mask,
  uint8_t age);

/**
 * Encodes the age mask into a string, like "8:10:12:14:16:18:21"
 */
char *
age_mask_to_string (
  const struct TALER_AgeMask *m)
{
  uint32_t bits = m->bits;
  unsigned int n = 0;
  char *buf = GNUNET_malloc (32 * 3); // max characters possible
  char *pos = buf;

  if (NULL == buf)
  {
    return buf;
  }

  while (bits != 0)
  {
    bits >>= 1;
    n++;
    if (0 == (bits & 1))
    {
      continue;
    }

    if (n > 9)
    {
      *(pos++) = '0' + n / 10;
    }
    *(pos++) = '0' + n % 10;

    if (0 != (bits >> 1))
    {
      *(pos++) = ':';
    }
  }
  return buf;
}


#define ITER 2000

double
average (long *times, size_t size)
{
  double mean = 0.0;
  for (int i = 0; i < size; i++)
  {
    mean += times[i];
  }
  return mean / size;
}


double
stdev (long *times, size_t size)
{
  double mean = average (times, size);
  double V = 0.0;
  for (int i = 0; i < size; i++)
  {
    double d = times[i] - mean;
    d *= d;
    V += d;
  }
  return sqrt (V / size);
}


#define pr(n,t, i) printf ("%10s (%dx):\t%.2f ± %.2fµs\n", (n), i, average ( \
                             &t[0], ITER) / 1000, stdev (&t[0], ITER) / 1000); \
  i = 0;

#define starttime clock_gettime (CLOCK_MONOTONIC, &tstart)
#define stoptime clock_gettime (CLOCK_MONOTONIC, &tend); \
  times[i] = ((long) tend.tv_sec * 1000 * 1000 * 1000 + tend.tv_nsec) \
             - ((long) tstart.tv_sec * 1000 * 1000 * 1000 + tstart.tv_nsec);


int
main (int argc,
      const char *const argv[])
{
  struct timespec tstart = {0,0}, tend = {0,0};
  enum GNUNET_GenericReturnValue ret;
  struct TALER_AgeCommitmentProof acp = {0};
  uint8_t age = 21;
  uint8_t age_group = get_age_group (&age_mask, age);
  struct GNUNET_HashCode seed;
  long times[ITER] = {0};
  int i = 0;

  //  commit
  for (; i < ITER; i++)
  {
    starttime;
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &seed,
                                sizeof(seed));

    ret = TALER_age_restriction_commit (&age_mask,
                                        age,
                                        &seed,
                                        &acp);
    stoptime;

  }
  pr ("commit", times, i);

  // attest
  for (; i < ITER; i++)
  {
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &seed,
                                sizeof(seed));

    ret = TALER_age_restriction_commit (&age_mask,
                                        age,
                                        &seed,
                                        &acp);

    starttime;
    uint8_t min_group = get_age_group (&age_mask, 13);
    struct TALER_AgeAttestation at = {0};
    ret = TALER_age_commitment_attest (&acp,
                                       13,
                                       &at);
    stoptime;
  }
  pr ("attest", times, i);

  // verify
  for (; i < ITER; i++)
  {
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &seed,
                                sizeof(seed));

    ret = TALER_age_restriction_commit (&age_mask,
                                        age,
                                        &seed,
                                        &acp);

    uint8_t min_group = get_age_group (&age_mask, 13);
    struct TALER_AgeAttestation at = {0};

    ret = TALER_age_commitment_attest (&acp,
                                       13,
                                       &at);
    starttime;
    ret = TALER_age_commitment_verify (&acp.commitment,
                                       13,
                                       &at);
    stoptime;
  }
  pr ("verify", times, i);

  // derive
  for (; i < ITER; i++)
  {
    struct TALER_AgeCommitmentProof acp2 = {0};
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &seed,
                                sizeof(seed));
    starttime;
    TALER_age_commitment_derive (&acp,
                                 &seed,
                                 &acp2);
    stoptime;
  }
  pr ("derive", times, i);

  return 0;
}


/* end of tv_age_restriction.c */
