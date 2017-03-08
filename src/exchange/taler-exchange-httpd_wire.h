/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 Inria and GNUnet e.V.

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
 * @file taler-exchange-httpd_wire.h
 * @brief Handle /wire requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_WIRE_H
#define TALER_EXCHANGE_HTTPD_WIRE_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Initialize wire subsystem.
 *
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if we found no valid
 *         wire methods
 */
int
TEH_WIRE_init (void);


/**
 * Obtain fee structure for @a wire_plugin_name wire transfers.
 *
 * @param wire_plugin_name name of the plugin to load fees for
 * @return JSON object (to be freed by caller) with fee structure
 */
json_t *
TEH_WIRE_get_fees (const char *wire_plugin_name);


/**
 * Handle a "/wire" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TEH_WIRE_handler_wire (struct TEH_RequestHandler *rh,
                       struct MHD_Connection *connection,
                       void **connection_cls,
                       const char *upload_data,
                       size_t *upload_data_size);


#endif
