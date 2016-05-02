/*
  This file is part of TALER
  Copyright (C) 2016 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
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
    /* Add EUR:5.01 to account 42 */
    { .oc = TBI_OC_ADMIN_ADD_INCOMING,
      .label = "deposit-1",
      .expected_response_code = MHD_HTTP_OK,
      .details.admin_add_incoming.credit_account_no = 1,
      .details.admin_add_incoming.debit_account_no = 2,
      .details.admin_add_incoming.amount = "PUDOS:5.01" },

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
