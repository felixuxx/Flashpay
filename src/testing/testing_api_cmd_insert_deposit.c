/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_insert_deposit.c
 * @brief deposit a coin directly into the database.
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * State for a "insert-deposit" CMD.
 */
struct InsertDepositState
{
  /**
   * Configuration file used by the command.
   */
  const struct TALER_TESTING_DatabaseConnection *dbc;

  /**
   * Human-readable name of the shop.
   */
  const char *merchant_name;

  /**
   * Merchant account name (NOT a payto-URI).
   */
  const char *merchant_account;

  /**
   * Deadline before which the aggregator should
   * send the payment to the merchant.
   */
  struct GNUNET_TIME_Relative wire_deadline;

  /**
   * When did the exchange receive the deposit?
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * Amount to deposit, inclusive of deposit fee.
   */
  const char *amount_with_fee;

  /**
   * Deposit fee.
   */
  const char *deposit_fee;
};

/**
 * Setup (fake) information about a coin used in deposit.
 *
 * @param[out] issue information to initialize with "valid" data
 */
static void
fake_issue (struct TALER_EXCHANGEDB_DenominationKeyInformationP *issue)
{
  struct GNUNET_TIME_Timestamp now;

  memset (issue,
          0,
          sizeof (struct TALER_EXCHANGEDB_DenominationKeyInformationP));
  now = GNUNET_TIME_timestamp_get ();
  issue->properties.start
    = GNUNET_TIME_timestamp_hton (now);
  issue->properties.expire_withdraw
    = GNUNET_TIME_timestamp_hton (
        GNUNET_TIME_relative_to_timestamp (GNUNET_TIME_UNIT_MINUTES));
  issue->properties.expire_deposit
    = GNUNET_TIME_timestamp_hton (
        GNUNET_TIME_relative_to_timestamp (GNUNET_TIME_UNIT_HOURS));
  issue->properties.expire_legal
    = GNUNET_TIME_timestamp_hton (
        GNUNET_TIME_relative_to_timestamp (GNUNET_TIME_UNIT_DAYS));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount_nbo ("EUR:1",
                                             &issue->properties.value));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount_nbo ("EUR:0.1",
                                             &issue->properties.fee_withdraw));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount_nbo ("EUR:0.1",
                                             &issue->properties.fee_deposit));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount_nbo ("EUR:0.1",
                                             &issue->properties.fee_refresh));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount_nbo ("EUR:0.1",
                                             &issue->properties.fee_refund));
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the commaind being run.
 * @param is interpreter state.
 */
static void
insert_deposit_run (void *cls,
                    const struct TALER_TESTING_Command *cmd,
                    struct TALER_TESTING_Interpreter *is)
{
  struct InsertDepositState *ids = cls;
  struct TALER_EXCHANGEDB_Deposit deposit;
  struct TALER_MerchantPrivateKeyP merchant_priv;
  struct TALER_EXCHANGEDB_DenominationKeyInformationP issue;
  struct TALER_DenominationPublicKey dpk;
  struct TALER_DenominationPrivateKey denom_priv;

