/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file testing/testing_api_cmd_reserve_open.c
 * @brief Implement the /reserve/$RID/open test command.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * Information we track per coin used to pay for opening the
 * reserve.
 */
struct CoinDetail
{
  /**
   * Name of the command and index of the coin to use.
   */
  const char *name;

  /**
   * Amount to charge to this coin.
   */
  struct TALER_Amount amount;
};


/**
 * State for a "open" CMD.
 */
struct OpenState
{
  /**
   * Label to the command which created the reserve to check,
   * needed to resort the reserve key.
   */
  const char *reserve_reference;

  /**
   * Requested expiration time.
   */
  struct GNUNET_TIME_Relative req_expiration_time;

  /**
   * Requested minimum number of purses.
   */
  uint32_t min_purses;

  /**
   * Amount to pay for the opening from the reserve balance.
   */
  struct TALER_Amount reserve_pay;

  /**
   * Handle to the "reserve open" operation.
   */
  struct TALER_EXCHANGE_ReservesOpenHandle *rsh;

  /**
   * Expected reserve balance.
   */
  const char *expected_balance;

  /**
   * Length of the @e cd array.
   */
  unsigned int cpl;

  /**
   * Coin details, array of length @e cpl.
   */
  struct CoinDetail *cd;

  /**
   * Private key of the reserve being analyzed.
   */
  const struct TALER_ReservePrivateKeyP *reserve_priv;

  /**
   * Public key of the reserve being analyzed.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;
};


/**
 * Check that the reserve balance and HTTP response code are
 * both acceptable.
 *
 * @param cls closure.
 * @param rs HTTP response details
 */
static void
reserve_open_cb (void *cls,
                 const struct TALER_EXCHANGE_ReserveOpenResult *rs)
{
  struct OpenState *ss = cls;
  struct TALER_TESTING_Interpreter *is = ss->is;

  ss->rsh = NULL;
  if (ss->expected_response_code != rs->hr.http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected HTTP response code: %d in %s:%u\n",
                rs->hr.http_status,
                __FILE__,
                __LINE__);
    json_dumpf (rs->hr.reply,
                stderr,
                JSON_INDENT (2));
    TALER_TESTING_interpreter_fail (ss->is);
    return;
  }
  if (MHD_HTTP_OK != rs->hr.http_status)
  {
    TALER_TESTING_interpreter_next (is);
    return;
  }
  TALER_TESTING_interpreter_next (is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command being executed.
 * @param is the interpreter state.
 */
static void
open_run (void *cls,
          const struct TALER_TESTING_Command *cmd,
          struct TALER_TESTING_Interpreter *is)
{
  struct OpenState *ss = cls;
  const struct TALER_TESTING_Command *create_reserve;
  struct TALER_EXCHANGE_PurseDeposit cp[GNUNET_NZL (ss->cpl)];

  ss->is = is;
  create_reserve
    = TALER_TESTING_interpreter_lookup_command (is,
                                                ss->reserve_reference);

  if (NULL == create_reserve)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_priv (create_reserve,
                                            &ss->reserve_priv))
  {
    GNUNET_break (0);
    TALER_LOG_ERROR ("Failed to find reserve_priv for open query\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_CRYPTO_eddsa_key_get_public (&ss->reserve_priv->eddsa_priv,
                                      &ss->reserve_pub.eddsa_pub);
  for (unsigned int i = 0; i<ss->cpl; i++)
  {
    struct TALER_EXCHANGE_PurseDeposit *cpi = &cp[i];
    const struct TALER_TESTING_Command *cmdi;
    const struct TALER_AgeCommitmentProof *age_commitment_proof;
    const struct TALER_CoinSpendPrivateKeyP *coin_priv;
    const struct TALER_DenominationSignature *denom_sig;
    const struct TALER_EXCHANGE_DenomPublicKey *denom_pub;
    char *cref;
    unsigned int cidx;

    if (GNUNET_OK !=
        TALER_TESTING_parse_coin_reference (ss->cd[i].name,
                                            &cref,
                                            &cidx))
    {
      GNUNET_break (0);
      TALER_LOG_ERROR ("Failed to parse coin reference `%s'\n",
                       ss->cd[i].name);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    cmdi = TALER_TESTING_interpreter_lookup_command (is,
                                                     cref);
    GNUNET_free (cref);
    if (NULL == cmdi)
    {
      GNUNET_break (0);
      TALER_LOG_ERROR ("Command `%s' not found\n",
                       ss->cd[i].name);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if ( (GNUNET_OK !=
          TALER_TESTING_get_trait_age_commitment_proof (cmdi,
                                                        cidx,
                                                        &age_commitment_proof))
         ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_coin_priv (cmdi,
                                             cidx,
                                             &coin_priv)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_denom_sig (cmdi,
                                             cidx,
                                             &denom_sig)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_denom_pub (cmdi,
                                             cidx,
                                             &denom_pub)) )
    {
      GNUNET_break (0);
      TALER_LOG_ERROR ("Coin trait not found in `%s'\n",
                       ss->cd[i].name);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    cpi->age_commitment_proof = age_commitment_proof;
    cpi->coin_priv = *coin_priv;
    cpi->denom_sig = *denom_sig;
    cpi->amount = ss->cd[i].amount;
    cpi->h_denom_pub = denom_pub->h_key;
  }
  ss->rsh = TALER_EXCHANGE_reserves_open (
    is->exchange,
    ss->reserve_priv,
    &ss->reserve_pay,
    ss->cpl,
    cp,
    GNUNET_TIME_relative_to_timestamp (ss->req_expiration_time),
    ss->min_purses,
    &reserve_open_cb,
    ss);
}


/**
 * Cleanup the state from a "reserve open" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
open_cleanup (void *cls,
              const struct TALER_TESTING_Command *cmd)
{
  struct OpenState *ss = cls;

  if (NULL != ss->rsh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ss->is->ip,
                cmd->label);
    TALER_EXCHANGE_reserves_open_cancel (ss->rsh);
    ss->rsh = NULL;
  }
  GNUNET_free (ss);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_open (const char *label,
                                const char *reserve_reference,
                                const char *reserve_pay,
                                struct GNUNET_TIME_Relative expiration_time,
                                uint32_t min_purses,
                                unsigned int expected_response_code,
                                ...)
{
  struct OpenState *ss;
  va_list ap;
  const char *name;
  unsigned int i;

  GNUNET_assert (NULL != reserve_reference);
  ss = GNUNET_new (struct OpenState);
  ss->reserve_reference = reserve_reference;
  ss->req_expiration_time = expiration_time;
  ss->min_purses = min_purses;
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (reserve_pay,
                                         &ss->reserve_pay));
  ss->expected_response_code = expected_response_code;
  va_start (ap,
            expected_response_code);
  while (NULL != (name = va_arg (ap, const char *)))
    ss->cpl++;
  va_end (ap);
  GNUNET_assert (0 == (ss->cpl % 2));
  ss->cpl /= 2; /* name and amount per coin */
  ss->cd = GNUNET_new_array (ss->cpl,
                             struct CoinDetail);
  i = 0;
  va_start (ap,
            expected_response_code);
  while (NULL != (name = va_arg (ap, const char *)))
  {
    struct CoinDetail *cd = &ss->cd[i];
    cd->name = name;
    GNUNET_assert (GNUNET_OK ==
                   TALER_string_to_amount (va_arg (ap,
                                                   const char *),
                                           &cd->amount));
    i++;
  }
  va_end (ap);
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ss,
      .label = label,
      .run = &open_run,
      .cleanup = &open_cleanup
    };

    return cmd;
  }
}
