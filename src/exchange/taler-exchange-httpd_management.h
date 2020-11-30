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
 * @file taler-exchange-httpd_management.h
 * @brief Handlers for the /management/ endpoints
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_MANAGEMENT_H
#define TALER_EXCHANGE_HTTPD_MANAGEMENT_H

#include <gnunet/gnunet_util_lib.h>
#include <microhttpd.h>
#include "taler-exchange-httpd.h"

/**
 * Handle a "/management/auditors" request.
 *
 * @param connection the MHD connection to handle
 * @param root uploaded JSON data
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_management_auditors (
  struct MHD_Connection *connection,
  const json_t *root);


/**
 * Handle a "/management/auditors/$AUDITOR_PUB/disable" request.
 *
 * @param connection the MHD connection to handle
 * @param auditor_pub public key of the auditor to disable
 * @param root uploaded JSON data
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_management_auditors_AP_disable (
  struct MHD_Connection *connection,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const json_t *root);


/**
 * Handle a "/management/denominations/$HDP/revoke" request.
 *
 * @param connection the MHD connection to handle
 * @param h_denom_pub hash of the public key of the denomination to revoke
 * @param root uploaded JSON data
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_management_denominations_HDP_revoke (
  struct MHD_Connection *connection,
  const struct GNUNET_HashCode *h_denom_pub,
  const json_t *root);


/**
 * Handle a "/management/signkeys/$EP/revoke" request.
 *
 * @param connection the MHD connection to handle
 * @param exchange_pub exchange online signing public key to revoke
 * @param root uploaded JSON data
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_management_signkeys_EP_revoke (
  struct MHD_Connection *connection,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const json_t *root);


/**
 * Handle a POST "/management/keys" request.
 *
 * @param connection the MHD connection to handle
 * @param root uploaded JSON data
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_management_post_keys (
  struct MHD_Connection *connection,
  const json_t *root);


/**
 * Handle a "/management/wire" request.
 *
 * @param connection the MHD connection to handle
 * @param root uploaded JSON data
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_management_denominations_wire (
  struct MHD_Connection *connection,
  const json_t *root);


/**
 * Handle a "/management/wire/disable" request.
 *
 * @param connection the MHD connection to handle
 * @param root uploaded JSON data
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_management_denominations_wire_disable (
  struct MHD_Connection *connection,
  const json_t *root);


/**
 * Handle a POST "/management/wire-fees" request.
 *
 * @param connection the MHD connection to handle
 * @param root uploaded JSON data
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_management_post_wire_fees (
  struct MHD_Connection *connection,
  const json_t *root);


#endif
