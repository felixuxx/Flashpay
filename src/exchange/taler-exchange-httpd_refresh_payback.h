/*
  This file is part of TALER
  Copyright (C) 2014-2019 Taler Systems SA

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
 * @file taler-exchange-httpd_refresh_payback.h
 * @brief Handle /refresh/payback requests
 * @author Florian Dold
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_REFRESH_PAYBACK_H
#define TALER_EXCHANGE_HTTPD_REFRESH_PAYBACK_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Handle a "/refresh/payback" request.  Parses the request into the JSON
 * components and then processes the request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TEH_REFRESH_handler_refresh_payback (struct TEH_RequestHandler *rh,
                                     struct MHD_Connection *connection,
                                     void **connection_cls,
                                     const char *upload_data,
                                     size_t *upload_data_size);


#endif
