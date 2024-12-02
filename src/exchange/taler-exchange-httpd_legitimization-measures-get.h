/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file taler-exchange-httpd_legitimization-measures-get.h
 * @brief Handle /aml/$OFFICER_PUB/legitimizations requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_LEGITIMIZATION_MEASURES_GET_H
#define TALER_EXCHANGE_HTTPD_LEGITIMIZATION_MEASURES_GET_H

#include <microhttpd.h>
#include "taler-exchange-httpd.h"

/**
 * Handle a GET "/aml/$OFFICER_PUB/legitimizations" request.  Parses the request
 * details, checks the signatures and if appropriately authorized returns
 * the matching measuress.
 *
 * @param rc request context
 * @param officer_pub public key of the AML officer who made the request
 * @param args GET arguments (should be the state)
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_legitimization_measures_get (
  struct TEH_RequestContext *rc,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const char *const args[]);

#endif
