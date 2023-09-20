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
 * @file bank-lib/fakebank_tbi_get_withdrawal_operation.h
 * @brief Implementation of the GET /withdrawal-operation/ request of the Taler Bank Integration API
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef FAKEBANK_TBI_GET_WITHDRAWAL_OPERATION_H
#define FAKEBANK_TBI_GET_WITHDRAWAL_OPERATION_H

#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"

/**
 * Handle GET /withdrawal-operation/{wopid} request.
 *
 * @param h the handle
 * @param connection the connection
 * @param wopid the withdrawal operation identifier
 * @param lp how long is the long-polling timeout
 * @param con_cls closure for request
 * @return MHD result code
 */
MHD_RESULT
TALER_FAKEBANK_tbi_get_withdrawal_operation_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *wopid,
  struct GNUNET_TIME_Relative lp,
  void **con_cls);

#endif
