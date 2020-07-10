/*
  This file is part of TALER
  Copyright (C) 2018-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_withdraw.c
 * @brief main interpreter loop for testcases
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <microhttpd.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"
#include "backoff.h"


/**
 * How often do we retry before giving up?
 */
#define NUM_RETRIES 15

/**
 * How long do we wait AT LEAST if the exchange says the reserve is unknown?
 */
#define UNKNOWN_MIN_BACKOFF GNUNET_TIME_relative_multiply ( \
    GNUNET_TIME_UNIT_MILLISECONDS, 10)

/**
 * How long do we wait AT MOST if the exchange says the reserve is unknown?
 */
#define UNKNOWN_MAX_BACKOFF GNUNET_TIME_relative_multiply ( \
    GNUNET_TIME_UNIT_MILLISECONDS, 100)

/**
 * State for a "withdraw" CMD.
 */
struct WithdrawState
{

  /**
   * Which reserve should we withdraw from?
   */
  const char *reserve_reference;

  /**
   * Reference to a withdraw or reveal operation from which we should
   * re-use the private coin key, or NULL for regular withdrawal.
   */
  const char *reuse_coin_key_ref;

  /**
   * String describing the denomination value we should withdraw.
   * A corresponding denomination key must exist in the exchange's
   * offerings.  Can be NULL if @e pk is set instead.
   */
  struct TALER_Amount amount;

  /**
   * If @e amount is NULL, this specifies the denomination key to
   * use.  Otherwise, this will be set (by the interpreter) to the
   * denomination PK matching @e amount.
   */
  struct TALER_EXCHANGE_DenomPublicKey *pk;

  /**
   * Exchange base URL.  Only used as offered trait.
   */
  char *exchange_url;

  /**
   * Interpreter state (during command).
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Set (by the interpreter) to the exchange's signature over the
   * coin's public key.
   */
  struct TALER_DenominationSignature sig;

  /**
   * Private key material of the coin, set by the interpreter.
   */
  struct TALER_PlanchetSecretsP ps;

  /**
   * Reserve history entry that corresponds to this operation.
   * Will be of type #TALER_EXCHANGE_RTT_WITHDRAWAL.
   */
  struct TALER_EXCHANGE_ReserveHistory reserve_history;

  /**
   * Withdraw handle (while operation is running).
   */
  struct TALER_EXCHANGE_WithdrawHandle *wsh;

  /**
   * Task scheduled to try later.
   */
  struct GNUNET_SCHEDULER_Task *retry_task;

  /**
   * How long do we wait until we retry?
   */
  struct GNUNET_TIME_Relative backoff;

  /**
   * Total withdraw backoff applied.
   */
  struct GNUNET_TIME_Relative total_backoff;

  /**
   * Expected HTTP response code to the request.
   */
  unsigned int expected_response_code;

  /**
   * Was this command modified via
   * #TALER_TESTING_cmd_withdraw_with_retry to
   * enable retries? How often should we still retry?
   */
  unsigned int do_retry;
};


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the commaind being run.
 * @param is interpreter state.
 */
static void
withdraw_run (void *cls,
              const struct TALER_TESTING_Command *cmd,
              struct TALER_TESTING_Interpreter *is);


/**
 * Task scheduled to re-try #withdraw_run.
 *
 * @param cls a `struct WithdrawState`
 */
static void
do_retry (void *cls)
{
  struct WithdrawState *ws = cls;

  ws->retry_task = NULL;
  ws->is->commands[ws->is->ip].last_req_time
    = GNUNET_TIME_absolute_get ();
  withdraw_run (ws,
                NULL,
                ws->is);
}


/**
 * "reserve withdraw" operation callback; checks that the
 * response code is expected and store the exchange signature
 * in the state.
 *
 * @param cls closure.
 * @param hr HTTP response details
 * @param sig signature over the coin, NULL on error.
 */
