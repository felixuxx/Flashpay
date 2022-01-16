/*
  This file is part of TALER
  (C) 2020, 2021 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file util/test_helper_rsa.c
 * @brief Tests for RSA crypto helper
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"

/**
 * Configuration has 1 minute duration and 5 minutes lookahead, but
 * we do not get 'revocations' for expired keys. So this must be
 * large enough to deal with key rotation during the runtime of
 * the benchmark.
 */
#define MAX_KEYS 1024

/**
 * How many random key revocations should we test?
 */
#define NUM_REVOKES 3

/**
 * How many iterations of the successful signing test should we run?
 */
#define NUM_SIGN_TESTS 5

/**
 * How many iterations of the successful signing test should we run
 * during the benchmark phase?
 */
#define NUM_SIGN_PERFS 100

/**
 * How many parallel clients should we use for the parallel
 * benchmark? (> 500 may cause problems with the max open FD number limit).
 */
#define NUM_CORES 8

/**
 * Number of keys currently in #keys.
 */
static unsigned int num_keys;

/**
 * Keys currently managed by the helper.
 */
struct KeyData
{
  /**
   * Validity start point.
   */
  struct GNUNET_TIME_Timestamp start_time;

  /**
   * Key expires for signing at @e start_time plus this value.
   */
  struct GNUNET_TIME_Relative validity_duration;

  /**
   * Hash of the public key.
   */
  struct TALER_RsaPubHashP h_rsa;

  /**
   * Full public key.
   */
  struct TALER_DenominationPublicKey denom_pub;

  /**
   * Is this key currently valid?
   */
  bool valid;

  /**
   * Did the test driver revoke this key?
   */
  bool revoked;
};

/**
 * Array of all the keys we got from the helper.
 */
static struct KeyData keys[MAX_KEYS];


/**
 * Release memory occupied by #keys.
 */
static void
free_keys (void)
{
  for (unsigned int i = 0; i<MAX_KEYS; i++)
    if (keys[i].valid)
    {
      TALER_denom_pub_free (&keys[i].denom_pub);
      keys[i].valid = false;
      GNUNET_assert (num_keys > 0);
      num_keys--;
    }
}


/**
 * Function called with information about available keys for signing.  Usually
 * only called once per key upon connect. Also called again in case a key is
 * being revoked, in that case with an @a end_time of zero.  Stores the keys
 * status in #keys.
 *
 * @param cls closure, NULL
 * @param section_name name of the denomination type in the configuration;
 *                 NULL if the key has been revoked or purged
 * @param start_time when does the key become available for signing;
 *                 zero if the key has been revoked or purged
 * @param validity_duration how long does the key remain available for signing;
 *                 zero if the key has been revoked or purged
 * @param h_rsa hash of the @a denom_pub that is available (or was purged)
 * @param denom_pub the public key itself, NULL if the key was revoked or purged
 * @param sm_pub public key of the security module, NULL if the key was revoked or purged
 * @param sm_sig signature from the security module, NULL if the key was revoked or purged
 *               The signature was already verified against @a sm_pub.
 */
