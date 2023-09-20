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
 * @file bank-lib/fakebank_bank_get_accounts.h
 * @brief implements the Taler Bank API "GET /accounts/" handler
 * @author Christian Grothoff <christian@grothoff.org>
 */
#ifndef FAKEBANK_BANK_GET_ACCOUNTS_H
#define FAKEBANK_BANK_GET_ACCOUNTS_H

#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_mhd_lib.h"
#include <gnunet/gnunet_mhd_compat.h>
#include "fakebank.h"


/**
 * Handle GET /accounts/${account_name} request of the Taler bank API.
 *
 * @param h the handle
 * @param connection the connection
 * @param account_name name of the account
 * @return MHD result code
 */
MHD_RESULT
TALER_FAKEBANK_bank_get_accounts_ (struct TALER_FAKEBANK_Handle *h,
                                   struct MHD_Connection *connection,
                                   const char *account_name);


#endif
