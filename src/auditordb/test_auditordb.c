/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 GNUnet e.V.

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
 * @file auditordb/test_auditordb.c
 * @brief test cases for DB interaction functions
 * @author Sree Harsha Totakura
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_auditordb_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Global result from the testcase.
 */
static int result = -1;

/**
 * Report line of error if @a cond is true, and jump to label "drop".
 */
#define FAILIF(cond)                              \
  do {                                          \
    if (!(cond)){ break;}                      \
    GNUNET_break (0);                           \
    /*goto drop;*/                              \
  } while (0)


/**
 * Initializes @a ptr with random data.
 */
#define RND_BLK(ptr)                                                    \
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, ptr, sizeof (*ptr))

/**
 * Initializes @a ptr with zeros.
 */
#define ZR_BLK(ptr) \
  memset (ptr, 0, sizeof (*ptr))


/**
 * Currency we use.
 */
#define CURRENCY "EUR"

/**
 * Database plugin under test.
 */
static struct TALER_AUDITORDB_Plugin *plugin;


/**
 * Callback that should never be called.
 */
static void
dead_prepare_cb (void *cls,
                 unsigned long long rowid,
                 const char *wire_method,
                 const char *buf,
                 size_t buf_size)
{
  GNUNET_assert (0);
}


int
select_denomination_info_result (void *cls,
                                 const struct TALER_DenominationKeyValidityPS *issue2)
{
  const struct TALER_DenominationKeyValidityPS *issue1 = cls;

  if (0 != memcmp (issue1, issue2, sizeof (*issue2)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "select_denomination_info_result: issue does not match\n");
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure with config
 */
static void
run (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  struct TALER_AUDITORDB_Session *session;

  if (NULL ==
      (plugin = TALER_AUDITORDB_plugin_load (cfg)))
  {
    result = 77;
    return;
  }

  (void) plugin->drop_tables (plugin->cls);
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls))
  {
    result = 77;
    goto drop;
  }
  if (NULL ==
      (session = plugin->get_session (plugin->cls)))
  {
    result = 77;
    goto drop;
  }

  struct TALER_Amount value, fee_withdraw, fee_deposit, fee_refresh, fee_refund;

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.000010",
                                         &value));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000011",
                                         &fee_withdraw));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000012",
                                         &fee_deposit));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000013",
                                         &fee_refresh));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000014",
                                         &fee_refund));

  struct TALER_MasterPublicKeyP master_pub;
  struct TALER_ReservePublicKeyP reserve_pub;
  RND_BLK (&master_pub);
  RND_BLK (&reserve_pub);

  struct TALER_DenominationPrivateKey denom_priv;
  struct TALER_DenominationPublicKey denom_pub;
  struct GNUNET_HashCode denom_pub_hash;
  denom_priv.rsa_private_key = GNUNET_CRYPTO_rsa_private_key_create (1024);
  denom_pub.rsa_public_key = GNUNET_CRYPTO_rsa_private_key_get_public (denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_hash (denom_pub.rsa_public_key, &denom_pub_hash);

  struct GNUNET_TIME_Absolute now, past, future;
  now = GNUNET_TIME_absolute_get ();
  past = GNUNET_TIME_absolute_subtract (now,
                                        GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_HOURS,
                                                                       4));
  future = GNUNET_TIME_absolute_add (now,
                                     GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_HOURS,
                                                                  4));

  struct TALER_DenominationKeyValidityPS issue = { 0 };
  issue.master = master_pub;
  issue.denom_hash = denom_pub_hash;

  issue.start = GNUNET_TIME_absolute_hton (now);
  issue.expire_withdraw = GNUNET_TIME_absolute_hton
    (GNUNET_TIME_absolute_add (now,
                               GNUNET_TIME_UNIT_HOURS));
  issue.expire_deposit = GNUNET_TIME_absolute_hton
      (GNUNET_TIME_absolute_add
       (now,
        GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_HOURS, 2)));
  issue.expire_legal = GNUNET_TIME_absolute_hton
      (GNUNET_TIME_absolute_add
       (now,
        GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_HOURS, 3)));
  TALER_amount_hton (&issue.value, &value);
  TALER_amount_hton (&issue.fee_withdraw, &fee_withdraw);
  TALER_amount_hton (&issue.fee_deposit, &fee_deposit);
  TALER_amount_hton (&issue.fee_refresh, &fee_refresh);
  TALER_amount_hton (&issue.fee_refund, &fee_refund);

  FAILIF (GNUNET_OK !=
          plugin->insert_denomination_info (plugin->cls,
                                            session,
                                            &issue));

  FAILIF (GNUNET_OK !=
          plugin->select_denomination_info (plugin->cls,
                                            session,
                                            &master_pub,
                                            select_denomination_info_result,
                                            &issue));

  result = 0;

drop:

  GNUNET_break (GNUNET_OK ==
                plugin->drop_tables (plugin->cls));
  TALER_AUDITORDB_plugin_unload (plugin);
  plugin = NULL;
}


int
main (int argc,
      char *const argv[])
{
  const char *plugin_name;
  char *config_filename;
  char *testname;
  struct GNUNET_CONFIGURATION_Handle *cfg;

  result = -1;
  if (NULL == (plugin_name = strrchr (argv[0], (int) '-')))
  {
    GNUNET_break (0);
    return -1;
  }
  GNUNET_log_setup (argv[0],
                    "WARNING",
                    NULL);
  plugin_name++;
  (void) GNUNET_asprintf (&testname,
                          "test-auditor-db-%s", plugin_name);
  (void) GNUNET_asprintf (&config_filename,
                          "%s.conf", testname);
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_parse (cfg,
                                  config_filename))
  {
    GNUNET_break (0);
    GNUNET_free (config_filename);
    GNUNET_free (testname);
    return 2;
  }
  GNUNET_SCHEDULER_run (&run, cfg);
  GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free (config_filename);
  GNUNET_free (testname);
  return result;
}
