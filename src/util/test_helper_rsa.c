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
 * @file util/test_helper_rsa.c
 * @brief Tests for RSA crypto helper
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"

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
 * How many iterations of the successful signing test should we run?
 */
#define NUM_SIGN_TESTS 5


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
   * Hash of the public key.
   */
  struct GNUNET_HashCode h_denom_pub;

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
 * @param h_denom_pub hash of the @a denom_pub that is available (or was purged)
 * @param denom_pub the public key itself, NULL if the key was revoked or purged
 * @param sm_pub public key of the security module, NULL if the key was revoked or purged
 * @param sm_sig signature from the security module, NULL if the key was revoked or purged
 *               The signature was already verified against @a sm_pub.
 */
static void
key_cb (void *cls,
        const char *section_name,
        struct GNUNET_TIME_Absolute start_time,
        struct GNUNET_TIME_Relative validity_duration,
        const struct GNUNET_HashCode *h_denom_pub,
        const struct TALER_DenominationPublicKey *denom_pub,
        const struct TALER_SecurityModulePublicKeyP *sm_pub,
        const struct TALER_SecurityModuleSignatureP *sm_sig)
{
  (void) sm_pub;
  (void) sm_sig;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Key notification about key %s in `%s'\n",
              GNUNET_h2s (h_denom_pub),
              section_name);
  if (0 == validity_duration.rel_value_us)
  {
    bool found = false;

    GNUNET_break (NULL == denom_pub);
    GNUNET_break (NULL == section_name);
    for (unsigned int i = 0; i<MAX_KEYS; i++)
      if (0 == GNUNET_memcmp (h_denom_pub,
                              &keys[i].h_denom_pub))
      {
        keys[i].valid = false;
        keys[i].revoked = false;
        GNUNET_CRYPTO_rsa_public_key_free (keys[i].denom_pub.rsa_public_key);
        keys[i].denom_pub.rsa_public_key = NULL;
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
      keys[i].h_denom_pub = *h_denom_pub;
      keys[i].start_time = start_time;
      keys[i].validity_duration = validity_duration;
      keys[i].denom_pub.rsa_public_key
        = GNUNET_CRYPTO_rsa_public_key_dup (denom_pub->rsa_public_key);
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
test_revocation (struct TALER_CRYPTO_DenominationHelper *dh)
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
               GNUNET_h2s (&keys[j].h_denom_pub));
      TALER_CRYPTO_helper_denom_revoke (dh,
                                        &keys[j].h_denom_pub);
      for (unsigned int k = 0; k<1000; k++)
      {
        TALER_CRYPTO_helper_denom_poll (dh);
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
        TALER_CRYPTO_helper_denom_disconnect (dh);
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
test_signing (struct TALER_CRYPTO_DenominationHelper *dh)
{
  struct TALER_DenominationSignature ds;
  enum TALER_ErrorCode ec;
  bool success = false;
  struct GNUNET_HashCode m_hash;
  struct GNUNET_CRYPTO_RsaBlindingKeySecret bks;

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &bks,
                              sizeof (bks));
  GNUNET_CRYPTO_hash ("Hello",
                      strlen ("Hello"),
                      &m_hash);
  for (unsigned int i = 0; i<MAX_KEYS; i++)
  {
    if (! keys[i].valid)
      continue;
    {
      void *buf;
      size_t buf_size;
      GNUNET_assert (GNUNET_YES ==
                     TALER_rsa_blind (&m_hash,
                                      &bks,
                                      keys[i].denom_pub.rsa_public_key,
                                      &buf,
                                      &buf_size));
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Requesting signature over %u bytes with key %s\n",
                  (unsigned int) buf_size,
                  GNUNET_h2s (&keys[i].h_denom_pub));
      ds = TALER_CRYPTO_helper_denom_sign (dh,
                                           &keys[i].h_denom_pub,
                                           buf,
                                           buf_size,
                                           &ec);
      GNUNET_free (buf);
    }
    switch (ec)
    {
    case TALER_EC_NONE:
      if (GNUNET_TIME_absolute_get_remaining (keys[i].start_time).rel_value_us >
          GNUNET_TIME_UNIT_SECONDS.rel_value_us)
      {
        /* key worked too early */
        GNUNET_break (0);
        return 4;
      }
      if (GNUNET_TIME_absolute_get_duration (keys[i].start_time).rel_value_us >
          keys[i].validity_duration.rel_value_us)
      {
        /* key worked too later */
        GNUNET_break (0);
        return 5;
      }
      {
        struct GNUNET_CRYPTO_RsaSignature *rs;

        rs = TALER_rsa_unblind (ds.rsa_signature,
                                &bks,
                                keys[i].denom_pub.rsa_public_key);
        if (NULL == rs)
        {
          GNUNET_break (0);
          return 6;
        }
        GNUNET_CRYPTO_rsa_signature_free (ds.rsa_signature);
        if (GNUNET_OK !=
            GNUNET_CRYPTO_rsa_verify (&m_hash,
                                      rs,
                                      keys[i].denom_pub.rsa_public_key))
        {
          /* signature invalid */
          GNUNET_break (0);
          GNUNET_CRYPTO_rsa_signature_free (rs);
          return 7;
        }
        GNUNET_CRYPTO_rsa_signature_free (rs);
      }
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Received valid signature for key %s\n",
                  GNUNET_h2s (&keys[i].h_denom_pub));
      success = true;
      break;
    case TALER_EC_EXCHANGE_DENOMINATION_HELPER_TOO_EARLY:
      /* This 'failure' is expected, we're testing also for the
         error handling! */
      if ( (0 ==
            GNUNET_TIME_absolute_get_remaining (
              keys[i].start_time).rel_value_us) &&
           (GNUNET_TIME_absolute_get_duration (
              keys[i].start_time).rel_value_us <
            keys[i].validity_duration.rel_value_us) )
      {
        /* key should have worked! */
        GNUNET_break (0);
        return 6;
      }
      break;
    default:
      /* unexpected error */
      GNUNET_break (0);
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
    struct GNUNET_HashCode rnd;

    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &rnd,
                                sizeof (rnd));
    (void) TALER_CRYPTO_helper_denom_sign (dh,
                                           &rnd,
                                           "Hello",
                                           strlen ("Hello"),
                                           &ec);
    if (TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN != ec)
    {
      GNUNET_break (0);
      return 17;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Signing with invalid key %s failed as desired\n",
                GNUNET_h2s (&rnd));
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
perf_signing (struct TALER_CRYPTO_DenominationHelper *dh)
{
  struct TALER_DenominationSignature ds;
  enum TALER_ErrorCode ec;
  struct GNUNET_HashCode m_hash;
  struct GNUNET_CRYPTO_RsaBlindingKeySecret bks;
  struct GNUNET_TIME_Relative duration;

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &bks,
                              sizeof (bks));
  GNUNET_CRYPTO_hash ("Hello",
                      strlen ("Hello"),
                      &m_hash);
  duration = GNUNET_TIME_UNIT_ZERO;
  for (unsigned int j = 0; j<NUM_SIGN_TESTS;)
  {
    TALER_CRYPTO_helper_denom_poll (dh);
    for (unsigned int i = 0; i<MAX_KEYS; i++)
    {
      if (! keys[i].valid)
        continue;
      if (GNUNET_TIME_absolute_get_remaining (keys[i].start_time).rel_value_us >
          GNUNET_TIME_UNIT_SECONDS.rel_value_us)
        continue;
      if (GNUNET_TIME_absolute_get_duration (keys[i].start_time).rel_value_us >
          keys[i].validity_duration.rel_value_us)
        continue;
      {
        void *buf;
        size_t buf_size;

        GNUNET_assert (GNUNET_YES ==
                       TALER_rsa_blind (&m_hash,
                                        &bks,
                                        keys[i].denom_pub.rsa_public_key,
                                        &buf,
                                        &buf_size));
        /* use this key as long as it works */
        while (1)
        {
          struct GNUNET_TIME_Absolute start = GNUNET_TIME_absolute_get ();
          struct GNUNET_TIME_Relative delay;

          ds = TALER_CRYPTO_helper_denom_sign (dh,
                                               &keys[i].h_denom_pub,
                                               buf,
                                               buf_size,
                                               &ec);
          if (TALER_EC_NONE != ec)
            break;
          delay = GNUNET_TIME_absolute_get_duration (start);
          duration = GNUNET_TIME_relative_add (duration,
                                               delay);
          GNUNET_CRYPTO_rsa_signature_free (ds.rsa_signature);
          j++;
          if (NUM_SIGN_TESTS == j)
            break;
        }
        GNUNET_free (buf);
      }
    } /* for i */
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
  struct TALER_CRYPTO_DenominationHelper *dh;
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
  dh = TALER_CRYPTO_helper_denom_connect (cfg,
                                          &key_cb,
                                          NULL);
  GNUNET_CONFIGURATION_destroy (cfg);
  if (NULL == dh)
  {
    GNUNET_break (0);
    return 1;
  }
  /* wait for helper to start and give us keys */
  fprintf (stderr, "Waiting for helper to start ");
  for (unsigned int i = 0; i<1000; i++)
  {
    TALER_CRYPTO_helper_denom_poll (dh);
    if (0 != num_keys)
      break;
    nanosleep (&req, NULL);
    fprintf (stderr, ".");
  }
  if (0 == num_keys)
  {
    fprintf (stderr,
             "\nFAILED: timeout trying to connect to helper\n");
    TALER_CRYPTO_helper_denom_disconnect (dh);
    return 1;
  }
  fprintf (stderr,
           "\nOK: Helper ready (%u keys)\n",
           num_keys);

  ret = 0;
  if (0 == ret)
    ret = test_revocation (dh);
  if (0 == ret)
    ret = test_signing (dh);
  if (0 == ret)
    ret = perf_signing (dh);
  TALER_CRYPTO_helper_denom_disconnect (dh);
  /* clean up our state */
  for (unsigned int i = 0; i<MAX_KEYS; i++)
    if (keys[i].valid)
    {
      GNUNET_CRYPTO_rsa_public_key_free (keys[i].denom_pub.rsa_public_key);
      keys[i].denom_pub.rsa_public_key = NULL;
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
  GNUNET_log_setup ("test-helper-rsa",
                    "WARNING",
                    NULL);
  GNUNET_OS_init (TALER_project_data_default ());
  libexec_dir = GNUNET_OS_installation_get_path (GNUNET_OS_IPK_LIBEXECDIR);
  GNUNET_asprintf (&binary_name,
                   "%s/%s",
                   libexec_dir,
                   "taler-helper-crypto-rsa");
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
