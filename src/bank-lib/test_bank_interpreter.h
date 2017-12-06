/*
  This file is part of TALER
  Copyright (C) 2016, 2017 GNUnet e.V.

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
 * @file bank/test_bank_interpreter.h
 * @brief interpreter for tests of the bank's HTTP API interface
 * @author Christian Grothoff
 */
#ifndef TEST_BANK_INTERPRETER_H
#define TEST_BANK_INTERPRETER_H

#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_bank_service.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include <microhttpd.h>


/**
 * Opcodes for the interpreter.
 */
enum TBI_OpCode
{
  /**
   * Termination code, stops the interpreter loop (with success).
   */
  TBI_OC_END = 0,

  /**
   * Add funds to a reserve by (faking) incoming wire transfer.
   */
  TBI_OC_ADMIN_ADD_INCOMING,

  /**
   * Request wire transfer history.
   */
  TBI_OC_HISTORY,

  /**
   * Expect that we have received the specified transfer at fakebank.
   */
  TBI_OC_EXPECT_TRANSFER,

  /**
   * Expect that we have exhaustively gone over all transfers at fakebank.
   */
  TBI_OC_EXPECT_TRANSFERS_EMPTY,

  /**
   * Reject incoming transfer.
   */
  TBI_OC_REJECT

};


/**
 * Details for a bank operation to execute.
 */
struct TBI_Command
{
  /**
   * Opcode of the command.
   */
  enum TBI_OpCode oc;

  /**
   * Label for the command, can be NULL.
   */
  const char *label;

  /**
   * Details about the command.
   */
  union
  {

    /**
     * Information for a #TBI_OC_ADMIN_ADD_INCOMING command.
     */
    struct
    {

      /**
       * String describing the amount to add to the reserve.
       */
      const char *amount;

      /**
       * Credited account number.
       */
      uint64_t credit_account_no;

      /**
       * Debited account number.
       */
      uint64_t debit_account_no;

      /**
       * Exchange base URL to use.
       */
      const char *exchange_base_url;

      /**
       * Wire transfer subject to use.
       */
      const char *subject;

      /**
       * Which response code do we expect for this command?
       */
      unsigned int expected_response_code;

      /**
       * Set to the API's handle during the operation.
       */
      struct TALER_BANK_AdminAddIncomingHandle *aih;

      /**
       * The serial ID for this record, as returned by the bank.
       */
      uint64_t serial_id;

    } admin_add_incoming;

    struct {

      /**
       * For which account do we query the history.
       */
      uint64_t account_number;

      /**
       * Which types of transactions should be listed?
       */
      enum TALER_BANK_Direction direction;

      /**
       * At which serial ID do we start? References the respective @e
       * admin_add_incoming command.  Use NULL for the extremes.
       */
      const char *start_row_ref;

      /**
       * How many results should be returned (if available)?
       */
      int64_t num_results;

      /**
       * Set to the API's handle during the operation.
       */
      struct TALER_BANK_HistoryHandle *hh;

      /**
       * How many results did we actually get?
       */
      uint64_t results_obtained;

      /**
       * Set to #GNUNET_YES if we encountered a problem.
       */
      int failed;

    } history;

    /**
     * If @e opcode is #TBI_OC_EXPECT_TRANSFER, this
     * specifies which transfer we expected.
     */
    struct {

      /**
       * Label of the command of an /admin/add/incoming
       * request that we should check was executed.
       */
      const char *cmd_ref;

    } expect_transfer;

    /**
     * Execute /reject operation.
     */
    struct {

      /**
       * Reference to the matching transfer that is now to be rejected.
       */
      const char *cmd_ref;

      /**
       * Set to the API's handle during the operation.
       */
      struct TALER_BANK_RejectHandle *rh;

    } reject;

  } details;

};


/**
 * Entry point to the interpeter.
 *
 * @param resultp where to store the final result
 * @param run_bank #GNUNET_YES to run the fakebank
 * @param commands list of commands to run
 */
void
TBI_run_interpreter (int *resultp,
                     int run_bank,
                     struct TBI_Command *commands);

#endif
