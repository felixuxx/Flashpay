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
#include "taler_auditordb_lib.h"
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
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, ptr, sizeof (*ptr))

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
                "select_historic_denom_revenue_result: result does not match\n");
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


static enum GNUNET_GenericReturnValue
select_historic_reserve_revenue_result (
  void *cls,
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
      plugin->create_tables (plugin->cls))
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

  struct TALER_Amount value;
  struct TALER_Amount fee_withdraw;
  struct TALER_Amount fee_deposit;
  struct TALER_Amount fee_refresh;
  struct TALER_Amount fee_refund;

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
  struct TALER_DenominationPrivateKey denom_priv;
  struct TALER_DenominationPublicKey denom_pub;
  struct GNUNET_TIME_Timestamp date;

  RND_BLK (&master_pub);
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

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: auditor_insert_exchange\n");
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_exchange (plugin->cls,
                                   &master_pub,
                                   "https://exchange/"));


  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: insert_auditor_progress\n");

  struct TALER_AUDITORDB_ProgressPointCoin ppc = {
    .last_deposit_serial_id = 123,
    .last_melt_serial_id = 456,
    .last_refund_serial_id = 789,
    .last_withdraw_serial_id = 555
  };
  struct TALER_AUDITORDB_ProgressPointCoin ppc2 = {
    .last_deposit_serial_id = 0,
    .last_melt_serial_id = 0,
    .last_refund_serial_id = 0,
    .last_withdraw_serial_id = 0
  };

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_auditor_progress_coin (plugin->cls,
                                                &master_pub,
                                                &ppc));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: update_auditor_progress\n");

  ppc.last_deposit_serial_id++;
  ppc.last_melt_serial_id++;
  ppc.last_refund_serial_id++;
  ppc.last_withdraw_serial_id++;

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->update_auditor_progress_coin (plugin->cls,
                                                &master_pub,
                                                &ppc));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: get_auditor_progress\n");

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_auditor_progress_coin (plugin->cls,
                                             &master_pub,
                                             &ppc2));
  FAILIF ( (ppc.last_deposit_serial_id != ppc2.last_deposit_serial_id) ||
           (ppc.last_melt_serial_id != ppc2.last_melt_serial_id) ||
           (ppc.last_refund_serial_id != ppc2.last_refund_serial_id) ||
           (ppc.last_withdraw_serial_id != ppc2.last_withdraw_serial_id) );

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
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->insert_reserve_info (plugin->cls,
                                         &reserve_pub,
                                         &master_pub,
                                         &rfb,
                                         past,
                                         "payto://bla/blub"));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: update_reserve_info\n");
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->update_reserve_info (plugin->cls,
                                         &reserve_pub,
                                         &master_pub,
                                         &rfb,
                                         future));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: get_reserve_info\n");
    {
      char *payto;

      FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
              plugin->get_reserve_info (plugin->cls,
                                        &reserve_pub,
                                        &master_pub,
                                        &rowid,
                                        &rfb2,
                                        &date,
                                        &payto));
      FAILIF (0 != strcmp (payto,
                           "payto://bla/blub"));
      GNUNET_free (payto);
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

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: insert_reserve_summary\n");

    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->insert_reserve_summary (plugin->cls,
                                            &master_pub,
                                            &rfb));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: update_reserve_summary\n");
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->update_reserve_summary (plugin->cls,
                                            &master_pub,
                                            &rfb));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: get_reserve_summary\n");
    ZR_BLK (&rfb2);
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->get_reserve_summary (plugin->cls,
                                         &master_pub,
                                         &rfb2));
    FAILIF ( (0 != TALER_amount_cmp (&rfb2.reserve_balance,
                                     &rfb.reserve_balance) ||
              (0 != TALER_amount_cmp (&rfb2.withdraw_fee_balance,
                                      &rfb.withdraw_fee_balance)) ||
              (0 != TALER_amount_cmp (&rfb2.close_fee_balance,
                                      &rfb.close_fee_balance)) ||
              (0 != TALER_amount_cmp (&rfb2.purse_fee_balance,
                                      &rfb.purse_fee_balance)) ||
              (0 != TALER_amount_cmp (&rfb2.open_fee_balance,
                                      &rfb.open_fee_balance)) ||
              (0 != TALER_amount_cmp (&rfb2.history_fee_balance,
                                      &rfb.history_fee_balance))));
  }

  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: insert_denomination_balance\n");

    struct TALER_AUDITORDB_DenominationCirculationData dcd;
    struct TALER_AUDITORDB_DenominationCirculationData dcd2;

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

  {
    struct TALER_AUDITORDB_GlobalCoinBalance gcb;
    struct TALER_AUDITORDB_GlobalCoinBalance gcb2;

    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":12.345678",
                                           &gcb.total_escrowed));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":23.456789",
                                           &gcb.deposit_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":34.567890",
                                           &gcb.melt_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":45.678901",
                                           &gcb.refund_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":55.678901",
                                           &gcb.purse_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":65.678901",
                                           &gcb.open_deposit_fee_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":13.57986",
                                           &gcb.risk));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":0.1",
                                           &gcb.loss));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":1.1",
                                           &gcb.irregular_loss));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: insert_balance_summary\n");

    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->insert_balance_summary (plugin->cls,
                                            &master_pub,
                                            &gcb));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: update_balance_summary\n");
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->update_balance_summary (plugin->cls,
                                            &master_pub,
                                            &gcb));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: get_balance_summary\n");
    ZR_BLK (&gcb2);
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->get_balance_summary (plugin->cls,
                                         &master_pub,
                                         &gcb2));
    FAILIF (0 != TALER_amount_cmp (&gcb2.total_escrowed,
                                   &gcb.total_escrowed));
    FAILIF (0 != TALER_amount_cmp (&gcb2.deposit_fee_balance,
                                   &gcb.deposit_fee_balance) );
    FAILIF (0 != TALER_amount_cmp (&gcb2.melt_fee_balance,
                                   &gcb.melt_fee_balance) );
    FAILIF (0 != TALER_amount_cmp (&gcb2.refund_fee_balance,
                                   &gcb.refund_fee_balance));
    FAILIF (0 != TALER_amount_cmp (&gcb2.purse_fee_balance,
                                   &gcb.purse_fee_balance));
    FAILIF (0 != TALER_amount_cmp (&gcb2.open_deposit_fee_balance,
                                   &gcb.open_deposit_fee_balance));
    FAILIF (0 != TALER_amount_cmp (&gcb2.risk,
                                   &gcb.risk));
    FAILIF (0 != TALER_amount_cmp (&gcb2.loss,
                                   &gcb.loss));
    FAILIF (0 != TALER_amount_cmp (&gcb2.irregular_loss,
                                   &gcb.irregular_loss));
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
                                                 &master_pub,
                                                 &denom_pub_hash,
                                                 past,
                                                 &rbalance,
                                                 &rloss));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_historic_denom_revenue (plugin->cls,
                                                 &master_pub,
                                                 &rnd_hash,
                                                 now,
                                                 &rbalance,
                                                 &rloss));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: select_historic_denom_revenue\n");
  FAILIF (0 >=
          plugin->select_historic_denom_revenue (
            plugin->cls,
            &master_pub,
            &select_historic_denom_revenue_result,
            NULL));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: insert_historic_reserve_revenue\n");
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":56.789012",
                                         &reserve_profits));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_historic_reserve_revenue (plugin->cls,
                                                   &master_pub,
                                                   past,
                                                   future,
                                                   &reserve_profits));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_historic_reserve_revenue (plugin->cls,
                                                   &master_pub,
                                                   now,
                                                   future,
                                                   &reserve_profits));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: select_historic_reserve_revenue\n");
  FAILIF (0 >=
          plugin->select_historic_reserve_revenue (plugin->cls,
                                                   &master_pub,
                                                   select_historic_reserve_revenue_result,
                                                   NULL));

  {
    struct TALER_Amount dbalance;
    struct TALER_Amount dbalance2;
    struct TALER_Amount rbalance2;

    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":2.535678",
                                           &dbalance));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: insert_predicted_result\n");
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->insert_predicted_result (plugin->cls,
                                             &master_pub,
                                             &rbalance,
                                             &dbalance));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: update_predicted_result\n");
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":78.901234",
                                           &rbalance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (CURRENCY ":73.901234",
                                           &dbalance));
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->update_predicted_result (plugin->cls,
                                             &master_pub,
                                             &rbalance,
                                             &dbalance));
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->insert_wire_fee_summary (plugin->cls,
                                             &master_pub,
                                             &rbalance));
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->update_wire_fee_summary (plugin->cls,
                                             &master_pub,
                                             &reserve_profits));
    {
      struct TALER_Amount rprof;

      FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
              plugin->get_wire_fee_summary (plugin->cls,
                                            &master_pub,
                                            &rprof));
      FAILIF (0 !=
              TALER_amount_cmp (&rprof,
                                &reserve_profits));
    }
    FAILIF (0 >
            plugin->commit (plugin->cls));


    FAILIF (GNUNET_OK !=
            plugin->start (plugin->cls));

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: get_predicted_balance\n");

    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->get_predicted_balance (plugin->cls,
                                           &master_pub,
                                           &rbalance2,
                                           &dbalance2));

    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->del_reserve_info (plugin->cls,
                                      &reserve_pub,
                                      &master_pub));

    FAILIF (0 != TALER_amount_cmp (&rbalance2,
                                   &rbalance));
    FAILIF (0 != TALER_amount_cmp (&dbalance2,
                                   &dbalance));

    plugin->rollback (plugin->cls);
  }

#if GC_IMPLEMENTED
  FAILIF (GNUNET_OK !=
          plugin->gc (plugin->cls));
#endif

  result = 0;

drop:
  {
    plugin->rollback (plugin->cls);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: auditor_delete_exchange\n");
    GNUNET_break (GNUNET_OK ==
                  plugin->start (plugin->cls));
    GNUNET_break (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
                  plugin->delete_exchange (plugin->cls,
                                           &master_pub));
    GNUNET_break (0 <=
                  plugin->commit (plugin->cls));
  }
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
