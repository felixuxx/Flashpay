/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

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
 * @file exchange-lib/testing_api_cmd_bank_check.c
 * @brief command to check if a particular wire transfer took
 *        place.
 * @author Marcello Stanisci
 */

#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_testing_lib.h"
#include "taler_fakebank_lib.h"

struct BankCheckState
{

  /**
   * Exchange base URL (Fixme: why?)
   */
  const char *exchange_base_url;

  /**
   * Expected transferred amount.
   */
  const char *amount;

  /**
   * Expected account number that gave money
   */
  unsigned int debit_account;
 
  /**
   * Expected account number that received money
   */
  unsigned int credit_account;

  /**
   * Wire transfer subject (set by fakebank-lib).
   */
  char *subject;

  /**
   * Binary form of the transfer subject.  Some commands expect
   * it - via appropriate traits - to be in binary form.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;
};

/**
 * Run the command.
 *
 * @param cls closure, typically a #struct WireState.
 * @param cmd the command to execute, a /wire one.
 * @param is the interpreter state.
 */
void
check_bank_transfer_run (void *cls,
                         const struct TALER_TESTING_Command *cmd,
                         struct TALER_TESTING_Interpreter *is)
{
  struct BankCheckState *bcs = cls;
  struct TALER_Amount amount;


  if (GNUNET_OK !=
      TALER_string_to_amount (bcs->amount,
                              &amount))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse amount `%s' at %u\n",
                bcs->amount,
                is->ip);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_FAKEBANK_check (is->fakebank,
                            &amount,
                            bcs->debit_account,
                            bcs->credit_account,
                            bcs->exchange_base_url,
                            &bcs->subject))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_interpreter_next (is);
}

/**
 * Cleanup the state.
 *
 * @param cls closure, typically a #struct WireState.
 * @param cmd the command which is being cleaned up.
 */
void
check_bank_transfer_cleanup
  (void *cls,
   const struct TALER_TESTING_Command *cmd)
{
  struct BankCheckState *bcs = cls;
 
  GNUNET_free_non_null (bcs->subject);
  GNUNET_free (bcs);
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
check_bank_transfer_traits (void *cls,
                            void **ret,
                            const char *trait,
                            unsigned int index)
{


  struct BankCheckState *bcs = cls; 

  GNUNET_assert (GNUNET_OK == 
    GNUNET_STRINGS_string_to_data
      (bcs->subject,
       strlen (bcs->subject),
       &bcs->wtid,
       sizeof (struct TALER_WireTransferIdentifierRawP)));

  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_transfer_subject (0, bcs->subject),
    TALER_TESTING_make_trait_wtid (0, &bcs->wtid),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}                           



/**
 * Command to check whether a particular wire transfer has been
 * made or not.
 *
 * @param label the command label
 * @param exchange_base_url base url of the exchange (Fixme: why?)
 * @param amount the amount expected to be transferred
 * @param debit_account the account that gave money
 * @param credit_account the account that received money
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_transfer
  (const char *label,
   const char *exchange_base_url,
   const char *amount,
   unsigned int debit_account,
   unsigned int credit_account)
{
  struct BankCheckState *bcs;
  struct TALER_TESTING_Command cmd;

  bcs = GNUNET_new (struct BankCheckState);
  bcs->exchange_base_url = exchange_base_url;
  bcs->amount = amount;
  bcs->debit_account = debit_account;
  bcs->credit_account = credit_account;

  cmd.label = label;
  cmd.cls = bcs;
  cmd.run = &check_bank_transfer_run;
  cmd.cleanup = &check_bank_transfer_cleanup;
  // traits?
  cmd.traits = &check_bank_transfer_traits;

  return cmd;
}

/**
 * Cleanup the state.
 *
 * @param cls closure, typically a #struct WireState.
 * @param cmd the command which is being cleaned up.
 */
void
check_bank_empty_cleanup
  (void *cls,
   const struct TALER_TESTING_Command *cmd)
{
  return;
}

/**
 * Run the command.
 *
 * @param cls closure, typically a #struct WireState.
 * @param cmd the command to execute, a /wire one.
 * @param is the interpreter state.
 */
void
check_bank_empty_run (void *cls,
                      const struct TALER_TESTING_Command *cmd,
                      struct TALER_TESTING_Interpreter *is)
{

  if (GNUNET_OK != TALER_FAKEBANK_check_empty (is->fakebank))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;  
  }
  TALER_TESTING_interpreter_next (is);
}

/**
 * Check bank's balance is zero.
 *
 * @param credit_account the account that received money
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_empty (const char *label)
{
  struct TALER_TESTING_Command cmd;

  cmd.label = label;
  cmd.run = &check_bank_empty_run;
  cmd.cleanup = &check_bank_empty_cleanup;
  
  return cmd;
}
