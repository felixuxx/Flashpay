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
 * @file bank-lib/fakebank_common_make_admin_transfer.h
 * @brief routines to create transfers to the exchange
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef FAKEBANK_COMMON_MAKE_ADMIN_TRANSFER_H
#define FAKEBANK_COMMON_MAKE_ADMIN_TRANSFER_H

#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"


/**
 * Tell the fakebank to create another wire transfer *to* an exchange.
 *
 * @param h fake bank handle
 * @param debit_account account to debit
 * @param credit_account account to credit
 * @param amount amount to transfer
 * @param reserve_pub reserve public key to use in subject
 * @param[out] row_id serial_id of the transfer
 * @param[out] timestamp when was the transfer made
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_FAKEBANK_make_admin_transfer_ (
  struct TALER_FAKEBANK_Handle *h,
  const char *debit_account,
  const char *credit_account,
  const struct TALER_Amount *amount,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  uint64_t *row_id,
  struct GNUNET_TIME_Timestamp *timestamp);


/**
 * Tell the fakebank to create a KYCAUTH wire transfer *to* an exchange.
 *
 * @param h fake bank handle
 * @param debit_account account to debit
 * @param credit_account account to credit
 * @param amount amount to transfer
 * @param account_pub account public key to use in subject
 * @param[out] row_id serial_id of the transfer
 * @param[out] timestamp when was the transfer made
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_FAKEBANK_make_kycauth_transfer_ (
  struct TALER_FAKEBANK_Handle *h,
  const char *debit_account,
  const char *credit_account,
  const struct TALER_Amount *amount,
  const union TALER_AccountPublicKeyP *account_pub,
  uint64_t *row_id,
  struct GNUNET_TIME_Timestamp *timestamp);

#endif
