/*
  This file is part of TALER
  (C) 2020 Taler Systems SA

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
 * @file util/test_helper_eddsa.c
 * @brief Tests for EDDSA crypto helper
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include <gnunet/gnunet_signatures.h>

/**
 * Configuration has 1 minute duration and 5 minutes lookahead, so
 * we should never have more than 6 active keys, plus for during
 * key expiration / revocation.
 */
#define MAX_KEYS 7

/**
 * How many random key revocations should we test?
 */
#define NUM_REVOKES 3

/**
 * How many iterations of the successful signing test should we run
 * during the benchmark phase?
 */
#define NUM_SIGN_TESTS 3

/**
 * How many iterations of the successful signing test should we run
 * during the benchmark phase?
 */
#define NUM_SIGN_PERFS 100


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
  struct GNUNET_TIME_Absolute start_time;

  /**
   * Key expires for signing at @e start_time plus this value.
   */
  struct GNUNET_TIME_Relative validity_duration;

  /**
   * Full public key.
   */
  struct TALER_ExchangePublicKeyP exchange_pub;

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
 * Function called with information about available keys for signing.  Usually
 * only called once per key upon connect. Also called again in case a key is
 * being revoked, in that case with an @a end_time of zero.  Stores the keys
 * status in #keys.
 *
 * @param cls closure, NULL
 * @param start_time when does the key become available for signing;
 *                 zero if the key has been revoked or purged
 * @param validity_duration how long does the key remain available for signing;
 *                 zero if the key has been revoked or purged
 * @param exchange_pub the public key itself
 * @param sm_pub public key of the security module, NULL if the key was revoked or purged
 * @param sm_sig signature from the security module, NULL if the key was revoked or purged
 *               The signature was already verified against @a sm_pub.
 */
