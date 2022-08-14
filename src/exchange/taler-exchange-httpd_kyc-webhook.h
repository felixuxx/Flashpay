/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_kyc-webhook.h
 * @brief Handle /kyc-webhook requests
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_KYC_WEBHOOK_H
#define TALER_EXCHANGE_HTTPD_KYC_WEBHOOK_H

#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Shutdown kyc-webhook subsystem.  Resumes all suspended long-polling clients
 * and cleans up data structures.
 */
void
TEH_kyc_webhook_cleanup (void);


/**
 * Handle a GET "/kyc-webhook" request.
 *
 * @param rc request to handle
 * @param args one argument with the legitimization_uuid
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_kyc_webhook_get (
  struct TEH_RequestContext *rc,
  const char *const args[]);


/**
 * Handle a POST "/kyc-webhook" request.
 *
 * @param rc request to handle
 * @param root uploaded JSON body
 * @param args one argument with the legitimization_uuid
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_kyc_webhook_post (
  struct TEH_RequestContext *rc,
  const json_t *root,
  const char *const args[]);


#endif