static void
reserve_withdraw_cb (void *cls,
                     const struct TALER_EXCHANGE_HttpResponse *hr,
                     const struct TALER_DenominationSignature *sig)
{
  struct WithdrawState *ws = cls;
  struct TALER_TESTING_Interpreter *is = ws->is;

  ws->wsh = NULL;
  if (ws->expected_response_code != hr->http_status)
  {
    if (0 != ws->do_retry)
    {
      if (TALER_EC_WITHDRAW_RESERVE_UNKNOWN != hr->ec)
        ws->do_retry--; /* we don't count reserve unknown as failures here */
      if ( (0 == hr->http_status) ||
           (TALER_EC_DB_COMMIT_FAILED_ON_RETRY == hr->ec) ||
           (TALER_EC_WITHDRAW_INSUFFICIENT_FUNDS == hr->ec) ||
           (TALER_EC_WITHDRAW_RESERVE_UNKNOWN == hr->ec) ||
           (MHD_HTTP_INTERNAL_SERVER_ERROR == hr->http_status) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Retrying withdraw failed with %u/%d\n",
                    hr->http_status,
                    (int) hr->ec);
        /* on DB conflicts, do not use backoff */
        if (TALER_EC_DB_COMMIT_FAILED_ON_RETRY == hr->ec)
          ws->backoff = GNUNET_TIME_UNIT_ZERO;
        else if (TALER_EC_WITHDRAW_RESERVE_UNKNOWN != hr->ec)
          ws->backoff = EXCHANGE_LIB_BACKOFF (ws->backoff);
        else
          ws->backoff = GNUNET_TIME_relative_max (UNKNOWN_MIN_BACKOFF,
                                                  ws->backoff);
        ws->backoff = GNUNET_TIME_relative_min (ws->backoff,
                                                UNKNOWN_MAX_BACKOFF);
        ws->total_backoff = GNUNET_TIME_relative_add (ws->total_backoff,
                                                      ws->backoff);
        ws->is->commands[ws->is->ip].num_tries++;
        ws->retry_task = GNUNET_SCHEDULER_add_delayed (ws->backoff,
                                                       &do_retry,
                                                       ws);
        return;
      }
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d to command %s in %s:%u\n",
                hr->http_status,
                (int) hr->ec,
                TALER_TESTING_interpreter_get_current_label (is),
                __FILE__,
                __LINE__);
    json_dumpf (hr->reply,
                stderr,
                0);
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  switch (hr->http_status)
  {
  case MHD_HTTP_OK:
    if (NULL == sig)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    ws->sig.rsa_signature = GNUNET_CRYPTO_rsa_signature_dup (
      sig->rsa_signature);
    if (0 != ws->total_backoff.rel_value_us)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Total withdraw backoff for %s was %s\n",
                  is->commands[is->ip].label,
                  GNUNET_STRINGS_relative_time_to_string (ws->total_backoff,
                                                          GNUNET_YES));
    }
    break;
  case MHD_HTTP_FORBIDDEN:
    /* nothing to check */
    break;
  case MHD_HTTP_CONFLICT:
    /* nothing to check */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* nothing to check */
    break;
  default:
    /* Unsupported status code (by test harness) */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Withdraw test command does not support status code %u\n",
                hr->http_status);
    GNUNET_break (0);
    break;
  }
  TALER_TESTING_interpreter_next (is);
}


/**
 * Parser reference to a coin.
 *
 * @param coin_reference of format $LABEL['#' $INDEX]?
 * @param[out] cref where we return a copy of $LABEL
 * @param[out] idx where we set $INDEX
 * @return #GNUNET_SYSERR if $INDEX is present but not numeric
 */