static void
key_cb (void *cls,
        struct GNUNET_TIME_Absolute start_time,
        struct GNUNET_TIME_Relative validity_duration,
        const struct TALER_ExchangePublicKeyP *exchange_pub,
        const struct TALER_SecurityModulePublicKeyP *sm_pub,
        const struct TALER_SecurityModuleSignatureP *sm_sig)
{
  (void) sm_pub;
  (void) sm_sig;
  if (0 == validity_duration.rel_value_us)
  {
    bool found = false;

    for (unsigned int i = 0; i<MAX_KEYS; i++)
      if (0 == GNUNET_memcmp (exchange_pub,
                              &keys[i].exchange_pub))
      {
        keys[i].valid = false;
        keys[i].revoked = false;
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
  for (unsigned int i = 0; i<MAX_KEYS; i++)
    if (! keys[i].valid)
    {
      keys[i].valid = true;
      keys[i].exchange_pub = *exchange_pub;
      keys[i].start_time = start_time;
      keys[i].validity_duration = validity_duration;
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
 * @param esh handle to the helper
 * @return 0 on success
 */
static int
test_revocation (struct TALER_CRYPTO_ExchangeSignHelper *esh)
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
               "Revoking key ...");
      TALER_CRYPTO_helper_esign_revoke (esh,
                                        &keys[j].exchange_pub);
      for (unsigned int k = 0; k<1000; k++)
      {
        TALER_CRYPTO_helper_esign_poll (esh);
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
        TALER_CRYPTO_helper_esign_disconnect (esh);
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
 * @param esh handle to the helper
 * @return 0 on success
 */
static int
test_signing (struct TALER_CRYPTO_ExchangeSignHelper *esh)
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose = {
    .purpose = htonl (GNUNET_SIGNATURE_PURPOSE_TEST),
    .size = htonl (sizeof (purpose)),
  };

  for (unsigned int i = 0; i<NUM_SIGN_TESTS; i++)
  {
    struct TALER_ExchangePublicKeyP exchange_pub;
    struct TALER_ExchangeSignatureP exchange_sig;
    enum TALER_ErrorCode ec;

    ec = TALER_CRYPTO_helper_esign_sign_ (esh,
                                          &purpose,
                                          &exchange_pub,
                                          &exchange_sig);
    switch (ec)
    {
    case TALER_EC_NONE:
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify_ (GNUNET_SIGNATURE_PURPOSE_TEST,
                                       &purpose,
                                       &exchange_sig.eddsa_signature,
                                       &exchange_pub.eddsa_pub))
      {
        /* signature invalid */
        GNUNET_break (0);
        return 17;
      }
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Received valid signature\n");
      break;
    default:
      /* unexpected error */
      GNUNET_break (0);
      return 7;
    }
  }
  return 0;
}


/**
 * Benchmark signing logic.
 *
 * @param esh handle to the helper
 * @return 0 on success
 */
static int
perf_signing (struct TALER_CRYPTO_ExchangeSignHelper *esh)
{
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose = {
    .purpose = htonl (GNUNET_SIGNATURE_PURPOSE_TEST),
    .size = htonl (sizeof (purpose)),
  };
  struct GNUNET_TIME_Relative duration;

  duration = GNUNET_TIME_UNIT_ZERO;
  for (unsigned int j = 0; j<NUM_SIGN_PERFS; j++)
  {
    struct GNUNET_TIME_Relative delay;
    struct TALER_ExchangePublicKeyP exchange_pub;
    struct TALER_ExchangeSignatureP exchange_sig;
    enum TALER_ErrorCode ec;
    struct GNUNET_TIME_Absolute start;

    TALER_CRYPTO_helper_esign_poll (esh);
    start = GNUNET_TIME_absolute_get ();
    ec = TALER_CRYPTO_helper_esign_sign_ (esh,
                                          &purpose,
                                          &exchange_pub,
                                          &exchange_sig);
    if (TALER_EC_NONE != ec)
    {
      GNUNET_break (0);
      return 42;
    }
    delay = GNUNET_TIME_absolute_get_duration (start);
    duration = GNUNET_TIME_relative_add (duration,
                                         delay);
  } /* for j */
  fprintf (stderr,
           "%u (sequential) signature operations took %s\n",
           (unsigned int) NUM_SIGN_TESTS,
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
  struct TALER_CRYPTO_ExchangeSignHelper *esh;
  struct timespec req = {
    .tv_nsec = 250000000
  };
  int ret;

  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_load (cfg,
                                 "test_helper_eddsa.conf"))
  {
    GNUNET_break (0);
    return 77;
  }
  esh = TALER_CRYPTO_helper_esign_connect (cfg,
                                           &key_cb,
                                           NULL);
  GNUNET_CONFIGURATION_destroy (cfg);
  if (NULL == esh)
  {
    GNUNET_break (0);
    return 1;
  }
  /* wait for helper to start and give us keys */
  fprintf (stderr, "Waiting for helper to start ");
  for (unsigned int i = 0; i<1000; i++)
  {
    TALER_CRYPTO_helper_esign_poll (esh);
    if (0 != num_keys)
      break;
    nanosleep (&req, NULL);
    fprintf (stderr, ".");
  }
  if (0 == num_keys)
  {
    fprintf (stderr,
             "\nFAILED: timeout trying to connect to helper\n");
    TALER_CRYPTO_helper_esign_disconnect (esh);
    return 1;
  }
  fprintf (stderr,
           "\nOK: Helper ready (%u keys)\n",
           num_keys);

  ret = 0;
  if (0 == ret)
    ret = test_revocation (esh);
  if (0 == ret)
    ret = test_signing (esh);
  if (0 == ret)
    ret = perf_signing (esh);
  TALER_CRYPTO_helper_esign_disconnect (esh);
  /* clean up our state */
  for (unsigned int i = 0; i<MAX_KEYS; i++)
    if (keys[i].valid)
    {
      keys[i].valid = false;
      GNUNET_assert (num_keys > 0);
      num_keys--;
    }
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
  GNUNET_log_setup ("test-helper-eddsa",
                    "WARNING",
                    NULL);
  GNUNET_OS_init (TALER_project_data_default ());
  libexec_dir = GNUNET_OS_installation_get_path (GNUNET_OS_IPK_BINDIR);
  GNUNET_asprintf (&binary_name,
                   "%s/%s",
                   libexec_dir,
                   "taler-exchange-secmod-eddsa");
  GNUNET_free (libexec_dir);
  helper = GNUNET_OS_start_process (GNUNET_OS_INHERIT_STD_ERR,
                                    NULL, NULL, NULL,
                                    binary_name,
                                    binary_name,
                                    "-c",
                                    "test_helper_eddsa.conf",
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


/* end of test_helper_eddsa.c */
