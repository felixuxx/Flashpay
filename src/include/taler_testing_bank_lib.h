/*
  This file is part of TALER
  (C) 2018-2020 Taler Systems SA

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
 * @file include/taler_testing_bank_lib.h
 * @brief API for writing test cases to test banks.
 * @author Marcello Stanisci
 */
#ifndef TALER_TESTING_BANK_LIB_H
#define TALER_TESTING_BANK_LIB_H

#include "taler_util.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include <microhttpd.h>
#include "taler_bank_service.h"
#include "taler_testing_lib.h"


/* ******** Credentials to log in at the bank ******* */

/* Note that the same passwords must be set in the script in
   contrib/taler-bank-manage-testing for the tests to work! */
#define TALER_TESTING_BANK_ACCOUNT_NUMBER 1
#define TALER_TESTING_BANK_USERNAME "Bank"
#define TALER_TESTING_BANK_PASSWORD "x"
#define TALER_TESTING_EXCHANGE_ACCOUNT_NUMBER 2
#define TALER_TESTING_EXCHANGE_USERNAME "Exchange"
#define TALER_TESTING_EXCHANGE_PASSWORD "x"
#define TALER_TESTING_USER_ACCOUNT_NUMBER 3
#define TALER_TESTING_USER_USERNAME "Tor"
#define TALER_TESTING_USER_PASSWORD "x"


/* ********************* Helper functions ********************* */

/**
 * Start the (Python) bank process.  Assume the port
 * is available and the database is clean.  Use the "prepare
 * bank" function to do such tasks.
 *
 * @param config_filename configuration filename.
 * @param bank_url base URL of the bank, used by `wget' to check
 *        that the bank was started right.
 *
 * @return the process, or NULL if the process could not
 *         be started.
 */
struct GNUNET_OS_Process *
TALER_TESTING_run_bank (const char *config_filename,
                        const char *bank_url);

/**
 * Runs the Fakebank by guessing / extracting the portnumber
 * from the base URL.
 *
 * @param bank_url bank's base URL.
 * @return the fakebank process handle, or NULL if any
 *         error occurs.
 */
struct TALER_FAKEBANK_Handle *
TALER_TESTING_run_fakebank (const char *bank_url);

/**
 * Prepare the bank execution.  Check if the port is available
 * and reset database.
 *
 * @param config_filename configuration file name.
 *
 * @return the base url, or NULL upon errors.  Must be freed
 *         by the caller.
 */
char *
TALER_TESTING_prepare_bank (const char *config_filename);


/**
 * Look for substring in a programs' name.
 *
 * @param prog program's name to look into
 * @param marker chunk to find in @a prog
 */
int
TALER_TESTING_has_in_name (const char *prog,
                           const char *marker);

/* ************** Specific interpreter commands ************ */

/**
 * Make a credit "history" CMD.
 *
 * @param label command label.
 * @param account_url base URL of the account offering the "history"
 *        operation.
 * @param start_row_reference reference to a command that can
 *        offer a row identifier, to be used as the starting row
 *        to accept in the result.
 * @param num_results how many rows we want in the result,
 *        and ascending/descending call
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_credits (const char *label,
                                const char *account_url,
                                const char *start_row_reference,
                                long long num_results);


/**
 * Make a debit "history" CMD.
 *
 * @param label command label.
 * @param account_url base URL of the account offering the "history"
 *        operation.
 * @param start_row_reference reference to a command that can
 *        offer a row identifier, to be used as the starting row
 *        to accept in the result.
 * @param num_results how many rows we want in the result.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_debits (const char *label,
                               const char *account_url,
                               const char *start_row_reference,
                               long long num_results);


#endif
