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
 * @file bank/test_bank_api_with_fakebank.c
 * @brief testcase to test bank's HTTP API interface against the fakebank
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_signatures.h"
#include "taler_bank_service.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include <microhttpd.h>
#include "test_bank_interpreter.h"


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure
 */
static void
run (void *cls)
{
  int *resultp = cls;
  static struct TBI_Command commands[] =
  {
    { .oc = TBI_OC_HISTORY,
      .label = "history-0",
      .details.history.account_number = 1,
      .details.history.direction = TALER_BANK_DIRECTION_BOTH,
      .details.history.start_row_ref = NULL,
      .details.history.num_results = 1 },
    /* Add EUR:5.01 to account 1 */
    { .oc = TBI_OC_ADMIN_ADD_INCOMING,
      .label = "debit-1",
      .details.admin_add_incoming.expected_response_code = MHD_HTTP_OK,
      .details.admin_add_incoming.credit_account_no = 1,
      .details.admin_add_incoming.debit_account_no = 2,
      .details.admin_add_incoming.exchange_base_url = "https://exchange.net/",
      .details.admin_add_incoming.amount = "KUDOS:5.01" },
    /* Add EUR:3.21 to account 3 */
    { .oc = TBI_OC_HISTORY,
      .label = "history-1c",
      .details.history.account_number = 1,
      .details.history.direction = TALER_BANK_DIRECTION_CREDIT,
      .details.history.start_row_ref = NULL,
      .details.history.num_results = 5 },
    { .oc = TBI_OC_HISTORY,
      .label = "history-1d",
      .details.history.account_number = 1,
      .details.history.direction = TALER_BANK_DIRECTION_DEBIT,
      .details.history.start_row_ref = NULL,
      .details.history.num_results = 5 },
    { .oc = TBI_OC_ADMIN_ADD_INCOMING,
      .label = "debit-2",
      .details.admin_add_incoming.expected_response_code = MHD_HTTP_OK,
      .details.admin_add_incoming.credit_account_no = 3,
      .details.admin_add_incoming.debit_account_no = 2,
      .details.admin_add_incoming.exchange_base_url = "https://exchange.org/",
      .details.admin_add_incoming.amount = "KUDOS:3.21" },
    { .oc = TBI_OC_ADMIN_ADD_INCOMING,
      .label = "credit-2",
      .details.admin_add_incoming.expected_response_code = MHD_HTTP_OK,
      .details.admin_add_incoming.credit_account_no = 2,
      .details.admin_add_incoming.debit_account_no = 3,
      .details.admin_add_incoming.exchange_base_url = "https://exchange.org/",
      .details.admin_add_incoming.amount = "KUDOS:3.22" },
    { .oc = TBI_OC_HISTORY,
      .label = "history-2b",
      .details.history.account_number = 2,
      .details.history.direction = TALER_BANK_DIRECTION_BOTH,
      .details.history.start_row_ref = NULL,
      .details.history.num_results = 5 },
    { .oc = TBI_OC_HISTORY,
      .label = "history-2bi",
      .details.history.account_number = 2,
      .details.history.direction = TALER_BANK_DIRECTION_BOTH,
      .details.history.start_row_ref = "debit-1",
      .details.history.num_results = 5 },
    /* check transfers arrived at fakebank */
    { .oc = TBI_OC_EXPECT_TRANSFER,
      .label = "expect-2d",
      .details.expect_transfer.cmd_ref = "credit-2" },
    { .oc = TBI_OC_EXPECT_TRANSFER,
      .label = "expect-2c",
      .details.expect_transfer.cmd_ref = "debit-2" },
    { .oc = TBI_OC_EXPECT_TRANSFER,
      .label = "expect-1",
      .details.expect_transfer.cmd_ref = "debit-1" },
    /* check transfer list is now empty */
    { .oc = TBI_OC_EXPECT_TRANSFERS_EMPTY,
      .label = "expect-empty" },
    { .oc = TBI_OC_END }
  };

  TBI_run_interpreter (resultp,
                       GNUNET_YES,
                       commands);
}


/**
 * Main function for the testcase for the bank API.
 *
 * @param argc expected to be 1
 * @param argv expected to only contain the program name
 */
int
main (int argc,
      char * const *argv)
{
  int result;

  GNUNET_log_setup ("test-bank-api-with-fakebank",
                    "WARNING",
                    NULL);
  GNUNET_SCHEDULER_run (&run, &result);
  return (GNUNET_OK == result) ? 0 : 1;
}

/* end of test_bank_api_with_fakebank.c */
