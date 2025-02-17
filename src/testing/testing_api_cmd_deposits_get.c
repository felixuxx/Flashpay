/*
  This file is part of TALER
  Copyright (C) 2014-2021, 2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/

/**
 * @file testing/testing_api_cmd_deposits_get.c
 * @brief Implement the testing CMDs for the /deposits/ GET operations.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"

/**
 * State for a "track transaction" CMD.
 */
struct TrackTransactionState
{

  /**
   * If non NULL, will provide a WTID to be compared against
   * the one returned by the "track transaction" operation.
   */
  const char *bank_transfer_reference;

  /**
   * Our command.
   */
  const struct TALER_TESTING_Command *cmd;

  /**
   * The WTID associated by the transaction being tracked.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Set to the KYC requirement payto hash *if* the exchange replied with a
   * request for KYC (#MHD_HTTP_ACCEPTED).
   * Note: set based on our @e merchant_payto_uri, as
   * the exchange does not respond with the payto hash.
   */
  struct TALER_NormalizedPaytoHashP h_payto;

  /**
   * Set to the KYC requirement row *if* the exchange replied with
   * a request for KYC (#MHD_HTTP_ACCEPTED).
   */
  uint64_t requirement_row;

  /**
   * Reference to any operation that can provide a transaction.
   * Will be the transaction to track.
   */
  const char *transaction_reference;

  /**
   * Payto URI of the merchant receiving the deposit.
   */
  struct TALER_FullPayto merchant_payto_uri;

  /**
   * Index of the coin involved in the transaction.  Recall:
   * at the exchange, the tracking is done _per coin_.
   */
  unsigned int coin_index;

  /**
   * Handle to the "track transaction" pending operation.
   */
  struct TALER_EXCHANGE_DepositGetHandle *tth;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;
};


/**
 * Checks what is returned by the "track transaction" operation.
 * Checks that the HTTP response code is acceptable, and - if the
 * right reference is non NULL - that the wire transfer subject
 * line matches our expectations.
 *
 * @param cls closure.
 * @param dr GET deposit response details
 */
