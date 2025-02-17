/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file taler-auditor-httpd_mhd.c
 * @brief helpers for MHD interaction; these are TALER_MHD_handler_ functions
 *        that generate simple MHD replies that do not require any real operations
 *        to be performed (error handling, static pages, etc.)
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_mhd_lib.h"
#include "taler-auditor-httpd.h"
#include "taler-auditor-httpd_mhd.h"


MHD_RESULT
TAH_MHD_handler_static_response (struct TAH_RequestHandler *rh,
                                 struct MHD_Connection *connection,
                                 void **connection_cls,
                                 const char *upload_data,
                                 size_t *upload_data_size,
                                 const char *const args[])
{
  size_t dlen;

  (void) connection_cls;
  (void) upload_data;
  (void) upload_data_size;
  dlen = (0 == rh->data_size)
         ? strlen ((const char *) rh->data)
         : rh->data_size;
  return TALER_MHD_reply_static (connection,
                                 rh->response_code,
                                 rh->mime_type,
                                 rh->data,
                                 dlen);
}


MHD_RESULT
TAH_MHD_handler_agpl_redirect (struct TAH_RequestHandler *rh,
                               struct MHD_Connection *connection,
                               void **connection_cls,
                               const char *upload_data,
                               size_t *upload_data_size,
                               const char *const args[])
{
  (void) rh;
  (void) connection_cls;
  (void) upload_data;
  (void) upload_data_size;
  return TALER_MHD_reply_agpl (connection,
                               "http://www.git.taler.net/?p=exchange.git");
}


/* end of taler-auditor-httpd_mhd.c */
