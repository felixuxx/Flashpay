/*
  This file is part of TALER
  Copyright (C) 2018-2020, 2024 Taler Systems SA

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
 * @file testing/testing_api_cmd_bank_admin_check.c
 * @brief command to check if a particular admin/add-incoming transfer took
 *        place.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"
#include "taler_fakebank_lib.h"


/**
 * State for a "bank check" CMD.
 */
struct BankAdminCheckState
{

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
   * Command providing the reserve public key trait to use.
   */
  const char *reserve_pub_ref;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

};

/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
check_bank_admin_transfer_run (void *cls,
                               const struct TALER_TESTING_Command *cmd,
                               struct TALER_TESTING_Interpreter *is)
{
  struct BankAdminCheckState *bcs = cls;
  struct TALER_Amount amount;
  char *debit_account;
  char *credit_account;
  struct TALER_FullPayto debit_payto;
  struct TALER_FullPayto credit_payto;
  const struct TALER_ReservePublicKeyP *reserve_pub;
  const struct TALER_TESTING_Command *cmd_ref;
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
  cmd_ref
    = TALER_TESTING_interpreter_lookup_command (is,
                                                bcs->reserve_pub_ref);
  if (NULL == cmd_ref)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_pub (cmd_ref,
                                           &reserve_pub))
  {
    GNUNET_break (0);
    TALER_LOG_ERROR ("Command reference fails to provide reserve public key\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  debit_payto = bcs->debit_payto;
  credit_payto = bcs->credit_payto;
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
  debit_account = TALER_xtalerbank_account_from_payto (debit_payto);
  credit_account = TALER_xtalerbank_account_from_payto (credit_payto);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "converted debit_payto (%s) to debit_account (%s)\n",
              debit_payto.full_payto,
              debit_account);
  if (GNUNET_OK !=
      TALER_FAKEBANK_check_credit (fakebank,
                                   &amount,
                                   debit_account,
                                   credit_account,
                                   reserve_pub))
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
check_bank_admin_transfer_cleanup (void *cls,
                                   const struct TALER_TESTING_Command *cmd)
{
  struct BankAdminCheckState *bcs = cls;

  (void) cmd;
  GNUNET_free (bcs);
}


/**
 * Make a "bank check" CMD.  It checks whether a particular wire transfer to
 * the exchange (credit) has been made or not.
 *
 * @param label the command label.
 * @param amount the amount expected to be transferred.
 * @param debit_payto the account that gave money.
 * @param credit_payto the account that received money.
 * @param reserve_pub_ref command that provides the reserve public key to expect
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_check_bank_admin_transfer (
  const char *label,
  const char *amount,
  struct TALER_FullPayto debit_payto,
  struct TALER_FullPayto credit_payto,
  const char *reserve_pub_ref)
{
  struct BankAdminCheckState *bcs;

  bcs = GNUNET_new (struct BankAdminCheckState);
  bcs->amount = amount;
  bcs->debit_payto = debit_payto;
  bcs->credit_payto = credit_payto;
  bcs->reserve_pub_ref = reserve_pub_ref;
  {
    struct TALER_TESTING_Command cmd = {
      .label = label,
      .cls = bcs,
      .run = &check_bank_admin_transfer_run,
      .cleanup = &check_bank_admin_transfer_cleanup
    };

    return cmd;
  }
}
