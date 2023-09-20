/*
  This file is part of TALER
  (C) 2016-2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 3,
  or (at your option) any later version.

  TALER is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not,
  see <http://www.gnu.org/licenses/>
*/
/**
 * @file bank-lib/fakebank_bank.h
 * @brief Main dispatcher for the Taler Bank API
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef FAKEBANK_BANK_H
#define FAKEBANK_BANK_H

#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"

/**
 * Handle incoming HTTP request to the Taler bank API.
 *
 * @param h our fakebank handle
 * @param connection the connection
 * @param url the requested url
 * @param method the method (POST, GET, ...)
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure for request
 * @return MHD result code
 */
MHD_RESULT
TALER_FAKEBANK_bank_main_ (struct TALER_FAKEBANK_Handle *h,
                           struct MHD_Connection *connection,
                           const char *url,
                           const char *method,
                           const char *upload_data,
                           size_t *upload_data_size,
                           void **con_cls);

#endif
