/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_extensions.h
 * @brief Manage extensions
 * @author Özgür Kesim
 */
#ifndef TALER_EXCHANGE_HTTPD_EXTENSIONS_H
#define TALER_EXCHANGE_HTTPD_EXTENSIONS_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Initialize extensions
 *
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TEH_extensions_init (void);

/**
 * Terminate the extension subsystem
 */
void
TEH_extensions_done (void);


/**
 * Handle POST "/extensions/..." requests.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param args array of additional options
 * @return MHD result code
 */
MHD_RESULT
TEH_extensions_post_handler (
  struct TEH_RequestContext *rc,
  const json_t *root,
  const char *const args[]);

#endif
