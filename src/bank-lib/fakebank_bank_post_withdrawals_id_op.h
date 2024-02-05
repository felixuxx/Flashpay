/*
  This file is part of TALER
  (C) 2016-2024 Taler Systems SA

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
 * @file bank-lib/fakebank_bank_post_withdrawals_id_op.h
 * @brief implement bank API POST /accounts/$ACCOUNT/withdrawals/$WID/$OP endpoint(s)
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef FAKEBANK_BANK_POST_WITHDRAWALS_ID_OP_H
#define FAKEBANK_BANK_POST_WITHDRAWALS_ID_OP_H

#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"


/**
 * Handle POST /accounts/{account_name}/withdrawals/{withdrawal_id}/${OP} request.
 *
 * @param h our fakebank handle
 * @param connection the connection
 * @param account name of the account
 * @param withdrawal_id the withdrawal operation identifier
 * @param op operation to be performed, includes leading "/"
 * @param upload_data data uploaded
 * @param[in,out] upload_data_size number of bytes in @a upload_data
 * @param[in,out] con_cls application context that can be used
 * @return MHD result code
 */
MHD_RESULT
TALER_FAKEBANK_bank_withdrawals_id_op_ (
  struct TALER_FAKEBANK_Handle *h,
  struct MHD_Connection *connection,
  const char *account,
  const char *withdrawal_id,
  const char *op,
  const char *upload_data,
  size_t *upload_data_size,
  void **con_cls);

#endif
