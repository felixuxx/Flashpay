/*
  This file is part of TALER
  Copyright (C) 2016--2022 Taler Systems SA

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
 * @author Gabor X Toth
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_db_lib.h>
#include "taler_auditordb_plugin.h"

/**
 * Currency we use, must match CURRENCY in "test-auditor-db-postgres.conf".
 */
#define CURRENCY "EUR"

/**
 * Report line of error if @a cond is true, and jump to label "drop".
 */
#define FAILIF(cond)                              \
        do {                                          \
          if (! (cond)) { break;}                     \
          GNUNET_break (0);                         \
          goto drop;                                \
        } while (0)

/**
 * Initializes @a ptr with random data.
 */
#define RND_BLK(ptr)                                                    \
        GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, ptr, sizeof (* \
                                                                             ptr))

/**
 * Initializes @a ptr with zeros.
 */
#define ZR_BLK(ptr) \
        memset (ptr, 0, sizeof (*ptr))


/**
 * Global result from the testcase.
 */
static int result = -1;

/**
 * Hash of denomination public key.
 */
static struct TALER_DenominationHashP denom_pub_hash;

/**
 * Another hash of a denomination public key.
 */
static struct TALER_DenominationHashP rnd_hash;

/**
 * Current time.
 */
static struct GNUNET_TIME_Timestamp now;

/**
 * Timestamp in the past.
 */
static struct GNUNET_TIME_Timestamp past;

/**
 * Timestamp in the future.
 */
static struct GNUNET_TIME_Timestamp future;

/**
 * Database plugin under test.
 */
static struct TALER_AUDITORDB_Plugin *plugin;

/**
 * Historic denomination revenue value.
 */
static struct TALER_Amount rbalance;

/**
 * Historic denomination loss value.
 */
static struct TALER_Amount rloss;

/**
 * Reserve profit value we are using.
 */
static struct TALER_Amount reserve_profits;


