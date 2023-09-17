/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file taler-exchange-httpd_coins_get.c
 * @brief Handle GET /coins/$COIN_PUB requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_mhd_lib.h"
#include "taler_json_lib.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_coins_get.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Add the headers we want to set for every /keys response.
 *
 * @param cls the key state to use
 * @param[in,out] response the response to modify
 */
static void
add_response_headers (void *cls,
                      struct MHD_Response *response)
{
  (void) cls;
  TALER_MHD_add_global_headers (response);
}


MHD_RESULT
TEH_handler_coins_get (struct TEH_RequestContext *rc,
                       const struct TALER_CoinSpendPublicKeyP *coin_pub)
{
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_EXCHANGEDB_TransactionList *tl;
  const char *etags;
  uint64_t etag = 0;

  etags = MHD_lookup_connection_value (rc->connection,
                                       MHD_HEADER_KIND,
                                       MHD_HTTP_HEADER_IF_NONE_MATCH);
  if (NULL != etags)
  {
    char dummy;
    unsigned long long ev;

    if (1 != sscanf (etags,
                     "%llu%c",
                     &ev,
                     &dummy))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Client send malformed `If-None-Match' header `%s'\n",
                  etags);
    }
    else
    {
      etag = (uint64_t) ev;
    }
  }
  qs = TEH_plugin->get_coin_transactions (TEH_plugin->cls,
                                          coin_pub,
                                          &etag,
                                          &tl);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_FETCH_FAILED,
                                       "get_coin_history");
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);   /* single-shot query should never have soft-errors */
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_SOFT_FAILURE,
                                       "get_coin_history");
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    if (0 == etag)
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_NOT_FOUND,
                                         TALER_EC_EXCHANGE_GENERIC_COIN_UNKNOWN,
                                         NULL);
    return TEH_RESPONSE_reply_not_modified (rc->connection,
                                            etags,
                                            &add_response_headers,
                                            NULL);
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    {
      json_t *history;
      char etagp[24];
      MHD_RESULT ret;
      struct MHD_Response *resp;

      GNUNET_snprintf (etagp,
                       sizeof (etagp),
                       "%llu",
                       (unsigned long long) etag);
      history = TEH_RESPONSE_compile_transaction_history (coin_pub,
                                                          tl);
      TEH_plugin->free_coin_transaction_list (TEH_plugin->cls,
                                              tl);
      tl = NULL;
      if (NULL == history)
      {
        GNUNET_break (0);
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                           "Failed to compile coin history");
      }
      resp = TALER_MHD_MAKE_JSON_PACK (
        GNUNET_JSON_pack_array_steal ("history",
                                      history));
      GNUNET_break (MHD_YES ==
                    MHD_add_response_header (resp,
                                             MHD_HTTP_HEADER_ETAG,
                                             etagp));
      ret = MHD_queue_response (rc->connection,
                                MHD_HTTP_OK,
                                resp);
      GNUNET_break (MHD_YES == ret);
      MHD_destroy_response (resp);
      return ret;
    }
  }
  GNUNET_break (0);
  return MHD_NO;
}


/* end of taler-exchange-httpd_coins_get.c */
