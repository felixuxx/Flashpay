/*
  This file is part of TALER
  (C) 2018 Taler Systems SA

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

#define BANK_ACCOUNT_NUMBER 1
#define BANK_USERNAME "Bank"
#define BANK_PASSWORD "x"
#define EXCHANGE_ACCOUNT_NUMBER 2
#define EXCHANGE_USERNAME "Exchange"
#define EXCHANGE_PASSWORD "x"
#define USER_ACCOUNT_NUMBER 3
#define USER_USERNAME "Tor"
#define USER_PASSWORD "x"


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
 * Make a "history" CMD.
 *
 * @param label command label.
 * @param bank_url base URL of the bank offering the "history"
 *        operation.
 * @param account_no bank account number to ask the history for.
 * @param direction which direction this operation is interested
 * @param ascending if GNUNET_YES, it ask the bank to return results
 *        in chronological order.
 * @param start_row_reference reference to a command that can
 *        offer a row identifier, to be used as the starting row
 *        to accept in the result.
 * @param num_result how many rows we want in the result.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_history (const char *label,
                                const char *bank_url,
                                uint64_t account_no,
                                enum TALER_BANK_Direction direction,
                                unsigned int ascending,
                                const char *start_row_reference,
                                long long num_results);


/**
 * Make a "history-range" CMD, picking dates from the arguments.
 *
 * @param label command label.
 * @param bank_url base URL of the bank offering the "history"
 *        operation.
 * @param account_no bank account number to ask the history for.
 * @param direction which direction this operation is interested.
 * @param ascending if GNUNET_YES, the bank will return the rows
 *        in ascending (= chronological) order.
 * @param start_date value for the 'start' argument
 *        of "/history-range".
 * @param end_date value for the 'end' argument
 *        of "/history-range".
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_history_range_with_dates (const char *label,
                                                 const char *bank_url,
                                                 uint64_t account_no,
                                                 enum TALER_BANK_Direction
                                                 direction,
                                                 unsigned int ascending,
                                                 struct GNUNET_TIME_Absolute
                                                 start_date,
                                                 struct GNUNET_TIME_Absolute
                                                 end_date);


/**
 * Make a "history-range" CMD, picking dates from traits.
 *
 * @param label command label.
 * @param bank_url base URL of the bank offering the "history"
 *        operation.
 * @param account_no bank account number to ask the history for.
 * @param direction which direction this operation is interested.
 * @param ascending if GNUNET_YES, the bank will return the rows
 *        in ascending (= chronological) order.
 * @param start_row_reference reference to a command that can
 *        offer a absolute time to use as the 'start' argument
 *        for "/history-range".
 * @param end_row_reference reference to a command that can
 *        offer a absolute time to use as the 'end' argument
 *        for "/history-range".
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_history_range (const char *label,
                                      const char *bank_url,
                                      uint64_t account_no,
                                      enum TALER_BANK_Direction direction,
                                      unsigned int ascending,
                                      const char *start_row_reference,
                                      const char *end_row_reference);


/**
 * Create a "reject" CMD.
 *
 * @param label command label.
 * @param bank_url base URL of the bank implementing the
 *        "reject" operation.
 * @param deposit_reference reference to a command that will
 *        provide a "row id" and credit (bank) account to craft
 *        the "reject" request.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_reject (const char *label,
                               const char *bank_url,
                               const char *deposit_reference);
#endif
