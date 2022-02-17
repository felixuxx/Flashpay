/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
 * @file taler-exchange-httpd_csr.h
 * @brief Handle /csr-* requests
 * @author Lucien Heuzeveldt
 * @author Gian Demarmles
 */
#ifndef TALER_EXCHANGE_HTTPD_CSR_H
#define TALER_EXCHANGE_HTTPD_CSR_H

#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Handle a "/csr-melt" request.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param args empty array
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_csr_melt (struct TEH_RequestContext *rc,
                      const json_t *root,
                      const char *const args[]);


/**
 * Handle a "/csr-withdraw" request.
 *
 * @param rc request context
 * @param root uploaded JSON data
 * @param args empty array
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_csr_withdraw (struct TEH_RequestContext *rc,
                          const json_t *root,
                          const char *const args[]);

#endif
