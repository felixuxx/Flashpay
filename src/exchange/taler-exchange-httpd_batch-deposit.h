/*
  This file is part of TALER
  Copyright (C) 2014 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_batch-deposit.h
 * @brief Handle /batch-deposit requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_BATCH_DEPOSIT_H
#define TALER_EXCHANGE_HTTPD_BATCH_DEPOSIT_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Handle a "/batch-deposit" request.  Parses the JSON, and, if
 * successful, passes the JSON data to #deposit_transaction() to
 * further check the details of the operation specified.  If everything checks
 * out, this will ultimately lead to the "/batch-deposit" being executed, or
 * rejected.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param args arguments, empty in this case
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_batch_deposit (struct TEH_RequestContext *rc,
                           const json_t *root,
                           const char *const args[]);


#endif
