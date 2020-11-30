/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file taler-exchange-httpd_auditors.h
 * @brief Handlers for the /auditors/ endpoints
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_AUDITORS_H
#define TALER_EXCHANGE_HTTPD_AUDITORS_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Handle a "/auditors/$AUDITOR_PUB/$H_DENOM_PUB" request.
 *
 * @param connection the MHD connection to handle
 * @param root uploaded JSON data
 * @param auditor_pub public key of the auditor
 * @param h_denom_pub hash of the denomination public key
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_management_denominations_auditors (
  struct MHD_Connection *connection,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct GNUNET_HashCode *h_denom_pub,
  const json_t *root);


#endif