static void
deposit_wtid_cb (
  void *cls,
  const struct TALER_EXCHANGE_GetDepositResponse *dr)
{
  struct TrackTransactionState *tts = cls;
  struct TALER_TESTING_Interpreter *is = tts->is;

  tts->tth = NULL;
  if (tts->expected_response_code != dr->hr.http_status)
  {
    TALER_TESTING_unexpected_status (is,
                                     dr->hr.http_status,
                                     tts->expected_response_code);
    return;
  }
  switch (dr->hr.http_status)
  {
  case MHD_HTTP_OK:
    tts->wtid = dr->details.ok.wtid;
    if (NULL != tts->bank_transfer_reference)
    {
      const struct TALER_TESTING_Command *bank_transfer_cmd;
      const struct TALER_WireTransferIdentifierRawP *wtid_want;

      /* _this_ wire transfer subject line.  */
      bank_transfer_cmd
        = TALER_TESTING_interpreter_lookup_command (is,
                                                    tts->bank_transfer_reference
                                                    );
      if (NULL == bank_transfer_cmd)
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }

      if (GNUNET_OK !=
          TALER_TESTING_get_trait_wtid (bank_transfer_cmd,
                                        &wtid_want))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }

      /* Compare that expected and gotten subjects match.  */
      if (0 != GNUNET_memcmp (&dr->details.ok.wtid,
                              wtid_want))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (tts->is);
        return;
      }
    }
    break;
  case MHD_HTTP_ACCEPTED:
    /* allowed, nothing to check here */
    TALER_full_payto_normalize_and_hash (tts->merchant_payto_uri,
                                         &tts->h_payto);
    tts->requirement_row
      = dr->details.accepted.requirement_row;
    break;
  case MHD_HTTP_NOT_FOUND:
    /* allowed, nothing to check here */
    break;
  default:
    GNUNET_break (0);
    break;
  }
  TALER_TESTING_interpreter_next (tts->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
deposits_get_run (
  void *cls,
  const struct TALER_TESTING_Command *cmd,
  struct TALER_TESTING_Interpreter *is)
{
  struct TrackTransactionState *tts = cls;
  const struct TALER_TESTING_Command *transaction_cmd;
  const struct TALER_CoinSpendPrivateKeyP *coin_priv;
  struct TALER_CoinSpendPublicKeyP coin_pub;
  const json_t *contract_terms;
  const json_t *wire_details;
  struct TALER_MerchantWireHashP h_wire_details;
  struct TALER_PrivateContractHashP h_contract_terms;
  const struct TALER_MerchantPrivateKeyP *merchant_priv;

  tts->cmd = cmd;
  tts->is = is;
  transaction_cmd
    = TALER_TESTING_interpreter_lookup_command (tts->is,
                                                tts->transaction_reference);
  if (NULL == transaction_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (tts->is);
    return;
  }

  if (GNUNET_OK !=
      TALER_TESTING_get_trait_coin_priv (transaction_cmd,
                                         tts->coin_index,
                                         &coin_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (tts->is);
    return;
  }

  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv->eddsa_priv,
                                      &coin_pub.eddsa_pub);

  /* Get the strings.. */
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_wire_details (transaction_cmd,
                                            &wire_details))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (tts->is);
    return;
  }
  tts->merchant_payto_uri.full_payto
    = GNUNET_strdup (json_string_value (json_object_get (wire_details,
                                                         "payto_uri")));
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_contract_terms (transaction_cmd,
                                              &contract_terms))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (tts->is);
    return;
  }

  if ( (NULL == wire_details) ||
       (NULL == contract_terms) )
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (tts->is);
    return;
  }

  /* Should not fail here, json has been parsed already */
  GNUNET_assert
    ( (GNUNET_OK ==
       TALER_JSON_merchant_wire_signature_hash (wire_details,
                                                &h_wire_details)) &&
    (GNUNET_OK ==
     TALER_JSON_contract_hash (contract_terms,
                               &h_contract_terms)) );

  if (GNUNET_OK !=
      TALER_TESTING_get_trait_merchant_priv (transaction_cmd,
                                             &merchant_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (tts->is);
    return;
  }

  tts->tth = TALER_EXCHANGE_deposits_get (
    TALER_TESTING_interpreter_get_context (is),
    TALER_TESTING_get_exchange_url (is),
    TALER_TESTING_get_keys (is),
    merchant_priv,
    &h_wire_details,
    &h_contract_terms,
    &coin_pub,
    GNUNET_TIME_UNIT_ZERO,
    &deposit_wtid_cb,
    tts);
  GNUNET_assert (NULL != tts->tth);
}


/**
 * Cleanup the state from a "track transaction" CMD, and possibly
 * cancel a operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
deposits_get_cleanup (
  void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  struct TrackTransactionState *tts = cls;

  if (NULL != tts->tth)
  {
    TALER_TESTING_command_incomplete (tts->is,
                                      cmd->label);
    TALER_EXCHANGE_deposits_get_cancel (tts->tth);
    tts->tth = NULL;
  }
  GNUNET_free (tts->merchant_payto_uri.full_payto);
  GNUNET_free (tts);
}


/**
 * Offer internal data from a "track transaction" CMD.
 *
 * @param cls closure.
 * @param[out] ret result (could be anything).
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
deposits_get_traits (void *cls,
                     const void **ret,
                     const char *trait,
                     unsigned int index)
{
  struct TrackTransactionState *tts = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_wtid (&tts->wtid),
    TALER_TESTING_make_trait_legi_requirement_row (
      &tts->requirement_row),
    TALER_TESTING_make_trait_h_normalized_payto (&tts->h_payto),
    TALER_TESTING_make_trait_full_payto_uri (&tts->merchant_payto_uri),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_deposits_get (
  const char *label,
  const char *transaction_reference,
  unsigned int coin_index,
  unsigned int expected_response_code,
  const char *bank_transfer_reference)
{
  struct TrackTransactionState *tts;

  tts = GNUNET_new (struct TrackTransactionState);
  tts->transaction_reference = transaction_reference;
  tts->expected_response_code = expected_response_code;
  tts->bank_transfer_reference = bank_transfer_reference;
  tts->coin_index = coin_index;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = tts,
      .label = label,
      .run = &deposits_get_run,
      .cleanup = &deposits_get_cleanup,
      .traits = &deposits_get_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_deposits_get.c */
