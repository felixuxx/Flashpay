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
 * @file testing/testing_api_cmd_reserve_close.c
 * @brief Implement the /reserve/$RID/close test command.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "close" CMD.
 */
struct CloseState
{
  /**
   * Label to the command which created the reserve to check,
   * needed to resort the reserve key.
   */
  const char *reserve_reference;

  /**
   * Handle to the "reserve close" operation.
   */
  struct TALER_EXCHANGE_ReservesCloseHandle *rsh;

  /**
   * payto://-URI where to wire the funds.
   */
  const char *target_account;

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

  /**
   * Set to the KYC requirement payto hash *if* the exchange replied with a
   * request for KYC.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Set to the KYC requirement row *if* the exchange replied with
   * a request for KYC.
   */
  uint64_t requirement_row;
};


/**
 * Check that the reserve balance and HTTP response code are
 * both acceptable.
 *
 * @param cls closure.
 * @param rs HTTP response details
 */
static void
reserve_close_cb (void *cls,
                  const struct TALER_EXCHANGE_ReserveCloseResult *rs)
{
  struct CloseState *ss = cls;
  struct TALER_TESTING_Interpreter *is = ss->is;

  ss->rsh = NULL;
  if (ss->expected_response_code != rs->hr.http_status)
  {
    TALER_TESTING_unexpected_status (ss->is,
                                     rs->hr.http_status,
                                     ss->expected_response_code);
    json_dumpf (rs->hr.reply,
                stderr,
                JSON_INDENT (2));
    return;
  }
  switch (rs->hr.http_status)
  {
  case MHD_HTTP_OK:
    break;
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
    /* nothing to check */
    ss->requirement_row
      = rs->details.unavailable_for_legal_reasons.requirement_row;
    ss->h_payto
      = rs->details.unavailable_for_legal_reasons.h_payto;
    break;
  default:
    break;
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
close_run (void *cls,
           const struct TALER_TESTING_Command *cmd,
           struct TALER_TESTING_Interpreter *is)
{
  struct CloseState *ss = cls;
  const struct TALER_TESTING_Command *create_reserve;

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
    TALER_LOG_ERROR ("Failed to find reserve_priv for close query\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_CRYPTO_eddsa_key_get_public (&ss->reserve_priv->eddsa_priv,
                                      &ss->reserve_pub.eddsa_pub);
  ss->rsh = TALER_EXCHANGE_reserves_close (
    TALER_TESTING_interpreter_get_context (is),
    TALER_TESTING_get_exchange_url (is),
    ss->reserve_priv,
    ss->target_account,
    &reserve_close_cb,
    ss);
}


/**
 * Cleanup the state from a "reserve close" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
close_cleanup (void *cls,
               const struct TALER_TESTING_Command *cmd)
{
  struct CloseState *ss = cls;

  if (NULL != ss->rsh)
  {
    TALER_TESTING_command_incomplete (ss->is,
                                      cmd->label);
    TALER_EXCHANGE_reserves_close_cancel (ss->rsh);
    ss->rsh = NULL;
  }
  GNUNET_free (ss);
}


/**
 * Offer internal data to a "close" CMD state to other
 * commands.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
close_traits (void *cls,
              const void **ret,
              const char *trait,
              unsigned int index)
{
  struct CloseState *cs = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_legi_requirement_row (
      &cs->requirement_row),
    TALER_TESTING_make_trait_h_payto (
      &cs->h_payto),
    TALER_TESTING_trait_end ()
  };

  if (cs->expected_response_code != MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS)
    return GNUNET_NO;
  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_close (const char *label,
                                 const char *reserve_reference,
                                 const char *target_account,
                                 unsigned int expected_response_code)
{
  struct CloseState *ss;

  GNUNET_assert (NULL != reserve_reference);
  ss = GNUNET_new (struct CloseState);
  ss->reserve_reference = reserve_reference;
  ss->target_account = target_account;
  ss->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ss,
      .label = label,
      .run = &close_run,
      .cleanup = &close_cleanup,
      .traits = &close_traits
    };

    return cmd;
  }
}
