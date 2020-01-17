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
 * @file auditor-lib/testing_api_cmd_insert_deposit.c
 * @brief deposit a coin directly into the database.
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "auditor_api_handle.h"
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
  memset (issue, 0, sizeof (struct
                            TALER_EXCHANGEDB_DenominationKeyInformationP));
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
  struct GNUNET_CRYPTO_RsaPrivateKey *denom_priv;
  struct GNUNET_HashCode hc;

  // prepare and store issue first.
  fake_issue (&issue);
  denom_priv = GNUNET_CRYPTO_rsa_private_key_create (1024);
  dpk.rsa_public_key = GNUNET_CRYPTO_rsa_private_key_get_public (denom_priv);
  GNUNET_CRYPTO_rsa_public_key_hash (dpk.rsa_public_key,
                                     &issue.properties.denom_hash);

  if ( (GNUNET_OK !=
        ids->dbc->plugin->start (ids->dbc->plugin->cls,
                                 ids->dbc->session,
                                 "talertestinglib: denomination insertion")) ||
       (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
        ids->dbc->plugin->insert_denomination_info (ids->dbc->plugin->cls,
                                                    ids->dbc->session,
                                                    &dpk,
                                                    &issue)) ||
       (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
        ids->dbc->plugin->commit (ids->dbc->plugin->cls,
                                  ids->dbc->session)) )
  {
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  // prepare and store deposit now.
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
                                    &deposit.h_contract_terms);
  if ( (GNUNET_OK !=
        TALER_string_to_amount (ids->amount_with_fee,
                                &deposit.amount_with_fee)) ||
       (GNUNET_OK !=
        TALER_string_to_amount (ids->deposit_fee,
                                &deposit.deposit_fee)) )
  {
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  GNUNET_CRYPTO_rsa_public_key_hash (dpk.rsa_public_key,
                                     &deposit.coin.denom_pub_hash);

  GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_WEAK,
                                    &hc);
  deposit.coin.denom_sig.rsa_signature = GNUNET_CRYPTO_rsa_sign_fdh (denom_priv,
                                                                     &hc);
  {
    char *str;

    GNUNET_asprintf (&str,
                     "payto://x-taler-bank/localhost/%s",
                     ids->merchant_account);
    deposit.receiver_wire_account
      = json_pack ("{s:s, s:s}",
                   "salt", "this-is-a-salt-value",
                   "url", str);
    GNUNET_free (str);
  }

  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_merchant_wire_signature_hash (
                   deposit.receiver_wire_account,
                   &deposit.h_wire));
  deposit.timestamp = GNUNET_TIME_absolute_get ();
  GNUNET_TIME_round_abs (&deposit.timestamp);
  deposit.wire_deadline = GNUNET_TIME_relative_to_absolute (
    ids->wire_deadline);
  GNUNET_TIME_round_abs (&deposit.wire_deadline);

  /* finally, actually perform the DB operation */
  if ( (GNUNET_OK !=
        ids->dbc->plugin->start (ids->dbc->plugin->cls,
                                 ids->dbc->session,
                                 "libtalertesting: insert deposit")) ||
       (0 >
        ids->dbc->plugin->ensure_coin_known (ids->dbc->plugin->cls,
                                             ids->dbc->session,
                                             &deposit.coin)) ||
       (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
        ids->dbc->plugin->insert_deposit (ids->dbc->plugin->cls,
                                          ids->dbc->session,
                                          &deposit)) ||
       (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
        ids->dbc->plugin->commit (ids->dbc->plugin->cls,
                                  ids->dbc->session)) )
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
  }

  GNUNET_CRYPTO_rsa_signature_free (deposit.coin.denom_sig.rsa_signature);
  GNUNET_CRYPTO_rsa_public_key_free (dpk.rsa_public_key);
  GNUNET_CRYPTO_rsa_private_key_free (denom_priv);
  json_decref (deposit.receiver_wire_account);

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

  GNUNET_free (ids);
}


/**
 * Offer "insert-deposit" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param ret[out] result
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static int
insert_deposit_traits (void *cls,
                       const void **ret,
                       const char *trait,
                       unsigned int index)
{
  return GNUNET_NO;
}


/**
 * Make the "insert-deposit" CMD.
 *
 * @param label command label.
 * @param dbc collects database plugin and session handles.
 * @param merchant_name Human-readable name of the merchant.
 * @param merchant_account merchant's account name (NOT a payto:// URI)
 * @param wire_deadline point in time where the aggregator should have
 *        wired money to the merchant.
 * @param amount_with_fee amount to deposit (inclusive of deposit fee)
 * @param deposit_fee deposit fee
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_insert_deposit (const char *label,
                                  const struct
                                  TALER_TESTING_DatabaseConnection *dbc,
                                  const char *merchant_name,
                                  const char *merchant_account,
                                  struct GNUNET_TIME_Relative wire_deadline,
                                  const char *amount_with_fee,
                                  const char *deposit_fee)
{
  struct TALER_TESTING_Command cmd;
  struct InsertDepositState *ids;

  ids = GNUNET_new (struct InsertDepositState);
  ids->dbc = dbc;
  ids->merchant_name = merchant_name;
  ids->merchant_account = merchant_account;
  ids->wire_deadline = wire_deadline;
  ids->amount_with_fee = amount_with_fee;
  ids->deposit_fee = deposit_fee;

  cmd.cls = ids;
  cmd.label = label;
  cmd.run = &insert_deposit_run;
  cmd.cleanup = &insert_deposit_cleanup;
  cmd.traits = &insert_deposit_traits;

  return cmd;
}


/* end of testing_api_cmd_insert_deposit.c */
