/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file taler-auditor-httpd_spa.h
 * @brief logic to preload and serve static files
 * @author Christian Grothoff
 */
#ifndef TALER_AUDITOR_HTTPD_SPA_H
#define TALER_AUDITOR_HTTPD_SPA_H

#include <microhttpd.h>
#include "taler-auditor-httpd.h"


/**
 * Return our single-page-app user interface
 * for staff (see contrib/wallet-core/).
 *
 * @param rh request context
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
MHD_RESULT
TAH_spa_handler (
  /* const */ struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size,
  const char *const args[]);


/**
 * Preload and compress SPA files.
 *
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TAH_spa_init (void);


#endif
