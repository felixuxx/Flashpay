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


/**
 * State for a "bank check" CMD.
 */
struct BankCheckState
{

  /**
   * Base URL of the exchange supposed to be
   * involved in the bank transaction.
   */
  const char *exchange_base_url;

  /**
   * Expected transferred amount.
   */
  const char *amount;

  /**
   * Expected debit bank account.
   */
  uint64_t debit_account;
 
  /**
   * Expected credit bank account.
   */
  uint64_t credit_account;

  /**
   * Wire transfer subject (set by fakebank-lib).
   */
  char *subject;

  /**
   * Binary form of the wire transfer subject.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Reference to a CMD that provides all the data
   * needed to issue the bank check.  If NULL, that data
   * must exist here in the state.
   */
  const char *deposit_reference;
};

/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
void
check_bank_transfer_run (void *cls,
                         const struct TALER_TESTING_Command *cmd,
                         struct TALER_TESTING_Interpreter *is)
{
  struct BankCheckState *bcs = cls;

  struct TALER_Amount amount;
  const uint64_t *debit_account;
  const uint64_t *credit_account;
  const char *exchange_base_url;


  if (NULL == bcs->deposit_reference)
  {
    TALER_LOG_INFO ("Deposit reference NOT given\n");
    debit_account = &bcs->debit_account;
    credit_account = &bcs->credit_account;
    exchange_base_url = bcs->exchange_base_url;

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
  }

  if (NULL != bcs->deposit_reference)
  {
    const struct TALER_TESTING_Command *deposit_cmd;
    const struct TALER_Amount *amount_ptr;

    TALER_LOG_INFO ("`%s' uses reference (%s/%p)\n",
                    TALER_TESTING_interpreter_get_current_label
                      (is),
                    bcs->deposit_reference,
                    bcs->deposit_reference);
    deposit_cmd = TALER_TESTING_interpreter_lookup_command
      (is, bcs->deposit_reference);

    if (NULL == deposit_cmd)
      TALER_TESTING_FAIL (is);

    GNUNET_assert
      (GNUNET_OK == TALER_TESTING_get_trait_amount_obj
        (deposit_cmd, 0, &amount_ptr));
    amount = *amount_ptr;

    GNUNET_assert
      (GNUNET_OK == TALER_TESTING_GET_TRAIT_DEBIT_ACCOUNT
        (deposit_cmd, &debit_account));

    GNUNET_assert
      (GNUNET_OK == TALER_TESTING_GET_TRAIT_CREDIT_ACCOUNT
        (deposit_cmd, &credit_account));

    GNUNET_assert
      (GNUNET_OK == TALER_TESTING_get_trait_url
        (deposit_cmd, 0, &exchange_base_url)); // check 0 works!

  }

  if (GNUNET_OK !=
      TALER_FAKEBANK_check (is->fakebank,
                            &amount,
                            *debit_account,
                            *credit_account,
                            exchange_base_url,
                            &bcs->subject))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  TALER_TESTING_interpreter_next (is);
}

/**
 * Free the state of a "bank check" CMD.
 *
 * @param cls closure.
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
 * Offer internal data from a "bank check" CMD state.
 *
 * @param cls closure.
 * @param ret[out] result (could be anything).
 * @param trait name of the trait.
 * @param selector more detailed information about which object
 *                 to return in case there were multiple generated
 *                 by the command.
 *
 * @return #GNUNET_OK on success.
 */
static int
check_bank_transfer_traits (void *cls,
                            void **ret,
                            const char *trait,
                            unsigned int index)
{
  struct BankCheckState *bcs = cls; 
  struct TALER_WireTransferIdentifierRawP *wtid_ptr;

  if (GNUNET_OK != GNUNET_STRINGS_string_to_data
      (bcs->subject,
       strlen (bcs->subject),
       &bcs->wtid,
       sizeof (struct TALER_WireTransferIdentifierRawP)))
    wtid_ptr = NULL;
  else
    wtid_ptr = &bcs->wtid;

  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_transfer_subject (0, bcs->subject),
    TALER_TESTING_make_trait_wtid (0, wtid_ptr),
    TALER_TESTING_make_trait_url (0, bcs->exchange_base_url),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}                           



/**
 * Make a "bank check" CMD.  It checks whether a
 * particular wire transfer has been made or not.
 *
 * @param label the command label.
 * @param exchange_base_url base url of the exchange involved in
 *        the wire transfer.
 * @param amount the amount expected to be transferred.
 * @param debit_account the account that gave money.
 * @param credit_account the account that received money.
 *
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_transfer
  (const char *label,
   const char *exchange_base_url,
   const char *amount,
   uint64_t debit_account,
   uint64_t credit_account)
{
  struct BankCheckState *bcs;
  struct TALER_TESTING_Command cmd;

  bcs = GNUNET_new (struct BankCheckState);
  bcs->exchange_base_url = exchange_base_url;
  bcs->amount = amount;
  bcs->debit_account = debit_account;
  bcs->credit_account = credit_account;

  bcs->deposit_reference = NULL;

  cmd.label = label;
  cmd.cls = bcs;
  cmd.run = &check_bank_transfer_run;
  cmd.cleanup = &check_bank_transfer_cleanup;
  cmd.traits = &check_bank_transfer_traits;

  return cmd;
}

/**
 * Cleanup the state, only defined to respect the API.
 *
 * @param cls closure.
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
 * @param cls closure.
 * @param cmd the command to execute.
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
 * Some commands (notably "bank history") could randomly
 * look for traits; this way makes sure we don't segfault.
 */
static int
check_bank_empty_traits (void *cls,
                         void **ret,
                         const char *trait,
                         unsigned int index)
{
  return GNUNET_SYSERR;
}                         

/**
 * Checks wheter all the wire transfers got "checked"
 * by the "bank check" CMD.
 *
 * @param label command label.
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
  cmd.traits = &check_bank_empty_traits;
  
  return cmd;
}


/**
 * Define a "bank check" CMD that takes the input
 * data from another CMD that offers it.
 *
 * @param label command label.
 * @param deposit_reference reference to a CMD that is
 *        able to provide the "check bank transfer" operation
 *        input data.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_transfer_with_ref
  (const char *label,
   const char *deposit_reference)
{

  struct BankCheckState *bcs;
  struct TALER_TESTING_Command cmd;

  bcs = GNUNET_new (struct BankCheckState);
  bcs->deposit_reference = deposit_reference;

  cmd.label = label;
  cmd.cls = bcs;
  cmd.run = &check_bank_transfer_run;
  cmd.cleanup = &check_bank_transfer_cleanup;
  cmd.traits = &check_bank_transfer_traits;

  return cmd;
}
