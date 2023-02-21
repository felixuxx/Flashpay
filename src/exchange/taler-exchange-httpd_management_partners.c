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
 * @file taler-exchange-httpd_management_partners.c
 * @brief Handle request to add exchange partner
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_signatures.h"
#include "taler-exchange-httpd_management.h"
#include "taler-exchange-httpd_responses.h"


MHD_RESULT
TEH_handler_management_partners (
  struct MHD_Connection *connection,
  const json_t *root)
{
  struct TALER_MasterPublicKeyP partner_pub;
  struct GNUNET_TIME_Timestamp start_date;
  struct GNUNET_TIME_Timestamp end_date;
  struct GNUNET_TIME_Relative wad_frequency;
  struct TALER_Amount wad_fee;
  const char *partner_base_url;
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("partner_pub",
                                 &partner_pub),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &master_sig),
    GNUNET_JSON_spec_string ("partner_base_url",
                             &partner_base_url),
    TALER_JSON_spec_amount ("wad_fee",
                            TEH_currency,
                            &wad_fee),
    GNUNET_JSON_spec_timestamp ("start_date",
                                &start_date),
    GNUNET_JSON_spec_timestamp ("end_date",
                                &end_date),
    GNUNET_JSON_spec_relative_time ("wad_frequency",
                                    &wad_frequency),
    GNUNET_JSON_spec_end ()
  };

  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
                                     root,
                                     spec);
    if (GNUNET_SYSERR == res)
      return MHD_NO; /* hard failure */
    if (GNUNET_NO == res)
      return MHD_YES; /* failure */
  }
  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_exchange_offline_partner_details_verify (
        &partner_pub,
        start_date,
        end_date,
        wad_frequency,
        &wad_fee,
        partner_base_url,
        &TEH_master_public_key,
        &master_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_MANAGEMENT_ADD_PARTNER_SIGNATURE_INVALID,
      NULL);
  }
  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->insert_partner (TEH_plugin->cls,
                                     &partner_pub,
                                     start_date,
                                     end_date,
                                     wad_frequency,
                                     &wad_fee,
                                     partner_base_url,
                                     &master_sig);
    if (qs < 0)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_STORE_FAILED,
                                         "add_partner");
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      /* FIXME: check for idempotency! */
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_CONFLICT,
                                         TALER_EC_EXCHANGE_MANAGEMENT_ADD_PARTNER_DATA_CONFLICT,
                                         NULL);
    }
  }
  return TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}


/* end of taler-exchange-httpd_management_partners.c */
