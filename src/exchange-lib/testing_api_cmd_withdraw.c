/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file exchange-lib/testing_api_cmd_withdraw.c
 * @brief main interpreter loop for testcases
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_signatures.h"


struct WithdrawState
{

  /**
   * Which reserve should we withdraw from?
   */
  const char *reserve_reference;

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
  const struct TALER_EXCHANGE_DenomPublicKey *pk;

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
   * Withdraw handle (while operation is running).
   */
  struct TALER_EXCHANGE_ReserveWithdrawHandle *wsh;

};


  /**
   * Runs the command.  Note that upon return, the interpreter
   * will not automatically run the next command, as the command
   * may continue asynchronously in other scheduler tasks.  Thus,
   * the command must ensure to eventually call
   * #TALER_TESTING_interpreter_next() or
   * #TALER_TESTING_interpreter_fail().
   *
   * @param i interpreter state
   */
static void
withdraw_run (void *cls,
              struct TALER_TESTING_Interpreter *i)
{
  struct WithdrawState *ws = cls;
  struct TALER_ReservePrivateKeyP rp;
  struct TALER_TESTING_Command *create_reserve;

  create_reserve
    = TALER_TESTING_interpreter_lookup_command (i,
                                                ws->reserve_reference);
  if (NULL == create_reserve)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (i);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_priv (create_reserve,
                                            NULL,
                                            &rp))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (i);
    return;
  }
  // ... trigger withdraw
  // ... eventually: TALER_TESTING_interpreter_next (i);
}


/**
 * Clean up after the command.  Run during forced termination
 * (CTRL-C) or test failure or test success.
 *
 * @param cls closure
 */
static void
withdraw_cleanup (void *cls)
{
  struct WithdrawState *ws = cls;

}


/**
 * Extract information from a command that is useful for other
 * commands.
 *
 * @param cls closure
 * @param ret[out] result (could be anything)
 * @param trait name of the trait
 * @param selector more detailed information about which object
 *                 to return in case there were multiple generated
 *                 by the command
 * @return #GNUNET_OK on success
 */
static int
withdraw_traits (void *cls,
                 void **ret,
                 const char *trait,
                 const char *selector)
{
  struct WithdrawState *ws = cls;
  struct TALER_INTERPRETER_Trait traits[] = {
    TALER_TESTING_make_trait_coin_priv (NULL /* only one coin */,
                                        &ws->ps.coin_priv),
#if 0
    TALER_TESTING_make_trait_coin_blinding_key (NULL /* only one coin */,
                                                &ws->ps.blinding_key),
    TALER_TESTING_make_trait_coin_denomination_key (NULL /* only one coin */,
                                                    ws->pk),
    TALER_TESTING_make_trait_coin_denomination_sig (NULL /* only one coin */,
                                                    &ws->sig),
#endif
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  selector);
}


/**
 * Create withdraw command.
 *
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_amount (const char *label,
                                   const char *reserve_reference,
                                   const char *amount)
{
  struct TALER_TESTING_Command cmd;
  struct WithdrawState *ws;

  ws = GNUNET_new (struct WithdrawState);
  ws->reserve_reference = reserve_reference;
  // convert amount -> ws->amount;
  cmd.cls = ws;
  cmd.label = label;
  cmd.run = &withdraw_run;
  cmd.cleanup = &withdraw_cleanup;
  cmd.traits = &withdraw_traits;
  return cmd;
}





/* end of testing_api_cmd_withdraw.c */
