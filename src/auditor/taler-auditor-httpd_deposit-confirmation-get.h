/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file taler-auditor-httpd_deposit-confirmation-get.h
 * @brief Handle GET /deposit-confirmation requests
 * @author Nic Eigel
 */
#ifndef TALER_AUDITOR_HTTPD_DEPOSIT_CONFIRMATION_GET_H
#define TALER_AUDITOR_HTTPD_DEPOSIT_CONFIRMATION_GET_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-auditor-httpd.h"

/**
 * Initialize subsystem.
 */
void
TEAH_DEPOSIT_CONFIRMATION_GET_init (void);

/**
 * Shut down subsystem.
 */
void
TEAH_DEPOSIT_CONFIRMATION_GET_done (void);

/**
 * Handle a "/deposit-confirmation" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @param args NULL-terminated array of remaining parts of the URI broken up at '/'
 * @return MHD result code
 */
MHD_RESULT
TAH_DEPOSIT_CONFIRMATION_handler_get (
  struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size,
  const char *const args[]);


#endif
