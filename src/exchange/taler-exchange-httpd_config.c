/*
  This file is part of TALER
  Copyright (C) 2015-2024 Taler Systems SA

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
 * @file taler-exchange-httpd_config.c
 * @brief Handle /config requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_dbevents.h"
#include "taler-exchange-httpd_config.h"
#include "taler_json_lib.h"
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include <jansson.h>


MHD_RESULT
TEH_handler_config (struct TEH_RequestContext *rc,
                    const char *const args[])
{
  static struct MHD_Response *resp;
  static struct GNUNET_TIME_Absolute a;

  (void) args;
  if ( (GNUNET_TIME_absolute_is_past (a)) &&
       (NULL != resp) )
  {
    MHD_destroy_response (resp);
    resp = NULL;
  }
  if (NULL == resp)
  {
    struct GNUNET_TIME_Timestamp km;
    char dat[128];

    a = GNUNET_TIME_relative_to_absolute (GNUNET_TIME_UNIT_DAYS);
    /* Round up to next full day to ensure the expiration
       time does not become a fingerprint! */
    a = GNUNET_TIME_absolute_round_down (a,
                                         GNUNET_TIME_UNIT_DAYS);
    a = GNUNET_TIME_absolute_add (a,
                                  GNUNET_TIME_UNIT_DAYS);
    /* => /config response stays at most 48h in caches! */
    km = GNUNET_TIME_absolute_to_timestamp (a);
    TALER_MHD_get_date_string (km.abs_time,
                               dat);
    resp = TALER_MHD_MAKE_JSON_PACK (
      GNUNET_JSON_pack_array_steal ("supported_kyc_requirements",
                                    TALER_KYCLOGIC_get_satisfiable ()),
      GNUNET_JSON_pack_object_steal (
        "currency_specification",
        TALER_CONFIG_currency_specs_to_json (TEH_cspec)),
      GNUNET_JSON_pack_string ("currency",
                               TEH_currency),
      GNUNET_JSON_pack_string ("name",
                               "taler-exchange"),
      GNUNET_JSON_pack_string ("implementation",
                               "urn:net:taler:specs:taler-exchange:c-reference")
      ,
      GNUNET_JSON_pack_string ("version",
                               EXCHANGE_PROTOCOL_VERSION));

    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (resp,
                                           MHD_HTTP_HEADER_EXPIRES,
                                           dat));
    GNUNET_break (MHD_YES ==
                  MHD_add_response_header (resp,
                                           MHD_HTTP_HEADER_CACHE_CONTROL,
                                           "public,max-age=21600")); /* 6h */
  }
  return MHD_queue_response (rc->connection,
                             MHD_HTTP_OK,
                             resp);
}


/* end of taler-exchange-httpd_config.c */