static int
parse_coin_reference (const char *coin_reference,
                      char **cref,
                      unsigned int *idx)
{
  const char *index;

  /* We allow command references of the form "$LABEL#$INDEX" or
     just "$LABEL", which implies the index is 0. Figure out
     which one it is. */
  index = strchr (coin_reference, '#');
  if (NULL == index)
  {
    *idx = 0;
    *cref = GNUNET_strdup (coin_reference);
    return GNUNET_OK;
  }
  *cref = GNUNET_strndup (coin_reference,
                          index - coin_reference);
  if (1 != sscanf (index + 1,
                   "%u",
                   idx))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Numeric index (not `%s') required after `#' in command reference of command in %s:%u\n",
                index,
                __FILE__,
                __LINE__);
    GNUNET_free (*cref);
    *cref = NULL;
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Run the command.
 */
static void
withdraw_run (void *cls,
              const struct TALER_TESTING_Command *cmd,
              struct TALER_TESTING_Interpreter *is)
{
  struct WithdrawState *ws = cls;
  const struct TALER_ReservePrivateKeyP *rp;
  const struct TALER_TESTING_Command *create_reserve;
  const struct TALER_EXCHANGE_DenomPublicKey *dpk;

  (void) cmd;
  create_reserve
    = TALER_TESTING_interpreter_lookup_command (
        is,
        ws->reserve_reference);
  if (NULL == create_reserve)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_priv (create_reserve,
                                            0,
                                            &rp))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (NULL == ws->reuse_coin_key_ref)
  {
    TALER_planchet_setup_random (&ws->ps);
  }
  else
  {
    const struct TALER_CoinSpendPrivateKeyP *coin_priv;
    const struct TALER_TESTING_Command *cref;
    char *cstr;
    unsigned int index;

    GNUNET_assert (GNUNET_OK ==
                   parse_coin_reference (ws->reuse_coin_key_ref,
                                         &cstr,
                                         &index));
    cref = TALER_TESTING_interpreter_lookup_command (is,
                                                     cstr);
    GNUNET_assert (NULL != cref);
    GNUNET_free (cstr);
    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_coin_priv (cref,
                                                      index,
                                                      &coin_priv));
    TALER_planchet_setup_random (&ws->ps);
    ws->ps.coin_priv = *coin_priv;
  }
  ws->is = is;
  if (NULL == ws->pk)
  {
    dpk = TALER_TESTING_find_pk (TALER_EXCHANGE_get_keys (is->exchange),
                                 &ws->amount);
    if (NULL == dpk)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to determine denomination key at %s\n",
                  (NULL != cmd) ? cmd->label : "<retried command>");
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    /* We copy the denomination key, as re-querying /keys
     * would free the old one. */
    ws->pk = TALER_EXCHANGE_copy_denomination_key (dpk);
  }
  else
  {
    ws->amount = ws->pk->value;
  }
  ws->reserve_history.type = TALER_EXCHANGE_RTT_WITHDRAWAL;
  GNUNET_assert (0 <=
                 TALER_amount_add (&ws->reserve_history.amount,
                                   &ws->amount,
                                   &ws->pk->fee_withdraw));
  ws->reserve_history.details.withdraw.fee = ws->pk->fee_withdraw;
  ws->wsh = TALER_EXCHANGE_withdraw (is->exchange,
                                     ws->pk,
                                     rp,
                                     &ws->ps,
                                     &reserve_withdraw_cb,
                                     ws);
  if (NULL == ws->wsh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "withdraw" CMD, and possibly cancel
 * a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
withdraw_cleanup (void *cls,
                  const struct TALER_TESTING_Command *cmd)
{
  struct WithdrawState *ws = cls;

  if (NULL != ws->wsh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %s did not complete\n",
                cmd->label);
    TALER_EXCHANGE_withdraw_cancel (ws->wsh);
    ws->wsh = NULL;
  }
  if (NULL != ws->retry_task)
  {
    GNUNET_SCHEDULER_cancel (ws->retry_task);
    ws->retry_task = NULL;
  }
  if (NULL != ws->sig.rsa_signature)
  {
    GNUNET_CRYPTO_rsa_signature_free (ws->sig.rsa_signature);
    ws->sig.rsa_signature = NULL;
  }
  if (NULL != ws->pk)
  {
    TALER_EXCHANGE_destroy_denomination_key (ws->pk);
    ws->pk = NULL;
  }
  GNUNET_free (ws->exchange_url);
  GNUNET_free (ws);
}


/**
 * Offer internal data to a "withdraw" CMD state to other
 * commands.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
withdraw_traits (void *cls,
                 const void **ret,
                 const char *trait,
                 unsigned int index)
{
  struct WithdrawState *ws = cls;
  const struct TALER_TESTING_Command *reserve_cmd;
  const struct TALER_ReservePrivateKeyP *reserve_priv;
  const struct TALER_ReservePublicKeyP *reserve_pub;

  /* We offer the reserve key where these coins were withdrawn
   * from. */
  reserve_cmd = TALER_TESTING_interpreter_lookup_command (ws->is,
                                                          ws->reserve_reference);

  if (NULL == reserve_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ws->is);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_priv (reserve_cmd,
                                            0,
                                            &reserve_priv))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ws->is);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_pub (reserve_cmd,
                                           0,
                                           &reserve_pub))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (ws->is);
    return GNUNET_SYSERR;
  }
  if (NULL == ws->exchange_url)
    ws->exchange_url
      = GNUNET_strdup (TALER_EXCHANGE_get_base_url (ws->is->exchange));
  {
    struct TALER_TESTING_Trait traits[] = {
      /* history entry MUST be first due to response code logic below! */
      TALER_TESTING_make_trait_reserve_history (0,
                                                &ws->reserve_history),
      TALER_TESTING_make_trait_coin_priv (0 /* only one coin */,
                                          &ws->ps.coin_priv),
      TALER_TESTING_make_trait_blinding_key (0 /* only one coin */,
                                             &ws->ps.blinding_key),
      TALER_TESTING_make_trait_denom_pub (0 /* only one coin */,
                                          ws->pk),
      TALER_TESTING_make_trait_denom_sig (0 /* only one coin */,
                                          &ws->sig),
      TALER_TESTING_make_trait_reserve_priv (0,
                                             reserve_priv),
      TALER_TESTING_make_trait_reserve_pub (0,
                                            reserve_pub),
      TALER_TESTING_make_trait_amount_obj (0,
                                           &ws->amount),
      TALER_TESTING_make_trait_url (TALER_TESTING_UT_EXCHANGE_BASE_URL,
                                    ws->exchange_url),
      TALER_TESTING_trait_end ()
    };

    return TALER_TESTING_get_trait ((ws->expected_response_code == MHD_HTTP_OK)
                                    ? &traits[0] /* we have reserve history */
                                    : &traits[1],/* skip reserve history */
                                    ret,
                                    trait,
                                    index);
  }
}


