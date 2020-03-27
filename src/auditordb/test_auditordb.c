/*
  This file is part of TALER
  Copyright (C) 2016 Taler Systems SA

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
 */
#include "platform.h"
#include <gnunet/gnunet_db_lib.h>
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
 * Currency we use, must match CURRENCY in "test-auditor-db-postgres.conf".
 */
#define CURRENCY "EUR"

/**
 * Database plugin under test.
 */
static struct TALER_AUDITORDB_Plugin *plugin;


static int
select_denomination_info_result (void *cls,
                                 const struct
                                 TALER_DenominationKeyValidityPS *issue2)
{
  const struct TALER_DenominationKeyValidityPS *issue1 = cls;

  if (0 != GNUNET_memcmp (issue1,
                          issue2))
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
  if (NULL ==
      (session = plugin->get_session (plugin->cls)))
  {
    result = 77;
    goto drop;
  }

  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         session));

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
  struct GNUNET_HashCode rnd_hash;
  RND_BLK (&master_pub);
  RND_BLK (&reserve_pub);
  RND_BLK (&rnd_hash);

  struct TALER_DenominationPrivateKey denom_priv;
  struct TALER_DenominationPublicKey denom_pub;
  struct GNUNET_HashCode denom_pub_hash;

  denom_priv.rsa_private_key = GNUNET_CRYPTO_rsa_private_key_create (1024);
  denom_pub.rsa_public_key = GNUNET_CRYPTO_rsa_private_key_get_public (
    denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_hash (denom_pub.rsa_public_key, &denom_pub_hash);
  GNUNET_CRYPTO_rsa_private_key_free (denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_free (denom_pub.rsa_public_key);

  struct GNUNET_TIME_Absolute now, past, future, date;
  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);
  past = GNUNET_TIME_absolute_subtract (now,
                                        GNUNET_TIME_relative_multiply (
                                          GNUNET_TIME_UNIT_HOURS,
                                          4));
  future = GNUNET_TIME_absolute_add (now,
                                     GNUNET_TIME_relative_multiply (
                                       GNUNET_TIME_UNIT_HOURS,
                                       4));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: auditor_insert_exchange\n");
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_exchange (plugin->cls,
                                   session,
                                   &master_pub,
                                   "https://exchange/"));


  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: insert_denomination_info\n");

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
                             GNUNET_TIME_relative_multiply (
                               GNUNET_TIME_UNIT_HOURS, 2)));
  issue.expire_legal = GNUNET_TIME_absolute_hton
                         (GNUNET_TIME_absolute_add
                           (now,
                           GNUNET_TIME_relative_multiply (
                             GNUNET_TIME_UNIT_HOURS, 3)));
  TALER_amount_hton (&issue.value, &value);
  TALER_amount_hton (&issue.fee_withdraw, &fee_withdraw);
  TALER_amount_hton (&issue.fee_deposit, &fee_deposit);
  TALER_amount_hton (&issue.fee_refresh, &fee_refresh);
  TALER_amount_hton (&issue.fee_refund, &fee_refund);

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_denomination_info (plugin->cls,
                                            session,
                                            &issue));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: select_denomination_info\n");

  FAILIF (0 >=
          plugin->select_denomination_info (plugin->cls,
                                            session,
                                            &master_pub,
                                            &select_denomination_info_result,
                                            &issue));

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
                                                session,
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
                                                session,
                                                &master_pub,
                                                &ppc));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: get_auditor_progress\n");

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_auditor_progress_coin (plugin->cls,
                                             session,
                                             &master_pub,
                                             &ppc2));
  FAILIF ( (ppc.last_deposit_serial_id != ppc2.last_deposit_serial_id) ||
           (ppc.last_melt_serial_id != ppc2.last_melt_serial_id) ||
           (ppc.last_refund_serial_id != ppc2.last_refund_serial_id) ||
           (ppc.last_withdraw_serial_id != ppc2.last_withdraw_serial_id) );

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: insert_reserve_info\n");

  struct TALER_Amount reserve_balance, withdraw_fee_balance;
  struct TALER_Amount reserve_balance2 = {}, withdraw_fee_balance2 = {};

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":12.345678",
                                         &reserve_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":23.456789",
                                         &withdraw_fee_balance));


  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_reserve_info (plugin->cls,
                                       session,
                                       &reserve_pub,
                                       &master_pub,
                                       &reserve_balance,
                                       &withdraw_fee_balance,
                                       past,
                                       "payto://bla/blub"));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: update_reserve_info\n");

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->update_reserve_info (plugin->cls,
                                       session,
                                       &reserve_pub,
                                       &master_pub,
                                       &reserve_balance,
                                       &withdraw_fee_balance,
                                       future));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: get_reserve_info\n");

  char *payto;

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_reserve_info (plugin->cls,
                                    session,
                                    &reserve_pub,
                                    &master_pub,
                                    &rowid,
                                    &reserve_balance2,
                                    &withdraw_fee_balance2,
                                    &date,
                                    &payto));
  FAILIF (0 != strcmp (payto,
                       "payto://bla/blub"));
  GNUNET_free (payto);
  FAILIF (0 != GNUNET_memcmp (&date, &future)
          || 0 != GNUNET_memcmp (&reserve_balance2, &reserve_balance)
          || 0 != GNUNET_memcmp (&withdraw_fee_balance2,
                                 &withdraw_fee_balance));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: insert_reserve_summary\n");

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_reserve_summary (plugin->cls,
                                          session,
                                          &master_pub,
                                          &withdraw_fee_balance,
                                          &reserve_balance));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: update_reserve_summary\n");

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->update_reserve_summary (plugin->cls,
                                          session,
                                          &master_pub,
                                          &reserve_balance,
                                          &withdraw_fee_balance));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: get_reserve_summary\n");

  ZR_BLK (&reserve_balance2);
  ZR_BLK (&withdraw_fee_balance2);

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_reserve_summary (plugin->cls,
                                       session,
                                       &master_pub,
                                       &reserve_balance2,
                                       &withdraw_fee_balance2));

  FAILIF ( (0 != GNUNET_memcmp (&reserve_balance2,
                                &reserve_balance) ||
            (0 != GNUNET_memcmp (&withdraw_fee_balance2,
                                 &withdraw_fee_balance)) ) );

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: insert_denomination_balance\n");

  struct TALER_Amount denom_balance;
  struct TALER_Amount denom_loss;
  struct TALER_Amount denom_loss2;
  struct TALER_Amount deposit_fee_balance;
  struct TALER_Amount melt_fee_balance;
  struct TALER_Amount refund_fee_balance;
  struct TALER_Amount denom_balance2;
  struct TALER_Amount deposit_fee_balance2;
  struct TALER_Amount melt_fee_balance2;
  struct TALER_Amount refund_fee_balance2;
  struct TALER_Amount rbalance;
  struct TALER_Amount rbalance2;
  struct TALER_Amount loss;
  struct TALER_Amount loss2;
  struct TALER_Amount iirp;
  struct TALER_Amount iirp2;
  uint64_t nissued;

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":12.345678",
                                         &denom_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.1",
                                         &denom_loss));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":23.456789",
                                         &deposit_fee_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":34.567890",
                                         &melt_fee_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":45.678901",
                                         &refund_fee_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":13.57986",
                                         &rbalance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.6",
                                         &loss));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.1",
                                         &iirp));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_denomination_balance (plugin->cls,
                                               session,
                                               &denom_pub_hash,
                                               &denom_balance,
                                               &denom_loss,
                                               &rbalance,
                                               &loss,
                                               42));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: update_denomination_balance\n");

  ppc.last_withdraw_serial_id++;
  ppc.last_deposit_serial_id++;
  ppc.last_melt_serial_id++;
  ppc.last_refund_serial_id++;

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->update_denomination_balance (plugin->cls,
                                               session,
                                               &denom_pub_hash,
                                               &denom_balance,
                                               &denom_loss,
                                               &rbalance,
                                               &loss,
                                               62));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: get_denomination_balance\n");

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_denomination_balance (plugin->cls,
                                            session,
                                            &denom_pub_hash,
                                            &denom_balance2,
                                            &denom_loss2,
                                            &rbalance2,
                                            &loss2,
                                            &nissued));

  FAILIF (0 != GNUNET_memcmp (&denom_balance2, &denom_balance));
  FAILIF (0 != GNUNET_memcmp (&denom_loss2, &denom_loss));
  FAILIF (0 != GNUNET_memcmp (&rbalance2, &rbalance));
  FAILIF (62 != nissued);


  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: insert_balance_summary\n");

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_balance_summary (plugin->cls,
                                          session,
                                          &master_pub,
                                          &refund_fee_balance,
                                          &melt_fee_balance,
                                          &deposit_fee_balance,
                                          &denom_balance,
                                          &rbalance,
                                          &loss,
                                          &iirp));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: update_balance_summary\n");

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->update_balance_summary (plugin->cls,
                                          session,
                                          &master_pub,
                                          &denom_balance,
                                          &deposit_fee_balance,
                                          &melt_fee_balance,
                                          &refund_fee_balance,
                                          &rbalance,
                                          &loss,
                                          &iirp));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: get_balance_summary\n");

  ZR_BLK (&denom_balance2);
  ZR_BLK (&deposit_fee_balance2);
  ZR_BLK (&melt_fee_balance2);
  ZR_BLK (&refund_fee_balance2);
  ZR_BLK (&rbalance2);
  ZR_BLK (&loss2);
  ZR_BLK (&iirp2);

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_balance_summary (plugin->cls,
                                       session,
                                       &master_pub,
                                       &denom_balance2,
                                       &deposit_fee_balance2,
                                       &melt_fee_balance2,
                                       &refund_fee_balance2,
                                       &rbalance2,
                                       &loss2,
                                       &iirp2));

  FAILIF ( (0 != GNUNET_memcmp (&denom_balance2,
                                &denom_balance) ) ||
           (0 != GNUNET_memcmp (&deposit_fee_balance2,
                                &deposit_fee_balance) ) ||
           (0 != GNUNET_memcmp (&melt_fee_balance2,
                                &melt_fee_balance) ) ||
           (0 != GNUNET_memcmp (&refund_fee_balance2,
                                &refund_fee_balance)) );
  FAILIF (0 != GNUNET_memcmp (&rbalance2,
                              &rbalance));
  FAILIF (0 != GNUNET_memcmp (&loss2,
                              &loss));
  FAILIF (0 != GNUNET_memcmp (&iirp2,
                              &iirp));


  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: insert_historic_denom_revenue\n");

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_historic_denom_revenue (plugin->cls,
                                                 session,
                                                 &master_pub,
                                                 &denom_pub_hash,
                                                 past,
                                                 &rbalance,
                                                 &loss));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_historic_denom_revenue (plugin->cls,
                                                 session,
                                                 &master_pub,
                                                 &rnd_hash,
                                                 now,
                                                 &rbalance,
                                                 &loss));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: select_historic_denom_revenue\n");

  int
  select_historic_denom_revenue_result (void *cls,
                                        const struct
                                        GNUNET_HashCode *denom_pub_hash2,
                                        struct GNUNET_TIME_Absolute
                                        revenue_timestamp2,
                                        const struct
                                        TALER_Amount *revenue_balance2,
                                        const struct TALER_Amount *loss2)
  {
    static int n = 0;

    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "select_historic_denom_revenue_result: row %u\n", n);

    if ((2 <= n++)
        || (cls != NULL)
        || ((0 != GNUNET_memcmp (&revenue_timestamp2, &past))
            && (0 != GNUNET_memcmp (&revenue_timestamp2, &now)))
        || ((0 != GNUNET_memcmp (denom_pub_hash2, &denom_pub_hash))
            && (0 != GNUNET_memcmp (denom_pub_hash2, &rnd_hash)))
        || (0 != GNUNET_memcmp (revenue_balance2, &rbalance))
        || (0 != GNUNET_memcmp (loss2, &loss)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "select_historic_denom_revenue_result: result does not match\n");
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  }


  FAILIF (0 >=
          plugin->select_historic_denom_revenue (plugin->cls,
                                                 session,
                                                 &master_pub,
                                                 &
                                                 select_historic_denom_revenue_result,
                                                 NULL));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: insert_historic_reserve_revenue\n");

  struct TALER_Amount reserve_profits;
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":56.789012",
                                         &reserve_profits));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_historic_reserve_revenue (plugin->cls,
                                                   session,
                                                   &master_pub,
                                                   past,
                                                   future,
                                                   &reserve_profits));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_historic_reserve_revenue (plugin->cls,
                                                   session,
                                                   &master_pub,
                                                   now,
                                                   future,
                                                   &reserve_profits));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: select_historic_reserve_revenue\n");

  int
  select_historic_reserve_revenue_result (void *cls,
                                          struct GNUNET_TIME_Absolute
                                          start_time2,
                                          struct GNUNET_TIME_Absolute end_time2,
                                          const struct
                                          TALER_Amount *reserve_profits2)
  {
    static int n = 0;

    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "select_historic_reserve_revenue_result: row %u\n", n);

    if ((2 <= n++)
        || (cls != NULL)
        || ((0 != GNUNET_memcmp (&start_time2, &past))
            && (0 != GNUNET_memcmp (&start_time2, &now)))
        || (0 != GNUNET_memcmp (&end_time2, &future))
        || (0 != GNUNET_memcmp (reserve_profits2, &reserve_profits)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "select_historic_reserve_revenue_result: result does not match\n");
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  }


  FAILIF (0 >=
          plugin->select_historic_reserve_revenue (plugin->cls,
                                                   session,
                                                   &master_pub,
                                                   select_historic_reserve_revenue_result,
                                                   NULL));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: insert_predicted_result\n");

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_predicted_result (plugin->cls,
                                           session,
                                           &master_pub,
                                           &rbalance));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: update_predicted_result\n");

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":78.901234",
                                         &rbalance));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->update_predicted_result (plugin->cls,
                                           session,
                                           &master_pub,
                                           &rbalance));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_wire_fee_summary (plugin->cls,
                                           session,
                                           &master_pub,
                                           &rbalance));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->update_wire_fee_summary (plugin->cls,
                                           session,
                                           &master_pub,
                                           &reserve_profits));
  {
    struct TALER_Amount rprof;

    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->get_wire_fee_summary (plugin->cls,
                                          session,
                                          &master_pub,
                                          &rprof));
    FAILIF (0 !=
            TALER_amount_cmp (&rprof,
                              &reserve_profits));
  }
  FAILIF (0 >
          plugin->commit (plugin->cls,
                          session));


  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         session));

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Test: get_predicted_balance\n");

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_predicted_balance (plugin->cls,
                                         session,
                                         &master_pub,
                                         &rbalance2));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->del_reserve_info (plugin->cls,
                                    session,
                                    &reserve_pub,
                                    &master_pub));

  FAILIF (0 != TALER_amount_cmp (&rbalance2,
                                 &rbalance));

  plugin->rollback (plugin->cls,
                    session);

#if GC_IMPLEMENTED
  FAILIF (GNUNET_OK !=
          plugin->gc (plugin->cls));
#endif

  result = 0;

drop:
  if (NULL != session)
  {
    plugin->rollback (plugin->cls,
                      session);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Test: auditor_delete_exchange\n");
    GNUNET_break (GNUNET_OK ==
                  plugin->start (plugin->cls,
                                 session));
    GNUNET_break (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
                  plugin->delete_exchange (plugin->cls,
                                           session,
                                           &master_pub));
    GNUNET_break (0 <=
                  plugin->commit (plugin->cls,
                                  session));
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
