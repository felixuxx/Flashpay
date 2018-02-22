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
 * @brief API for writing an interpreter to test Taler components
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
#define USER_USERNAME "user3"
#define USER_PASSWORD "pass3"


/* ********************* Helper functions ********************* */

#define BANK_FAIL() \
  do {GNUNET_break (0); return NULL; } while (0)

/**
 * Start the (Python) bank process.  Assume the port
 * is available and the database is clean.  Use the "prepare
 * bank" function to do such tasks.
 *
 * @param config_filename configuration filename.
 *
 * @return the process, or NULL if the process could not
 *         be started.
 */
struct GNUNET_OS_Process *
TALER_TESTING_run_bank (const char *config_filename);

/**
 * Prepare the bank execution.  Check if the port is available
 * (and reset database?).
 *
 * @param config_filename configuration filename.
 *
 * @return the base url, or NULL upon errors.  Must be freed
 *         by the caller.
 */
char *
TALER_TESTING_prepare_bank (const char *config_filename);


/* ******************* Generic interpreter logic ************ */

/* ************** Specific interpreter commands ************ */

/**
 * Test /history API from the bank.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_history
  (const char *label,
   const char *bank_url,
   uint64_t account_no,
   enum TALER_BANK_Direction direction,
   const char *start_row_reference,
   unsigned int num_results);

/**
 * FIXME.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_reject (const char *label,
                               const char *bank_url,
                               const char *deposit_reference);

/* *** Generic trait logic for implementing traits ********* */

/* ****** Specific traits supported by this component ******* */

#endif
