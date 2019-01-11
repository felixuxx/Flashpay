/*
  This file is part of TALER
  Copyright (C) 2014-2018 GNUnet e.V.

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
 * @file lib/exchange_api_curl_defaults.h
 * @brief curl easy handle defaults
 * @author Florian Dold
 */

#ifndef _TALER_CURL_DEFAULTS_H
#define _TALER_CURL_DEFAULTS_H


#include "platform.h"
#include <gnunet/gnunet_curl_lib.h>


/**
 * Get a curl handle with the right defaults
 * for the exchange lib.  In the future, we might manage a pool of connections here.
 *
 * @param url URL to query
 */
CURL *
TEL_curl_easy_get (const char *url);

#endif /* _TALER_CURL_DEFAULTS_H */
