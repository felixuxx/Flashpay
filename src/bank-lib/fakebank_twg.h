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
 * @file bank-lib/fakebank_twg.h
 * @brief main entry point for the Taler Wire Gateway API
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef FAKEBANK_TWG_H
#define FAKEBANK_TWG_H

#include "taler_fakebank_lib.h"
#include <gnunet/gnunet_mhd_compat.h>


/**
 * Handle incoming HTTP request to the Taler Wire Gateway
 * API.
 *
 * @param h our handle
 * @param connection the connection
 * @param url the requested url
 * @param method the method (POST, GET, ...)
 * @param account which account should process the request
 * @param upload_data request data
 * @param upload_data_size size of @a upload_data in bytes
 * @param con_cls closure
 * @return MHD result code
 */
MHD_RESULT
TALER_FAKEBANK_twg_main_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  const char *url,
  const char *method,
  const char *upload_data,
  size_t *upload_data_size,
  void **con_cls);

#endif
