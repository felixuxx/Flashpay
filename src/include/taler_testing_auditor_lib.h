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
 * @file include/taler_testing_auditor_lib.h
 * @brief API for writing an interpreter to test Taler components
 * @author Christian Grothoff <christian@grothoff.org>
 * @author Marcello Stanisci
 */
#ifndef TALER_TESTING_AUDITOR_LIB_H
#define TALER_TESTING_AUDITOR_LIB_H

#include "taler_util.h"
#include "taler_exchange_service.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_json_lib.h"
#include <microhttpd.h>


/* ********************* Commands ********************* */

/**
 * Make the "exec-auditor" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_auditor (const char *label,
                                const char *config_filename);


/**
 * Make the "exec wire-auditor" CMD.
 *
 * @param label command label.
 * @param config_filename configuration filename.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exec_wire_auditor (const char *label,
                                     const char *config_filename);


/**
 * Create a "deposit-confirmation" command.
 *
 * @param label command label.
 * @param auditor auditor connection.
 * @param deposit_reference reference to any operation that can
 *        provide a coin.
 * @param coin_index if @a deposit_reference offers an array of
 *        coins, this parameter selects which one in that array.
 *        This value is currently ignored, as only one-coin
 *        deposits are implemented.
 * @param amount_without_fee deposited amount without the fee
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_confirmation
  (const char *label,
   struct TALER_AUDITOR_Handle *auditor,
   const char *deposit_reference,
   unsigned int coin_index,
   const char *amount_without_fee,
   unsigned int expected_response_code);


/**
 * Modify a deposit confirmation command to enable retries when we get
 * transient errors from the auditor.
 *
 * @param cmd a deposit confirmation command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_deposit_confirmation_with_retry (struct TALER_TESTING_Command cmd);


/**
 * Create a "list exchanges" command.
 *
 * @param label command label.
 * @param auditor auditor connection.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exchanges
  (const char *label,
   struct TALER_AUDITOR_Handle *auditor,
   unsigned int expected_response_code);


/**
 * Modify an exchanges command to enable retries when we get
 * transient errors from the auditor.
 *
 * @param cmd a deposit confirmation command
 * @return the command with retries enabled
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_exchanges_with_retry (struct TALER_TESTING_Command cmd);


/* ********************* Helper functions ********************* */


/**
 * Install signal handlers plus schedules the main wrapper
 * around the "run" method.
 *
 * @param main_cb the "run" method which contains all the
 *        commands.
 * @param main_cb_cls a closure for "run", typically NULL.
 * @param config_filename configuration filename.
 * @return #GNUNET_OK if all is okay, != #GNUNET_OK otherwise.
 *         non-GNUNET_OK codes are #GNUNET_SYSERR most of the
 *         times.
 */
int
TALER_TESTING_AUDITOR_setup (TALER_TESTING_Main main_cb,
                             void *main_cb_cls,
                             const char *config_filename);


#endif
