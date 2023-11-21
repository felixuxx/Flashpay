/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of EXCHANGEABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_spa.h
 * @brief logic to preload and serve static files
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_SPA_H
#define TALER_EXCHANGE_HTTPD_SPA_H

#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Return our single-page-app user interface (see contrib/wallet-core/).
 *
 * @param rc context of the handler
 * @param[in,out] args remaining arguments (ignored)
 * @return #MHD_YES on success (reply queued), #MHD_NO on error (close connection)
 */
MHD_RESULT
TEH_handler_spa (struct TEH_RequestContext *rc,
                 const char *const args[]);


/**
 * Preload and compress SPA files.
 *
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TEH_spa_init (void);


#endif
