/*
  This file is part of TALER
  Copyright (C) 2015, 2016 GNUnet e.V. and INRIA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_wire.c
 * @brief Handle /wire requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_validation.h"
#include "taler-exchange-httpd_wire.h"
#include <jansson.h>

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
TMH_WIRE_handler_wire (struct TMH_RequestHandler *rh,
                       struct MHD_Connection *connection,
                       void **connection_cls,
                       const char *upload_data,
                       size_t *upload_data_size)
{
  static json_t *wire_methods;

  if (NULL == wire_methods)
    wire_methods = TMH_VALIDATION_get_wire_methods ("exchange-wire-incoming");

  return TMH_RESPONSE_reply_json (connection,
                                  wire_methods,
                                  MHD_HTTP_OK);
}


/* end of taler-exchange-httpd_wire.c */
