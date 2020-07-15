/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file testing/testing_api_cmd_refund.c
 * @brief Implement the /refund test command, plus other
 *        corollary commands (?).
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "refund" CMD.
 */
struct RefundState
{
  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Amount to be refunded.
   */
  const char *refund_amount;

  /**
   * Reference to any command that can provide a coin to refund.
   */
  const char *coin_reference;

  /**
   * Refund transaction identifier.
   */
  uint64_t refund_transaction_id;

  /**
   * Connection to the exchange.
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * Handle to the refund operation.
   */
  struct TALER_EXCHANGE_RefundHandle *rh;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;
};


/**
 * Check the result for the refund request, just check if the
 * response code is acceptable.
 *
 * @param cls closure
 * @param hr HTTP response details
 * @param refund_fee the refund fee the exchange charged
 * @param exchange_pub public key the exchange
 *        used for signing @a obj.
 * @param exchange_sig actual signature confirming the refund
 */
static void
refund_cb (void *cls,
           const struct TALER_EXCHANGE_HttpResponse *hr,
           const struct TALER_Amount *refund_fee,
           const struct TALER_ExchangePublicKeyP *exchange_pub,
           const struct TALER_ExchangeSignatureP *exchange_sig)
{

  struct RefundState *rs = cls;
  struct TALER_TESTING_Command *refund_cmd;

  (void) refund_fee;
  refund_cmd = &rs->is->commands[rs->is->ip];
  rs->rh = NULL;
  if (rs->expected_response_code != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d to command %s in %s:%u\n",
                hr->http_status,
                hr->ec,
                refund_cmd->label,
                __FILE__,
                __LINE__);
    json_dumpf (hr->reply,
                stderr,
                0);
    TALER_TESTING_interpreter_fail (rs->is);
    return;
  }
  TALER_TESTING_interpreter_next (rs->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
refund_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct RefundState *rs = cls;
  const struct TALER_CoinSpendPrivateKeyP *coin_priv;
  struct TALER_CoinSpendPublicKeyP coin;
  const json_t *contract_terms;
  struct GNUNET_HashCode h_contract_terms;
  struct TALER_Amount refund_amount;
  const struct TALER_MerchantPrivateKeyP *merchant_priv;
  const struct TALER_TESTING_Command *coin_cmd;

  rs->exchange = is->exchange;
  rs->is = is;

  if (GNUNET_OK !=
      TALER_string_to_amount (rs->refund_amount,
                              &refund_amount))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse amount `%s' at %u/%s\n",
                rs->refund_amount,
                is->ip,
                cmd->label);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  coin_cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                       rs->coin_reference);
  if (NULL == coin_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_contract_terms (coin_cmd,
                                              0,
                                              &contract_terms))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_contract_hash (contract_terms,
                                           &h_contract_terms));

  /* Hunting for a coin .. */
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_coin_priv (coin_cmd,
                                         0,
                                         &coin_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv->eddsa_priv,
                                      &coin.eddsa_pub);
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_merchant_priv (coin_cmd,
                                             0,
                                             &merchant_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  rs->rh = TALER_EXCHANGE_refund (rs->exchange,
                                  &refund_amount,
                                  &h_contract_terms,
                                  &coin,
                                  rs->refund_transaction_id,
                                  merchant_priv,
                                  &refund_cb,
                                  rs);
  GNUNET_assert (NULL != rs->rh);
}


/**
 * Free the state from a "refund" CMD, and possibly cancel
 * a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
refund_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct RefundState *rs = cls;

  if (NULL != rs->rh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                rs->is->ip,
                cmd->label);
    TALER_EXCHANGE_refund_cancel (rs->rh);
    rs->rh = NULL;
  }
  GNUNET_free (rs);
}


/**
 * Create a "refund" command.
 *
 * @param label command label.
 * @param expected_response_code expected HTTP status code.
 * @param refund_amount the amount to ask a refund for.
 * @param coin_reference reference to a command that can
 *        provide a coin to be refunded.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refund (const char *label,
                          unsigned int expected_response_code,
                          const char *refund_amount,
                          const char *coin_reference)
{
  struct RefundState *rs;

  rs = GNUNET_new (struct RefundState);

  rs->expected_response_code = expected_response_code;
  rs->refund_amount = refund_amount;
  rs->coin_reference = coin_reference;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = rs,
      .label = label,
      .run = &refund_run,
      .cleanup = &refund_cleanup
    };

    return cmd;
  }
}


/**
 * Create a "refund" command, allow to specify refund transaction
 * id.  Mainly used to create conflicting requests.
 *
 * @param label command label.
 * @param expected_response_code expected HTTP status code.
 * @param refund_amount the amount to ask a refund for.
 * @param coin_reference reference to a command that can
 *        provide a coin to be refunded.
 * @param refund_transaction_id transaction id to use
 *        in the request.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_refund_with_id
  (const char *label,
  unsigned int expected_response_code,
  const char *refund_amount,
  const char *coin_reference,
  uint64_t refund_transaction_id)
{
  struct RefundState *rs;

  rs = GNUNET_new (struct RefundState);
  rs->expected_response_code = expected_response_code;
  rs->refund_amount = refund_amount;
  rs->coin_reference = coin_reference;
  rs->refund_transaction_id = refund_transaction_id;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = rs,
      .label = label,
      .run = &refund_run,
      .cleanup = &refund_cleanup
    };

    return cmd;
  }
}