  (void) cmd;
  // prepare and store issue first.
  fake_issue (&issue);
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_priv_create (&denom_priv,
                                          &dpk,
                                          TALER_DENOMINATION_RSA,
                                          1024));
  TALER_denom_pub_hash (&dpk,
                        &issue.properties.denom_hash);

  if ( (GNUNET_OK !=
        ids->dbc->plugin->start (ids->dbc->plugin->cls,
                                 "talertestinglib: denomination insertion")) ||
       (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
        ids->dbc->plugin->insert_denomination_info (ids->dbc->plugin->cls,
                                                    &dpk,
                                                    &issue)) ||
       (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
        ids->dbc->plugin->commit (ids->dbc->plugin->cls)) )
  {
    TALER_TESTING_interpreter_fail (is);
    TALER_denom_pub_free (&dpk);
    TALER_denom_priv_free (&denom_priv);
    return;
  }

  /* prepare and store deposit now. */
  memset (&deposit,
          0,
          sizeof (deposit));

  GNUNET_CRYPTO_kdf (&merchant_priv,
                     sizeof (struct TALER_MerchantPrivateKeyP),
                     "merchant-priv",
                     strlen ("merchant-priv"),
                     ids->merchant_name,
                     strlen (ids->merchant_name),
                     NULL,
                     0);
  GNUNET_CRYPTO_eddsa_key_get_public (&merchant_priv.eddsa_priv,
                                      &deposit.merchant_pub.eddsa_pub);
  GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_WEAK,
                                    &deposit.h_contract_terms.hash);
  if ( (GNUNET_OK !=
        TALER_string_to_amount (ids->amount_with_fee,
                                &deposit.amount_with_fee)) ||
       (GNUNET_OK !=
        TALER_string_to_amount (ids->deposit_fee,
                                &deposit.deposit_fee)) )
  {
    TALER_TESTING_interpreter_fail (is);
    TALER_denom_pub_free (&dpk);
    TALER_denom_priv_free (&denom_priv);
    return;
  }

  TALER_denom_pub_hash (&dpk,
                        &deposit.coin.denom_pub_hash);
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &deposit.coin.coin_pub,
                              sizeof (deposit.coin.coin_pub));
  {
    struct TALER_CoinPubHash c_hash;
    struct TALER_PlanchetDetail pd;
    struct TALER_BlindedDenominationSignature bds;
    union TALER_DenominationBlindingKeyP bks;

    TALER_blinding_secret_create (&bks, TALER_DENOMINATION_RSA);
    GNUNET_assert (GNUNET_OK ==
                   TALER_denom_blind (&dpk,
                                      &bks,
                                      NULL, /* FIXME-Oec */
                                      &deposit.coin.coin_pub,
                                      &c_hash,
                                      &pd.blinded_planchet));
    GNUNET_assert (GNUNET_OK ==
                   TALER_denom_sign_blinded (&bds,
                                             &denom_priv,
                                             &pd.blinded_planchet));
    GNUNET_free (pd.blinded_planchet.details.rsa_blinded_planchet.blinded_msg);
    GNUNET_assert (GNUNET_OK ==
                   TALER_denom_sig_unblind (&deposit.coin.denom_sig,
                                            &bds,
                                            &bks,
                                            &dpk));
    TALER_blinded_denom_sig_free (&bds);
  }
  GNUNET_asprintf (&deposit.receiver_wire_account,
                   "payto://x-taler-bank/localhost/%s",
                   ids->merchant_account);
  memset (&deposit.wire_salt,
          46,
          sizeof (deposit.wire_salt));
  deposit.timestamp = GNUNET_TIME_timestamp_get ();
  deposit.wire_deadline = GNUNET_TIME_relative_to_timestamp (
    ids->wire_deadline);
  /* finally, actually perform the DB operation */
  {
    uint64_t known_coin_id;
    struct TALER_DenominationHash dph;
    struct TALER_AgeHash agh;

    if ( (GNUNET_OK !=
          ids->dbc->plugin->start (ids->dbc->plugin->cls,
                                   "libtalertesting: insert deposit")) ||
         (0 >
          ids->dbc->plugin->ensure_coin_known (ids->dbc->plugin->cls,
                                               &deposit.coin,
                                               &known_coin_id,
                                               &dph,
                                               &agh)) ||
         (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          ids->dbc->plugin->insert_deposit (ids->dbc->plugin->cls,
                                            ids->exchange_timestamp,
                                            &deposit)) ||
         (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          ids->dbc->plugin->commit (ids->dbc->plugin->cls)) )
    {
      GNUNET_break (0);
      ids->dbc->plugin->rollback (ids->dbc->plugin->cls);
      GNUNET_free (deposit.receiver_wire_account);
      TALER_denom_pub_free (&dpk);
      TALER_denom_priv_free (&denom_priv);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
  }

  TALER_denom_sig_free (&deposit.coin.denom_sig);
  TALER_denom_pub_free (&dpk);
  TALER_denom_priv_free (&denom_priv);
  GNUNET_free (deposit.receiver_wire_account);
  TALER_TESTING_interpreter_next (is);
}


/**
 * Free the state of a "auditor-dbinit" CMD, and possibly kills its
 * process if it did not terminate correctly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
insert_deposit_cleanup (void *cls,
                        const struct TALER_TESTING_Command *cmd)
{
  struct InsertDepositState *ids = cls;

  (void) cmd;
  GNUNET_free (ids);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_insert_deposit (
  const char *label,
  const struct TALER_TESTING_DatabaseConnection *dbc,
  const char *merchant_name,
  const char *merchant_account,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  struct GNUNET_TIME_Relative wire_deadline,
  const char *amount_with_fee,
  const char *deposit_fee)
{
  struct InsertDepositState *ids;

  ids = GNUNET_new (struct InsertDepositState);
  ids->dbc = dbc;
  ids->merchant_name = merchant_name;
  ids->merchant_account = merchant_account;
  ids->exchange_timestamp = exchange_timestamp;
  ids->wire_deadline = wire_deadline;
  ids->amount_with_fee = amount_with_fee;
  ids->deposit_fee = deposit_fee;

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ids,
      .label = label,
      .run = &insert_deposit_run,
      .cleanup = &insert_deposit_cleanup
    };

    return cmd;
  }
}


/* end of testing_api_cmd_insert_deposit.c */