/**
 * Create a withdraw command, letting the caller specify
 * the desired amount as string.
 *
 * @param label command label.
 * @param reserve_reference command providing us with a reserve to withdraw from
 * @param amount how much we withdraw.
 * @param expected_response_code which HTTP response code
 *        we expect from the exchange.
 * @return the withdraw command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_amount (const char *label,
                                   const char *reserve_reference,
                                   const char *amount,
                                   unsigned int expected_response_code)
{
  struct WithdrawState *ws;

  ws = GNUNET_new (struct WithdrawState);
  ws->reserve_reference = reserve_reference;
  if (GNUNET_OK !=
      TALER_string_to_amount (amount,
                              &ws->amount))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse amount `%s' at %s\n",
                amount,
                label);
    GNUNET_assert (0);
  }
  ws->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ws,
      .label = label,
      .run = &withdraw_run,
      .cleanup = &withdraw_cleanup,
      .traits = &withdraw_traits
    };

    return cmd;
  }
}


/**
 * Create a withdraw command, letting the caller specify
 * the desired amount as string and also re-using an existing
 * coin private key in the process (violating the specification,
 * which will result in an error when spending the coin!).
 *
 * @param label command label.
 * @param reserve_reference command providing us with a reserve to withdraw from
 * @param amount how much we withdraw.
 * @param coin_ref reference to (withdraw/reveal) command of a coin
 *        from which we should re-use the private key
 * @param expected_response_code which HTTP response code
 *        we expect from the exchange.
 * @return the withdraw command to be executed by the interpreter.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_amount_reuse_key (
  const char *label,
  const char *reserve_reference,
  const char *amount,
  const char *coin_ref,
  unsigned int expected_response_code)
{
  struct TALER_TESTING_Command cmd;

  cmd = TALER_TESTING_cmd_withdraw_amount (label,
                                           reserve_reference,
                                           amount,
                                           expected_response_code);
  {
    struct WithdrawState *ws = cmd.cls;

    ws->reuse_coin_key_ref = coin_ref;
  }
  return cmd;
}


/**
 * Create withdraw command, letting the caller specify the
 * amount by a denomination key.
 *
 * @param label command label.
 * @param reserve_reference reference to the reserve to withdraw
 *        from; will provide reserve priv to sign the request.
 * @param dk denomination public key.
 * @param expected_response_code expected HTTP response code.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_denomination (
  const char *label,
  const char *reserve_reference,
  const struct TALER_EXCHANGE_DenomPublicKey *dk,
  unsigned int expected_response_code)
{
  struct WithdrawState *ws;

  if (NULL == dk)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Denomination key not specified at %s\n",
                label);
    GNUNET_assert (0);
  }
  ws = GNUNET_new (struct WithdrawState);
  ws->reserve_reference = reserve_reference;
  ws->pk = TALER_EXCHANGE_copy_denomination_key (dk);
  ws->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ws,
      .label = label,
      .run = &withdraw_run,
      .cleanup = &withdraw_cleanup,
      .traits = &withdraw_traits
    };

    return cmd;
  }
}


/**
 * Modify a withdraw command to enable retries when the
 * reserve is not yet full or we get other transient
 * errors from the exchange.
 *
 * @param cmd a withdraw command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_with_retry (struct TALER_TESTING_Command cmd)
{
  struct WithdrawState *ws;

  GNUNET_assert (&withdraw_run == cmd.run);
  ws = cmd.cls;
  ws->do_retry = NUM_RETRIES;
  return cmd;
}


/* end of testing_api_cmd_withdraw.c */
