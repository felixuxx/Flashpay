/*
  This file is part of TALER
  Copyright (C) 2018-2024 Taler Systems SA

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
 * @file testing/testing_api_cmd_bank_check.c
 * @brief command to check if a particular wire transfer took
 *        place.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
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
  struct TALER_FullPayto debit_payto;

  /**
   * Expected credit bank account.
   */
  struct TALER_FullPayto credit_payto;

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
static void
check_bank_transfer_run (void *cls,
                         const struct TALER_TESTING_Command *cmd,
                         struct TALER_TESTING_Interpreter *is)
{
  struct BankCheckState *bcs = cls;
  struct TALER_Amount amount;
  char *debit_account;
  char *credit_account;
  const char *exchange_base_url;
  const struct TALER_FullPayto *debit_payto;
  const struct TALER_FullPayto *credit_payto;
  struct TALER_FAKEBANK_Handle *fakebank;

  (void) cmd;
  {
    const struct TALER_TESTING_Command *fakebank_cmd;

    fakebank_cmd
      = TALER_TESTING_interpreter_get_command (is,
                                               "fakebank");
    if (NULL == fakebank_cmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_fakebank (fakebank_cmd,
                                          &fakebank))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
  }
  if (NULL == bcs->deposit_reference)
  {
    TALER_LOG_INFO ("Deposit reference NOT given\n");
    debit_payto = &bcs->debit_payto;
    credit_payto = &bcs->credit_payto;
    exchange_base_url = bcs->exchange_base_url;

    if (GNUNET_OK !=
        TALER_string_to_amount (bcs->amount,
                                &amount))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to parse amount `%s' at %s\n",
                  bcs->amount,
                  TALER_TESTING_interpreter_get_current_label (is));
      TALER_TESTING_interpreter_fail (is);
      return;
    }
  }
  else
  {
    const struct TALER_TESTING_Command *deposit_cmd;
    const struct TALER_Amount *amount_ptr;

    TALER_LOG_INFO ("`%s' uses reference (%s/%p)\n",
                    TALER_TESTING_interpreter_get_current_label
                      (is),
                    bcs->deposit_reference,
                    bcs->deposit_reference);
    deposit_cmd
      = TALER_TESTING_interpreter_lookup_command (is,
                                                  bcs->deposit_reference);
    if (NULL == deposit_cmd)
      TALER_TESTING_FAIL (is);
    if ( (GNUNET_OK !=
          TALER_TESTING_get_trait_amount (deposit_cmd,
                                          &amount_ptr)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_debit_payto_uri (deposit_cmd,
                                                   &debit_payto)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_credit_payto_uri (deposit_cmd,
                                                    &credit_payto)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_exchange_url (deposit_cmd,
                                                &exchange_base_url)) )
      TALER_TESTING_FAIL (is);
    amount = *amount_ptr;
  }
  debit_account = TALER_xtalerbank_account_from_payto (*debit_payto);
  credit_account = TALER_xtalerbank_account_from_payto (*credit_payto);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "converted debit_payto (%s) to debit_account (%s)\n",
              debit_payto->full_payto,
              debit_account);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "converted credit_payto (%s) to credit_account (%s)\n",
              credit_payto->full_payto,
              credit_account);
  if (GNUNET_OK !=
      TALER_FAKEBANK_check_debit (fakebank,
                                  &amount,
                                  debit_account,
                                  credit_account,
                                  exchange_base_url,
                                  &bcs->wtid))
  {
    GNUNET_break (0);
    GNUNET_free (credit_account);
    GNUNET_free (debit_account);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_free (credit_account);
  GNUNET_free (debit_account);
  TALER_TESTING_interpreter_next (is);
}


/**
 * Free the state of a "bank check" CMD.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
check_bank_transfer_cleanup (void *cls,
                             const struct TALER_TESTING_Command *cmd)
{
  struct BankCheckState *bcs = cls;

  (void) cmd;
  GNUNET_free (bcs);
}


/**
 * Offer internal data from a "bank check" CMD state.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
check_bank_transfer_traits (void *cls,
                            const void **ret,
                            const char *trait,
                            unsigned int index)
{
  struct BankCheckState *bcs = cls;
  struct TALER_WireTransferIdentifierRawP *wtid_ptr = &bcs->wtid;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_wtid (wtid_ptr),
    TALER_TESTING_make_trait_exchange_url (
      bcs->exchange_base_url),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_transfer (
  const char *label,
  const char *exchange_base_url,
  const char *amount,
  const struct TALER_FullPayto debit_payto,
  const struct TALER_FullPayto credit_payto)
{
  struct BankCheckState *bcs;

  bcs = GNUNET_new (struct BankCheckState);
  bcs->exchange_base_url = exchange_base_url;
  bcs->amount = amount;
  bcs->debit_payto = debit_payto;
  bcs->credit_payto = credit_payto;
  bcs->deposit_reference = NULL;
  {
    struct TALER_TESTING_Command cmd = {
      .label = label,
      .cls = bcs,
      .run = &check_bank_transfer_run,
      .cleanup = &check_bank_transfer_cleanup,
      .traits = &check_bank_transfer_traits
    };

    return cmd;
  }
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_transfer_with_ref (
  const char *label,
  const char *deposit_reference)
{
  struct BankCheckState *bcs;

  bcs = GNUNET_new (struct BankCheckState);
  bcs->deposit_reference = deposit_reference;
  {
    struct TALER_TESTING_Command cmd = {
      .label = label,
      .cls = bcs,
      .run = &check_bank_transfer_run,
      .cleanup = &check_bank_transfer_cleanup,
      .traits = &check_bank_transfer_traits
    };

    return cmd;
  }
}
