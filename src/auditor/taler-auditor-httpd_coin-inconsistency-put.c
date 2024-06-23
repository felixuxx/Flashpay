/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
 */


#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-auditor-httpd.h"
#include "taler-auditor-httpd_coin-inconsistency-put.h"

/**
 * We have parsed the JSON information about the deposit, do some
 * basic sanity checks (especially that the signature on the coin is
 * valid, and that this type of coin exists) and then execute the
 * deposit.
 *
 * @param connection the MHD connection to handle
 * @param dc information about the deposit confirmation
 * @param es information about the exchange's signing key
 * @return MHD result code
 */
static MHD_RESULT
process_inconsistency (
  struct MHD_Connection *connection,
  const struct TALER_AUDITORDB_CoinInconsistency *dc)
{

  enum GNUNET_DB_QueryStatus qs;

  if (GNUNET_SYSERR ==
      TAH_plugin->preflight (TAH_plugin->cls))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_SETUP_FAILED,
                                       NULL);
  }

  /* execute transaction */
  qs = TAH_plugin->insert_coin_inconsistency (TAH_plugin->cls,
                                              dc);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    TALER_LOG_WARNING (
      "Failed to store /insert-coin in database\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_STORE_FAILED,
                                       "insert coin");
  }
  return TALER_MHD_REPLY_JSON_PACK (connection,
                                    MHD_HTTP_OK,
                                    GNUNET_JSON_pack_string ("status",
                                                             "INSERT_COIN_OK"));
}


MHD_RESULT
TAH_COIN_INCONSISTENCY_PUT_handler (
  struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size,
  const char *const args[])
{

  struct TALER_AUDITORDB_CoinInconsistency dc;

  struct GNUNET_JSON_Specification spec[] = {

    GNUNET_JSON_spec_string ("operation", (const char **) &dc.operation),
    TALER_JSON_spec_amount ("exchange_amount", TAH_currency,
                            &dc.exchange_amount),
    TALER_JSON_spec_amount ("auditor_amount", TAH_currency,&dc.auditor_amount),
    GNUNET_JSON_spec_fixed_auto ("coin_pub", &dc.coin_pub),
    GNUNET_JSON_spec_bool ("profitable", &dc.profitable),

    GNUNET_JSON_spec_end ()
  };

  json_t *json;

  (void) rh;
  (void) connection_cls;
  (void) upload_data;
  (void) upload_data_size;
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_post_json (connection,
                                     connection_cls,
                                     upload_data,
                                     upload_data_size,
                                     &json);
    if (GNUNET_SYSERR == res)
      return MHD_NO;
    if ((GNUNET_NO == res) ||
        (NULL == json))
      return MHD_YES;
    res = TALER_MHD_parse_json_data (connection,
                                     json,
                                     spec);
    if (GNUNET_SYSERR == res)
    {
      json_decref (json);
      return MHD_NO;             /* hard failure */
    }
    if (GNUNET_NO == res)
    {
      json_decref (json);
      return MHD_YES;             /* failure */
    }
  }

  MHD_RESULT res;

  res = process_inconsistency (connection, &dc);

  GNUNET_JSON_parse_free (spec);
  json_decref (json);
  return res;

}


void
TEAH_COIN_INCONSISTENCY_PUT_init (void)
{

}


void
TEAH_COIN_INCONSISTENCY_PUT_done (void)
{

}