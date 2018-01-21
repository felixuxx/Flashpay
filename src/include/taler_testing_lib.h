/*
  This file is part of TALER
  (C) 2018 Taler Systems SA

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
 * @file include/taler_testing_lib.h
 * @brief API for writing an interpreter to test Taler components
 * @author Christian Grothoff <christian@grothoff.org>
 * @author Marcello Stanisci
 */
#ifndef TALER_TESTING_LIB_H
#define TALER_TESTING_LIB_H

#include "taler_util.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include <microhttpd.h>

/* ******************* Generic interpreter logic ****************** */

/**
 * Global state of the interpreter, used by a command
 * to access information about other commands.
 */
struct TALER_TESTING_Interpreter;


/**
 * A command to be run by the interpreter.
 */
struct TALER_TESTING_Command
{

  /**
   * Closure for all commands with command-specific context
   * information.
   */
  void *cls;

  /**
   * Label for the command.
   */
  const char *label;

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
  void
  (*run)(void *cls,
         const struct TALER_TESTING_Command *cmd,
         struct TALER_TESTING_Interpreter *i);


  /**
   * Clean up after the command.  Run during forced termination
   * (CTRL-C) or test failure or test success.
   *
   * @param cls closure
   */
  void
  (*cleanup)(void *cls,
             const struct TALER_TESTING_Command *cmd);

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
  int
  (*traits)(void *cls,
            void **ret,
            const char *trait,
            const char *selector);

};


/**
 * Lookup command by label.
 */
const struct TALER_TESTING_Command *
TALER_TESTING_interpreter_lookup_command (struct TALER_TESTING_Interpreter *i,
                                          const char *label);


/**
 * Obtain main execution context for the main loop.
 */
struct GNUNET_CURL_Context *
TALER_TESTING_interpreter_get_context (struct TALER_TESTING_Interpreter *is);


/**
 * Current command is done, run the next one.
 */
void
TALER_TESTING_interpreter_next (struct TALER_TESTING_Interpreter *is);

/**
 * Current command failed, clean up and fail the test case.
 */
void
TALER_TESTING_interpreter_fail (struct TALER_TESTING_Interpreter *is);

/**
 * Create command array terminator.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_end (void);


void
TALER_TESTING_run (struct TALER_TESTING_Interpreter *is,
                   struct TALER_TESTING_Command *commands);


typedef void
(*TALER_TESTING_Main)(void *cls,
                      struct TALER_TESTING_Interpreter *is);


/**
 * Initialize scheduler loop and curl context for the testcase.
 */
int
TALER_TESTING_setup (TALER_TESTING_Main main_cb,
                     void *main_cb_cls);




/* ****************** Specific interpreter commands **************** */

/**
 * Perform a wire transfer (formerly Admin-add-incoming)
 *
 * @return NULL on failure
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer (const char *label,
                                     const char *amount,
                                     uint64_t debit_account_no,
                                     uint64_t credit_account_no,
                                     const char *auth_username,
                                     const char *auth_password);


/**
 * Create withdraw command.
 *
 * @return NULL on failure
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_amount (const char *label,
                                   struct TALER_EXCHANGE_Handle *exchange,
                                   const char *reserve_reference,
                                   const char *amount,
                                   unsigned int expected_response_code);




/* ********************** Generic trait logic for implementing traits ******************* */

/**
 * A trait.
 */
struct TALER_TESTING_Trait
{
  const char *selector;

  const char *trait_name;

  const void *ptr;
};



struct TALER_TESTING_Trait
TALER_TESTING_trait_end (void);


int
TALER_TESTING_get_trait (const struct TALER_TESTING_Trait *traits,
                         void **ret,
                         const char *trait,
                         const char *selector);


/* ****************** Specific traits supported by this component *************** */

struct TALER_TESTING_Trait
TALER_TESTING_make_trait_reserve_priv (const char *selector,
                                       const struct TALER_ReservePrivateKeyP *reserve_priv);


/**
 * Obtain a reserve private key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on offer
 * @param reserve_priv[out] set to the private key of the reserve
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_reserve_priv (const struct TALER_TESTING_Command *cmd,
                                      const char *selector,
                                      struct TALER_ReservePrivateKeyP **reserve_priv);


/**
 * @param selector
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_coin_priv (const char *selector,
                                    const struct TALER_CoinSpendPrivateKeyP *coin_priv);


/**
 * Obtain a coin private key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on offer
 * @param coin_priv[out] set to the private key of the coin
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_coin_priv (const struct TALER_TESTING_Command *cmd,
                                   const char *selector,
                                   struct TALER_CoinSpendPrivateKeyP **coin_priv);



/**
 * @param selector
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_blinding_key (const char *selector,
                                       const struct TALER_DenominationBlindingKeyP *blinding_key);


/**
 * Obtain a coin's blinding key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on offer
 * @param blinding_key[out] set to the blinding key of the coin
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_blinding_key (const struct TALER_TESTING_Command *cmd,
                                      const char *selector,
                                      struct TALER_DenominationBlindingKeyP **blinding_key);




/**
 * @param selector
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_denom_pub (const char *selector,
                                    const struct TALER_EXCHANGE_DenomPublicKey *dpk);


/**
 * Obtain a coin private key from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on offer
 * @param dpk[out] set to a denomination key of the coin
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_denom_pub (const struct TALER_TESTING_Command *cmd,
                                   const char *selector,
                                   struct TALER_EXCHANGE_DenomPublicKey **dpk);


/**
 * Obtain a coin denomination signature from a @a cmd.
 *
 * @param cmd command to extract trait from
 * @param selector which coin to pick if @a cmd has multiple on offer
 * @param sig[out] set to a denomination signature over the coin
 * @return #GNUNET_OK on success
 */
int
TALER_TESTING_get_trait_denom_sig (const struct TALER_TESTING_Command *cmd,
                                   const char *selector,
                                   struct TALER_DenominationSignature **dpk);


/**
 * @param selector
 */
struct TALER_TESTING_Trait
TALER_TESTING_make_trait_denom_sig (const char *selector,
                                    const struct TALER_DenominationSignature *sig);











#endif
