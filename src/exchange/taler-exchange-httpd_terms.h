/*
  This file is part of TALER
  Copyright (C) 2019 Taler Systems SA

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
 * @file taler-exchange-httpd_terms.h
 * @brief Handle /terms requests to return the terms of service
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_TERMS_H
#define TALER_EXCHANGE_HTTPD_TERMS_H
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Handle a "/terms" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (must be empty for this function)
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_terms (const struct TEH_RequestHandler *rh,
                   struct MHD_Connection *connection,
                   const char *const args[]);


/**
 * Handle a "/privacy" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (must be empty for this function)
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_privacy (const struct TEH_RequestHandler *rh,
                     struct MHD_Connection *connection,
                     const char *const args[]);


/**
 * Load our terms of service as per configuration.
 *
 * @param cfg configuration to process
 */
void
TEH_load_terms (const struct GNUNET_CONFIGURATION_Handle *cfg);


#endif
