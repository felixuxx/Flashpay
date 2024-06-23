/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
 */


#ifndef SRC_TALER_AUDITOR_HTTPD_WIRE_FORMAT_INCONSISTENCY_PUT_H
#define SRC_TALER_AUDITOR_HTTPD_WIRE_FORMAT_INCONSISTENCY_PUT_H

#include <microhttpd.h>
#include "taler-auditor-httpd.h"

/**
* Initialize subsystem.
*/
void
TEAH_BAD_WIRE_FORMAT_INCONSISTENCY_init (void);

/**
* Shut down subsystem.
*/
void
TEAH_BAD_WIRE_FORMAT_INCONSISTENCY_done (void);


/**
* Handle a "/wire-format-inconsistency" request.  Parses the JSON, and, if
* successful, checks the signatures and stores the result in the DB.
*
* @param rh context of the handler
* @param connection the MHD connection to handle
* @param[in,out] connection_cls the connection's closure (can be updated)
* @param upload_data upload data
* @param[in,out] upload_data_size number of bytes (left) in @a upload_data
* @return MHD result code
*/
MHD_RESULT
TAH_WIRE_FORMAT_INCONSISTENCY_handler_put (struct TAH_RequestHandler *rh,
                                           struct MHD_Connection *
                                           connection,
                                           void **connection_cls,
                                           const char *upload_data,
                                           size_t *upload_data_size,
                                           const char *const args[]);


#endif // SRC_TALER_AUDITOR_HTTPD_WIRE_FORMAT_INCONSISTENCY_PUT_H
