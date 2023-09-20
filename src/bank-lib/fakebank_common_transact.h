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
 * @file bank-lib/fakebank_common_transact.h
 * @brief actual transaction logic for FAKEBANK
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef FAKEBANK_COMMON_TRANSACT_H
#define FAKEBANK_COMMON_TRANSACT_H

#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"


/**
 * Add transaction to the debit and credit accounts,
 * updating the balances as needed.
 *
 * The transaction @a t must already be locked
 * when calling this function!
 *
 * @param[in,out] h bank handle
 * @param[in,out] t transaction to add to account lists
 */
void
TALER_FAKEBANK_transact_ (struct TALER_FAKEBANK_Handle *h,
                          struct Transaction *t);


/**
 * Tell the fakebank to create another wire transfer *from* an exchange.
 *
 * @param h fake bank handle
 * @param debit_account account to debit
 * @param credit_account account to credit
 * @param amount amount to transfer
 * @param subject wire transfer subject to use
 * @param exchange_base_url exchange URL
 * @param request_uid unique number to make the request unique, or NULL to create one
 * @param[out] ret_row_id pointer to store the row ID of this transaction
 * @param[out] timestamp set to the time of the transfer
 * @return #GNUNET_YES if the transfer was successful,
 *         #GNUNET_SYSERR if the request_uid was reused for a different transfer
 */
enum GNUNET_GenericReturnValue
TALER_FAKEBANK_make_transfer_ (
  struct TALER_FAKEBANK_Handle *h,
  const char *debit_account,
  const char *credit_account,
  const struct TALER_Amount *amount,
  const struct TALER_WireTransferIdentifierRawP *subject,
  const char *exchange_base_url,
  const struct GNUNET_HashCode *request_uid,
  uint64_t *ret_row_id,
  struct GNUNET_TIME_Timestamp *timestamp);

#endif
