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
 * @file bank-lib/fakebank_common_lookup.h
 * @brief common helper functions related to lookups
 * @author Christian Grothoff <christian@grothoff.org>
 */

#ifndef FAKEBANK_COMMON_LOOKUP_H
#define FAKEBANK_COMMON_LOOKUP_H

#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"


/**
 * Lookup account with @a name, and if it does not exist, create it.
 *
 * @param[in,out] h bank to lookup account at
 * @param name account name to resolve
 * @param receiver_name receiver name in payto:// URI,
 *         NULL if the account must already exist
 * @return account handle, NULL if account does not yet exist
 */
struct Account *
TALER_FAKEBANK_lookup_account_ (
  struct TALER_FAKEBANK_Handle *h,
  const char *name,
  const char *receiver_name);


/**
 * Find withdrawal operation @a wopid in @a h.
 *
 * @param h fakebank handle
 * @param wopid withdrawal operation ID as a string
 * @return NULL if operation was not found
 */
struct WithdrawalOperation *
TALER_FAKEBANK_lookup_withdrawal_operation_ (struct TALER_FAKEBANK_Handle *h,
                                             const char *wopid);

#endif
