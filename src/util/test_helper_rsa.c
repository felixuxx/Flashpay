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
#define NUM_REVOKES 10


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

static struct KeyData keys[MAX_KEYS];


static void
key_cb (void *cls,
        const char *section_name,
        struct GNUNET_TIME_Absolute start_time,
        struct GNUNET_TIME_Relative validity_duration,
        const struct GNUNET_HashCode *h_denom_pub,
        const struct TALER_DenominationPublicKey *denom_pub)
{
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
  for (unsigned int i = 0; i<80; i++)
  {
    TALER_CRYPTO_helper_poll (dh);
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
      for (unsigned int k = 0; k<80; k++)
      {
        TALER_CRYPTO_helper_poll (dh);
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
      break;
    }
  }


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
  return 0;
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
                    "INFO",
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
                                    "INFO",
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
