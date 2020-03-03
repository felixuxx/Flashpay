/*
  This file is part of TALER
  Copyright (C) 2015, 2016, 2017 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file bank-lib/bank_api_common.h
 * @brief Common functions for the bank API
 * @author Christian Grothoff
 */
#ifndef BANK_API_COMMON_H
#define BANK_API_COMMON_H

#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_bank_service.h"
#include "taler_json_lib.h"


/**
 * Set authentication data in @a easy from @a auth.
 *
 * @param easy curl handle to setup for authentication
 * @param auth authentication data to use
 * @return #GNUNET_OK in success
 */
int
TALER_BANK_setup_auth_ (CURL *easy,
                        const struct TALER_BANK_AuthenticationData *auth);


#endif