static void
key_cb (void *cls,
        const char *section_name,
        struct GNUNET_TIME_Timestamp start_time,
        struct GNUNET_TIME_Relative validity_duration,
        const struct TALER_RsaPubHashP *h_rsa,
        const struct TALER_DenominationPublicKey *denom_pub,
        const struct TALER_SecurityModulePublicKeyP *sm_pub,
        const struct TALER_SecurityModuleSignatureP *sm_sig)
{
  (void) cls;
  (void) sm_pub;
  (void) sm_sig;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Key notification about key %s in `%s'\n",
              GNUNET_h2s (&h_rsa->hash),
              section_name);
  if (0 == validity_duration.rel_value_us)
  {
    bool found = false;

    GNUNET_break (NULL == denom_pub);
    GNUNET_break (NULL == section_name);
    for (unsigned int i = 0; i<MAX_KEYS; i++)
      if (0 == GNUNET_memcmp (h_rsa,
                              &keys[i].h_rsa))
      {
        keys[i].valid = false;
        keys[i].revoked = false;
        TALER_denom_pub_free (&keys[i].denom_pub);
        GNUNET_assert (num_keys > 0);
        num_keys--;
        found = true;
        break;
      }
    if (! found)
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Error: helper announced expiration of unknown key!\n");

    return;
  }

  GNUNET_break (NULL != denom_pub);
  for (unsigned int i = 0; i<MAX_KEYS; i++)
    if (! keys[i].valid)
    {
      keys[i].valid = true;
      keys[i].h_rsa = *h_rsa;
      keys[i].start_time = start_time;
      keys[i].validity_duration = validity_duration;
      TALER_denom_pub_deep_copy (&keys[i].denom_pub,
                                 denom_pub);
      num_keys++;
      return;
    }
  /* too many keys! */
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Error: received %d live keys from the service!\n",
              MAX_KEYS + 1);
}


/**
 * Test key revocation logic.
 *
 * @param dh handle to the helper
 * @return 0 on success
 */
static int
test_revocation (struct TALER_CRYPTO_RsaDenominationHelper *dh)
{
  struct timespec req = {
    .tv_nsec = 250000000
  };

  for (unsigned int i = 0; i<NUM_REVOKES; i++)
  {
    uint32_t off;

    off = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK,
                                    num_keys);
    /* find index of key to revoke */
    for (unsigned int j = 0; j < MAX_KEYS; j++)
    {
      if (! keys[j].valid)
        continue;
      if (0 != off)
      {
        off--;
        continue;
      }
      keys[j].revoked = true;
      fprintf (stderr,
               "Revoking key %s ...",
               GNUNET_h2s (&keys[j].h_rsa.hash));
      TALER_CRYPTO_helper_rsa_revoke (dh,
                                      &keys[j].h_rsa);
      for (unsigned int k = 0; k<1000; k++)
      {
        TALER_CRYPTO_helper_rsa_poll (dh);
        if (! keys[j].revoked)
          break;
        nanosleep (&req, NULL);
        fprintf (stderr, ".");
      }
      if (keys[j].revoked)
      {
        fprintf (stderr,
                 "\nFAILED: timeout trying to revoke key %u\n",
                 j);
        TALER_CRYPTO_helper_rsa_disconnect (dh);
        return 2;
      }
      fprintf (stderr, "\n");
      break;
    }
  }
  return 0;
}


/**
 * Test signing logic.
 *
 * @param dh handle to the helper
 * @return 0 on success
 */
static int
test_signing (struct TALER_CRYPTO_RsaDenominationHelper *dh)
{
  struct TALER_BlindedDenominationSignature ds;
  enum TALER_ErrorCode ec;
  bool success = false;
  struct TALER_PlanchetSecretsP ps;
  struct TALER_ExchangeWithdrawValues alg_values;
  struct TALER_CoinPubHash c_hash;

  alg_values.cipher = TALER_DENOMINATION_RSA;
  TALER_planchet_setup_random (&ps,
                               &alg_values);
  for (unsigned int i = 0; i<MAX_KEYS; i++)
  {
    if (! keys[i].valid)
      continue;
    if (TALER_DENOMINATION_RSA != keys[i].denom_pub.cipher)
      continue;
    {
      struct TALER_PlanchetDetail pd;
      pd.blinded_planchet.cipher = TALER_DENOMINATION_RSA;

      GNUNET_assert (GNUNET_YES ==
                     TALER_planchet_prepare (&keys[i].denom_pub,
                                             &alg_values,
                                             &ps,
                                             &c_hash,
                                             &pd));
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Requesting signature over %u bytes with key %s\n",
                  (unsigned
                   int) pd.blinded_planchet.details.rsa_blinded_planchet.
                  blinded_msg_size,
                  GNUNET_h2s (&keys[i].h_rsa.hash));
      ds = TALER_CRYPTO_helper_rsa_sign (dh,
                                         &keys[i].h_rsa,
                                         pd.blinded_planchet.details.
                                         rsa_blinded_planchet.blinded_msg,
                                         pd.blinded_planchet.details.
                                         rsa_blinded_planchet.blinded_msg_size,
                                         &ec);
      TALER_blinded_planchet_free (&pd.blinded_planchet);
    }
    switch (ec)
    {
    case TALER_EC_NONE:
      if (GNUNET_TIME_relative_cmp (GNUNET_TIME_absolute_get_remaining (
                                      keys[i].start_time.abs_time),
                                    >,
                                    GNUNET_TIME_UNIT_SECONDS))
      {
        /* key worked too early */
        GNUNET_break (0);
        return 4;
      }
      if (GNUNET_TIME_relative_cmp (GNUNET_TIME_absolute_get_duration (
                                      keys[i].start_time.abs_time),
                                    >,
                                    keys[i].validity_duration))
      {
        /* key worked too later */
        GNUNET_break (0);
        return 5;
      }
      {
        struct TALER_DenominationSignature rs;

        if (GNUNET_OK !=
            TALER_denom_sig_unblind (&rs,
                                     &ds,
                                     &ps.blinding_key,
                                     &keys[i].denom_pub))
        {
          GNUNET_break (0);
          return 6;
        }
        TALER_blinded_denom_sig_free (&ds);
        if (GNUNET_OK !=
            TALER_denom_pub_verify (&keys[i].denom_pub,
                                    &rs,
                                    &c_hash))
        {
          /* signature invalid */
          GNUNET_break (0);
          TALER_denom_sig_free (&rs);
          return 7;
        }
        TALER_denom_sig_free (&rs);
      }
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Received valid signature for key %s\n",
                  GNUNET_h2s (&keys[i].h_rsa.hash));
      success = true;
      break;
    case TALER_EC_EXCHANGE_DENOMINATION_HELPER_TOO_EARLY:
      /* This 'failure' is expected, we're testing also for the
         error handling! */
      if ( (GNUNET_TIME_relative_is_zero (
              GNUNET_TIME_absolute_get_remaining (
                keys[i].start_time.abs_time))) &&
           (GNUNET_TIME_relative_cmp (
              GNUNET_TIME_absolute_get_duration (
                keys[i].start_time.abs_time),
              <,
              keys[i].validity_duration)) )
      {
        /* key should have worked! */
        GNUNET_break (0);
        return 6;
      }
      break;
    default:
      /* unexpected error */
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unexpected error %d\n",
                  ec);
      return 7;
    }
  }
  if (! success)
  {
    /* no valid key for signing found, also bad */
    GNUNET_break (0);
    return 16;
  }

  /* check signing does not work if the key is unknown */
  {
    struct TALER_RsaPubHashP rnd;

    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &rnd,
                                sizeof (rnd));
    ds = TALER_CRYPTO_helper_rsa_sign (dh,
                                       &rnd,
                                       "Hello",
                                       strlen ("Hello"),
                                       &ec);
    if (TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN != ec)
    {
      if (TALER_EC_NONE == ec)
        TALER_blinded_denom_sig_free (&ds);
      GNUNET_break (0);
      return 17;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Signing with invalid key %s failed as desired\n",
                GNUNET_h2s (&rnd.hash));
  }
  return 0;
}


/**
 * Benchmark signing logic.
 *
 * @param dh handle to the helper
 * @return 0 on success
 */
static int
perf_signing (struct TALER_CRYPTO_RsaDenominationHelper *dh,
              const char *type)
{
  struct TALER_BlindedDenominationSignature ds;
  enum TALER_ErrorCode ec;
  struct GNUNET_TIME_Relative duration;
  struct TALER_PlanchetSecretsP ps;
  struct TALER_ExchangeWithdrawValues alg_values;

  alg_values.cipher = TALER_DENOMINATION_RSA;
  TALER_planchet_setup_random (&ps,
                               &alg_values);
  duration = GNUNET_TIME_UNIT_ZERO;
  TALER_CRYPTO_helper_rsa_poll (dh);
  for (unsigned int j = 0; j<NUM_SIGN_PERFS;)
  {
    for (unsigned int i = 0; i<MAX_KEYS; i++)
    {
      if (! keys[i].valid)
        continue;
      if (TALER_DENOMINATION_RSA != keys[i].denom_pub.cipher)
        continue;
      if (GNUNET_TIME_relative_cmp (GNUNET_TIME_absolute_get_remaining (
                                      keys[i].start_time.abs_time),
                                    >,
                                    GNUNET_TIME_UNIT_SECONDS))
        continue;
      if (GNUNET_TIME_relative_cmp (GNUNET_TIME_absolute_get_duration (
                                      keys[i].start_time.abs_time),
                                    >,
                                    keys[i].validity_duration))
        continue;
      {
        struct TALER_CoinPubHash c_hash;
        struct TALER_PlanchetDetail pd;

        GNUNET_assert (GNUNET_YES ==
                       TALER_planchet_prepare (&keys[i].denom_pub,
                                               &alg_values,
                                               &ps,
                                               &c_hash,
                                               &pd));
        /* use this key as long as it works */
        while (1)
        {
          struct GNUNET_TIME_Absolute start = GNUNET_TIME_absolute_get ();
          struct GNUNET_TIME_Relative delay;

          ds = TALER_CRYPTO_helper_rsa_sign (dh,
                                             &keys[i].h_rsa,
                                             pd.blinded_planchet.details.
                                             rsa_blinded_planchet.blinded_msg,
                                             pd.blinded_planchet.details.
                                             rsa_blinded_planchet.
                                             blinded_msg_size,
                                             &ec);
          if (TALER_EC_NONE != ec)
            break;
          delay = GNUNET_TIME_absolute_get_duration (start);
          duration = GNUNET_TIME_relative_add (duration,
                                               delay);
          TALER_blinded_denom_sig_free (&ds);
          j++;
          if (NUM_SIGN_PERFS <= j)
            break;
        }
        TALER_blinded_planchet_free (&pd.blinded_planchet);
      }
    } /* for i */
  } /* for j */
  fprintf (stderr,
           "%u (%s) signature operations took %s\n",
           (unsigned int) NUM_SIGN_PERFS,
           type,
           GNUNET_STRINGS_relative_time_to_string (duration,
                                                   GNUNET_YES));
  return 0;
}


/**
 * Parallel signing logic.
 *
 * @param esh handle to the helper
 * @return 0 on success
 */
static int
par_signing (struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct GNUNET_TIME_Absolute start;
  struct GNUNET_TIME_Relative duration;
  pid_t pids[NUM_CORES];
  struct TALER_CRYPTO_RsaDenominationHelper *dh;

  start = GNUNET_TIME_absolute_get ();
  for (unsigned int i = 0; i<NUM_CORES; i++)
  {
    pids[i] = fork ();
    num_keys = 0;
    GNUNET_assert (-1 != pids[i]);
    if (0 == pids[i])
    {
      int ret;

      dh = TALER_CRYPTO_helper_rsa_connect (cfg,
                                            &key_cb,
                                            NULL);
      GNUNET_assert (NULL != dh);
      ret = perf_signing (dh,
                          "parallel");
      TALER_CRYPTO_helper_rsa_disconnect (dh);
      free_keys ();
      exit (ret);
    }
  }
  for (unsigned int i = 0; i<NUM_CORES; i++)
  {
    int wstatus;

    GNUNET_assert (pids[i] ==
                   waitpid (pids[i],
                            &wstatus,
                            0));
  }
  duration = GNUNET_TIME_absolute_get_duration (start);
  fprintf (stderr,
           "%u (parallel) signature operations took %s (total real time)\n",
           (unsigned int) NUM_SIGN_PERFS * NUM_CORES,
           GNUNET_STRINGS_relative_time_to_string (duration,
                                                   GNUNET_YES));
  return 0;
}


/**
 * Main entry point into the test logic with the helper already running.
 */
static int
run_test (void)
{
  struct GNUNET_CONFIGURATION_Handle *cfg;
  struct TALER_CRYPTO_RsaDenominationHelper *dh;
  struct timespec req = {
    .tv_nsec = 250000000
  };
  int ret;

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (cfg,
                                 "test_helper_rsa.conf"))
  {
    GNUNET_break (0);
    return 77;
  }

  fprintf (stderr, "Waiting for helper to start ... ");
  for (unsigned int i = 0; i<100; i++)
  {
    nanosleep (&req,
               NULL);
    dh = TALER_CRYPTO_helper_rsa_connect (cfg,
                                          &key_cb,
                                          NULL);
    if (NULL != dh)
      break;
    fprintf (stderr, ".");
  }
  if (NULL == dh)
  {
    fprintf (stderr,
             "\nFAILED: timeout trying to connect to helper\n");
    GNUNET_CONFIGURATION_destroy (cfg);
    return 1;
  }
  if (0 == num_keys)
  {
    fprintf (stderr,
             "\nFAILED: timeout trying to connect to helper\n");
    TALER_CRYPTO_helper_rsa_disconnect (dh);
    GNUNET_CONFIGURATION_destroy (cfg);
    return 1;
  }
  fprintf (stderr,
           " Done (%u keys)\n",
           num_keys);
  ret = 0;
  if (0 == ret)
    ret = test_revocation (dh);
  if (0 == ret)
    ret = test_signing (dh);
  if (0 == ret)
    ret = perf_signing (dh,
                        "sequential");
  TALER_CRYPTO_helper_rsa_disconnect (dh);
  free_keys ();
  if (0 == ret)
    ret = par_signing (cfg);
  /* clean up our state */
  GNUNET_CONFIGURATION_destroy (cfg);
  return ret;
}


int
main (int argc,
      const char *const argv[])
{
  struct GNUNET_OS_Process *helper;
  char *libexec_dir;
  char *binary_name;
  int ret;
  enum GNUNET_OS_ProcessStatusType type;
  unsigned long code;

  (void) argc;
  (void) argv;
  unsetenv ("XDG_DATA_HOME");
  unsetenv ("XDG_CONFIG_HOME");
  GNUNET_log_setup ("test-helper-rsa",
                    "WARNING",
                    NULL);
  GNUNET_OS_init (TALER_project_data_default ());
  libexec_dir = GNUNET_OS_installation_get_path (GNUNET_OS_IPK_BINDIR);
  GNUNET_asprintf (&binary_name,
                   "%s/%s",
                   libexec_dir,
                   "taler-exchange-secmod-rsa");
  GNUNET_free (libexec_dir);
  helper = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ERR,
                                    NULL, NULL, NULL,
                                    binary_name,
                                    binary_name,
                                    "-c",
                                    "test_helper_rsa.conf",
                                    "-L",
                                    "WARNING",
                                    NULL);
  if (NULL == helper)
  {
    GNUNET_log_strerror_file (GNUNET_ERROR_TYPE_ERROR,
                              "exec",
                              binary_name);
    GNUNET_free (binary_name);
    return 77;
  }
  GNUNET_free (binary_name);
  ret = run_test ();

  GNUNET_OS_process_kill (helper,
                          SIGTERM);
  if (GNUNET_OK !=
      GNUNET_OS_process_wait_status (helper,
                                     &type,
                                     &code))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Helper process did not die voluntarily, killing hard\n");
    GNUNET_OS_process_kill (helper,
                            SIGKILL);
    ret = 4;
  }
  else if ( (GNUNET_OS_PROCESS_EXITED != type) ||
            (0 != code) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Helper died with unexpected status %d/%d\n",
                (int) type,
                (int) code);
    ret = 5;
  }
  GNUNET_OS_process_destroy (helper);
  return ret;
}


/* end of test_helper_rsa.c */
