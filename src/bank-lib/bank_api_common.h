/*
  This file is part of TALER
  Copyright (C) 2015, 2016, 2017 GNUnet e.V.

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
#include <jansson.h>
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_bank_service.h"
#include "taler_json_lib.h"


/**
 * Build authentication header from @a auth.
 *
 * @param auth authentication data to use
 * @return NULL on error, otherwise curl headers to use
 */
struct curl_slist *
TALER_BANK_make_auth_header_ (const struct TALER_BANK_AuthenticationData *auth);


/**
 * Obtain the URL to use for an API request.
 *
 * @param u base URL of the bank
 * @param path Taler API path (i.e. "/history")
 * @return the full URI to use with cURL
 */
char *
TALER_BANK_path_to_url_ (const char *u,
                         const char *path);


/**
 * Parse error code given in @a json.
 *
 * @param json the json to parse
 * @return error code, or #TALER_EC_INVALID if not found
 */
enum TALER_ErrorCode
TALER_BANK_parse_ec_ (const json_t *json);


#endif
