/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published
  by the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/

/**
 * @file auditor-lib/testing_api_cmd_insert_deposit.c
 * @brief deposit a coin directly into the database.
 * @author Marcello Stanisci
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "auditor_api_handle.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "insert-deposit" CMD.
 */
struct InsertDepositState
{
  /**
   * Configuration file used by the command.
   */
  const char *config_filename;

  /**
   * Human-readable name of the shop.
   */
  const char *merchant_name;

  /**
   * Merchant bank account (FIXME: payto, non-payto?)
   */
  const char *merchant_account;

  /**
   * Deadline before which the aggregator should
   * send the payment to the merchant.
   */
  struct GNUNET_TIME_Absolute wire_deadline;

  /**
   * Amount to deposit, inclusive of deposit fee.
   */
  const char *amount_with_fee;

  /**
   * Deposit fee.
   */
  const char *deposit_fee;
};


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the commaind being run.
 * @param is interpreter state.
 */
static void
insert_deposit_run (void *cls,
                    const struct TALER_TESTING_Command *cmd,
                    struct TALER_TESTING_Interpreter *is)
{
  struct InsertDepositState *ids = cls;
  // TODO
}


/**
 * Free the state of a "auditor-dbinit" CMD, and possibly kills its
 * process if it did not terminate correctly.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
insert_deposit_cleanup (void *cls,
                        const struct TALER_TESTING_Command *cmd)
{
  struct InsertDepositState *ds = cls;

  GNUNET_free (ds);
}


/**
 * Offer "insert-deposit" CMD internal data to other commands.
 *
 * @param cls closure.
 * @param ret[out] result
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static int
insert_deposit_traits (void *cls,
                       const void **ret,
                       const char *trait,
                       unsigned int index)
{
  struct InsertDepositState *ids = cls;
  struct TALER_TESTING_Trait traits[] = {
    // FIXME: needed?
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Make the "insert-deposit" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @param merchant_name Human-readable name of the merchant.
 * @param merchant_account value indicating the merchant at its bank.
 * @param wire_deadline point in time where the aggregator should have
 *        wired money to the merchant.
 * @param amount_with_fee amount to deposit (inclusive of deposit fee)
 * @param deposit_fee deposit fee
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_insert_deposit (const char *label,
                                  const char *config_filename,
				  const char *merchant_name,
				  const char *merchant_account,
				  struct GNUNET_TIME_Absolute wire_deadline,
				  const char *amount_with_fee,
				  const char *deposit_fee)
{
  struct TALER_TESTING_Command cmd;
  struct InsertDepositState *ids;

  ids = GNUNET_new (struct InsertDepositState);
  ids->config_filename = config_filename;
  ids->merchant_name = merchant_name;
  ids->merchant_account = merchant_account;
  ids->wire_deadline = wire_deadline;
  ids->amount_with_fee = amount_with_fee;
  ids->deposit_fee = deposit_fee;

  cmd.cls = ids;
  cmd.label = label;
  cmd.run = &insert_deposit_run;
  cmd.cleanup = &insert_deposit_cleanup;
  cmd.traits = &insert_deposit_traits;
  return cmd;
}


/* end of testing_auditor_api_cmd_exec_auditor_dbinit.c */
