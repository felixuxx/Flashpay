/*
  This file is part of TALER
  Copyright (C) 2019, 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_terms.c
 * @brief Handle /terms requests to return the terms of service
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_terms.h"

/**
 * Our terms of service.
 */
static struct TALER_MHD_Legal *tos;


/**
 * Our privacy policy.
 */
static struct TALER_MHD_Legal *pp;


MHD_RESULT
TEH_handler_terms (struct TEH_RequestContext *rc,
                   const char *const args[])
{
  (void) args;
  return TALER_MHD_reply_legal (rc->connection,
                                tos);
}


MHD_RESULT
TEH_handler_privacy (struct TEH_RequestContext *rc,
                     const char *const args[])
{
  (void) args;
  return TALER_MHD_reply_legal (rc->connection,
                                pp);
}


void
TEH_load_terms (const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  tos = TALER_MHD_legal_load (cfg,
                              "exchange",
                              "TERMS_DIR",
                              "TERMS_ETAG");
  if (NULL == tos)
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Terms of service not configured\n");
  pp = TALER_MHD_legal_load (cfg,
                             "exchange",
                             "PRIVACY_DIR",
                             "PRIVACY_ETAG");
  if (NULL == pp)
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Privacy policy not configured\n");
}


/* end of taler-exchange-httpd_terms.c */
