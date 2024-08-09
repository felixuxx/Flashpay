/*
  This file is part of TALER
  (C) 2024 Taler Systems SA

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
 * @file bank-lib/fakebank_twg_get_transfers.h
 * @brief routines to return outgoing transaction status
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef FAKEBANK_TWG_GET_TRANSFERS_H
#define FAKEBANK_TWG_GET_TRANSFERS_H

#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"


/**
 * Handle incoming HTTP request for /transfers
 *
 * @param h the fakebank handle
 * @param connection the connection
 * @param account which account the request is about
 * @param con_cls closure for request
 */
MHD_RESULT
TALER_FAKEBANK_twg_get_transfers_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  void **con_cls);


/**
 * Handle incoming HTTP request for /transfers/$ID
 *
 * @param h the fakebank handle
 * @param connection the connection
 * @param account which account the request is about
 * @param id the transfer ID the request is about
 * @param con_cls closure for request
 */
MHD_RESULT
TALER_FAKEBANK_twg_get_transfers_id_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  const char *id,
  void **con_cls);


#endif