static enum GNUNET_GenericReturnValue
select_historic_denom_revenue_result (
  void *cls,
  uint64_t rowid,
  const struct TALER_DenominationHashP *denom_pub_hash2,
  struct GNUNET_TIME_Timestamp revenue_timestamp2,
  const struct TALER_Amount *revenue_balance2,
  const struct TALER_Amount *loss2)
{
  static int n = 0;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "select_historic_denom_revenue_result: row %u\n", n);

  if ( (2 <= n++)
       || (cls != NULL)
       || ((0 != GNUNET_memcmp (&revenue_timestamp2,
                                &past))
           && (0 != GNUNET_memcmp (&revenue_timestamp2,
                                   &now)))
       || ((0 != GNUNET_memcmp (denom_pub_hash2,
                                &denom_pub_hash))
           && (0 != GNUNET_memcmp (denom_pub_hash2,
                                   &rnd_hash)))
       || (0 != TALER_amount_cmp (revenue_balance2,
                                  &rbalance))
       || (0 != TALER_amount_cmp (loss2,
                                  &rloss)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "select_historic_denom_revenue_result: result does not match\n")
    ;
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


static enum GNUNET_GenericReturnValue
select_historic_reserve_revenue_result (
  void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Timestamp start_time2,
  struct GNUNET_TIME_Timestamp end_time2,
  const struct TALER_Amount *reserve_profits2)
{
  static int n = 0;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "select_historic_reserve_revenue_result: row %u\n", n);

  if ((2 <= n++)
      || (cls != NULL)
      || ((0 != GNUNET_memcmp (&start_time2,
                               &past))
          && (0 != GNUNET_memcmp (&start_time2,
                                  &now)))
      || (0 != GNUNET_memcmp (&end_time2,
                              &future))
      || (0 != TALER_amount_cmp (reserve_profits2,
                                 &reserve_profits)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "select_historic_reserve_revenue_result: result does not match\n");
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
  uint64_t rowid;
  struct TALER_Amount value;
  struct TALER_Amount fee_withdraw;
  struct TALER_Amount fee_deposit;
  struct TALER_Amount fee_refresh;
  struct TALER_Amount fee_refund;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct TALER_DenominationPrivateKey denom_priv;
  struct TALER_DenominationPublicKey denom_pub;
  struct GNUNET_TIME_Timestamp date;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "loading database plugin\n");

  if (NULL ==
      (plugin = TALER_AUDITORDB_plugin_load (cfg)))
  {
    result = 77;
    return;
  }

  (void) plugin->drop_tables (plugin->cls,
                              GNUNET_YES);
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls,
                             false,
                             0))
  {
    result = 77;
    goto unload;
  }
  if (GNUNET_SYSERR ==
      plugin->preflight (plugin->cls))
  {
    result = 77;
    goto drop;
  }

  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "initializing\n");

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
  RND_BLK (&reserve_pub);
  RND_BLK (&rnd_hash);
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_priv_create (&denom_priv,
                                          &denom_pub,
                                          GNUNET_CRYPTO_BSA_RSA,
                                          1024));
  TALER_denom_pub_hash (&denom_pub,
                        &denom_pub_hash);
  TALER_denom_priv_free (&denom_priv);
  TALER_denom_pub_free (&denom_pub);

  now = GNUNET_TIME_timestamp_get ();
  past = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_subtract (now.abs_time,
                                   GNUNET_TIME_relative_multiply (
                                     GNUNET_TIME_UNIT_HOURS,
                                     4)));
  future = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_add (now.abs_time,
                              GNUNET_TIME_relative_multiply (
                                GNUNET_TIME_UNIT_HOURS,
                                4)));

  {
    struct TALER_AUDITORDB_ReserveFeeBalance rfb;
    struct TALER_AUDITORDB_ReserveFeeBalance rfb2;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: insert_reserve_info\n");
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":12.345678",
                                           &rfb.reserve_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":11.245678",
                                           &rfb.reserve_loss));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":23.456789",
                                           &rfb.withdraw_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":23.456719",
                                           &rfb.close_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":33.456789",
                                           &rfb.purse_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":43.456789",
                                           &rfb.open_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":53.456789",
                                           &rfb.history_fee_balance));
    {
      struct TALER_FullPayto pt = {
        .full_payto = (char *) "payto://bla/blub?receiver-name=blub"
      };

      FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
              plugin->insert_reserve_info (plugin->cls,
                                           &reserve_pub,
                                           &rfb,
                                           past,
                                           pt));
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: update_reserve_info\n");
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->update_reserve_info (plugin->cls,
                                         &reserve_pub,
                                         &rfb,
                                         future));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: get_reserve_info\n");
    {
      struct TALER_FullPayto payto;

      FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
              plugin->get_reserve_info (plugin->cls,
                                        &reserve_pub,
                                        &rowid,
                                        &rfb2,
                                        &date,
                                        &payto));
      FAILIF (0 != strcmp (payto.full_payto,
                           "payto://bla/blub?receiver-name=blub"));
      GNUNET_free (payto.full_payto);
    }
    FAILIF ( (0 != GNUNET_memcmp (&date,
                                  &future))
             || (0 != TALER_amount_cmp (&rfb2.reserve_balance,
                                        &rfb.reserve_balance))
             || (0 != TALER_amount_cmp (&rfb2.withdraw_fee_balance,
                                        &rfb.withdraw_fee_balance))
             || (0 != TALER_amount_cmp (&rfb2.close_fee_balance,
                                        &rfb.close_fee_balance))
             || (0 != TALER_amount_cmp (&rfb2.purse_fee_balance,
                                        &rfb.purse_fee_balance))
             || (0 != TALER_amount_cmp (&rfb2.open_fee_balance,
                                        &rfb.open_fee_balance))
             || (0 != TALER_amount_cmp (&rfb2.history_fee_balance,
                                        &rfb.history_fee_balance))
             );
  }

  {
    struct TALER_AUDITORDB_DenominationCirculationData dcd;
    struct TALER_AUDITORDB_DenominationCirculationData dcd2;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: insert_denomination_balance\n");
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":12.345678",
                                           &dcd.denom_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":0.1",
                                           &dcd.denom_loss));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":13.57986",
                                           &dcd.denom_risk));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":12.57986",
                                           &dcd.recoup_loss));
    dcd.num_issued = 62;
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->insert_denomination_balance (plugin->cls,
                                                 &denom_pub_hash,
                                                 &dcd));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: update_denomination_balance\n");
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->update_denomination_balance (plugin->cls,
                                                 &denom_pub_hash,
                                                 &dcd));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: get_denomination_balance\n");

    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->get_denomination_balance (plugin->cls,
                                              &denom_pub_hash,
                                              &dcd2));
    FAILIF (0 != TALER_amount_cmp (&dcd2.denom_balance,
                                   &dcd.denom_balance));
    FAILIF (0 != TALER_amount_cmp (&dcd2.denom_loss,
                                   &dcd.denom_loss));
    FAILIF (0 != TALER_amount_cmp (&dcd2.denom_risk,
                                   &dcd.denom_risk));
    FAILIF (0 != TALER_amount_cmp (&dcd2.recoup_loss,
                                   &dcd.recoup_loss));
    FAILIF (dcd2.num_issued != dcd.num_issued);
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: insert_historic_denom_revenue\n");
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":12.345678",
                                         &rbalance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":23.456789",
                                         &rloss));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_historic_denom_revenue (plugin->cls,
                                                 &denom_pub_hash,
                                                 past,
                                                 &rbalance,
                                                 &rloss));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_historic_denom_revenue (plugin->cls,
                                                 &rnd_hash,
                                                 now,
                                                 &rbalance,
                                                 &rloss));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: select_historic_denom_revenue\n");
  FAILIF (0 >=
          plugin->select_historic_denom_revenue (
            plugin->cls,
            0,
            1024,
            &select_historic_denom_revenue_result,
            NULL));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: insert_historic_reserve_revenue\n");
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":56.789012",
                                         &reserve_profits));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_historic_reserve_revenue (plugin->cls,
                                                   past,
                                                   future,
                                                   &reserve_profits));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_historic_reserve_revenue (plugin->cls,
                                                   now,
                                                   future,
                                                   &reserve_profits));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: select_historic_reserve_revenue\n");
  FAILIF (0 >=
          plugin->select_historic_reserve_revenue (
            plugin->cls,
            0,
            1024,
            &select_historic_reserve_revenue_result,
            NULL));

  FAILIF (0 >
          plugin->commit (plugin->cls));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->del_reserve_info (plugin->cls,
                                    &reserve_pub));

#if GC_IMPLEMENTED
  FAILIF (GNUNET_OK !=
          plugin->gc (plugin->cls));
#endif

  result = 0;

drop:
  plugin->rollback (plugin->cls);
  GNUNET_break (GNUNET_OK ==
                plugin->drop_tables (plugin->cls,
                                     GNUNET_YES));
unload:
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

  (void) argc;
  result = -1;
  GNUNET_log_setup (argv[0],
                    "WARNING",
                    NULL);
  TALER_OS_init ();
  if (NULL == (plugin_name = strrchr (argv[0],
                                      (int) '-')))
  {
    GNUNET_break (0);
    return -1;
  }
  plugin_name++;
  (void) GNUNET_asprintf (&testname,
                          "test-auditor-db-%s",
                          plugin_name);
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
  GNUNET_SCHEDULER_run (&run,
                        cfg);
  GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free (config_filename);
  GNUNET_free (testname);
  return result;
}
