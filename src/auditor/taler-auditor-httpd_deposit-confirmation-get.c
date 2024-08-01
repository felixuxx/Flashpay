/*
  This file is part of TALER
  Copyright (C) 2014-2024 Taler Systems SA

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
 * @file taler-auditor-httpd_deposit-confirmation-get.c
 * @brief Handle /deposit-confirmation requests; return list of deposit confirmations from merchant
 * that were not received from the exchange, by auditor.
 * @author Nic Eigel
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
#include "taler-auditor-httpd_deposit-confirmation-get.h"

/**
 * Add deposit confirmation to the list.
 *
 * @param[in,out] cls a `json_t *` array to extend
 * @param serial_id location of the @a dc in the database
 * @param dc struct of deposit confirmation
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop iterating
 */
static enum GNUNET_GenericReturnValue
add_deposit_confirmation (
  void *cls,
  uint64_t serial_id,
  const struct TALER_AUDITORDB_DepositConfirmation *dc)
{
  json_t *list = cls;
  json_t *obj;

  json_t *coin_pubs_json = json_array ();
  json_t *coin_sigs_json = json_array ();

  for (int i = 0; dc->num_coins > i; i++)
  {

    int sz_pub = sizeof(dc->coin_pubs[0]) * 9;
    char *o_pub = malloc (sz_pub);
    GNUNET_STRINGS_data_to_string (&dc->coin_pubs[i], sizeof(dc->coin_pubs[0]),
                                   o_pub, sz_pub);
    json_t *pub = json_string (o_pub);
    json_array_append_new (coin_pubs_json, pub);
    free (o_pub);


    int sz_sig = sizeof(dc->coin_sigs[0]) * 9;
    char *o_sig = malloc (sz_sig);
    GNUNET_STRINGS_data_to_string (&dc->coin_sigs[i], sizeof(dc->coin_sigs[0]),
                                   o_sig, sz_sig);
    json_t *sig = json_string (o_sig);
    json_array_append_new (coin_sigs_json, sig);
    free (o_sig);

  }

  obj = GNUNET_JSON_PACK (

    GNUNET_JSON_pack_int64 ("deposit_confirmation_serial_id", serial_id),
    GNUNET_JSON_pack_data_auto ("h_contract_terms", &dc->h_contract_terms),
    GNUNET_JSON_pack_data_auto ("h_policy", &dc->h_policy),
    GNUNET_JSON_pack_data_auto ("h_wire", &dc->h_wire),
    GNUNET_JSON_pack_timestamp ("exchange_timestamp", dc->exchange_timestamp),
    GNUNET_JSON_pack_timestamp ("refund_deadline", dc->refund_deadline),
    GNUNET_JSON_pack_timestamp ("wire_deadline", dc->wire_deadline),
    TALER_JSON_pack_amount ("total_without_fee", &dc->total_without_fee),

    GNUNET_JSON_pack_array_steal ("coin_pubs", coin_pubs_json),
    GNUNET_JSON_pack_array_steal ("coin_sigs", coin_sigs_json),

    GNUNET_JSON_pack_data_auto ("merchant_pub", &dc->merchant),
    GNUNET_JSON_pack_data_auto ("exchange_sig", &dc->exchange_sig),
    GNUNET_JSON_pack_data_auto ("exchange_pub", &dc->exchange_pub),
    GNUNET_JSON_pack_data_auto ("master_sig", &dc->master_sig)

    );

  GNUNET_break (0 ==
                json_array_append_new (list,
                                       obj));
  return GNUNET_OK;
}


MHD_RESULT
TAH_DEPOSIT_CONFIRMATION_handler_get (
  struct TAH_RequestHandler *rh,
  struct MHD_Connection *connection,
  void **connection_cls,
  const char *upload_data,
  size_t *upload_data_size,
  const char *const args[])
{
  json_t *ja;
  enum GNUNET_DB_QueryStatus qs;

  (void) rh;
  (void) connection_cls;
  (void) upload_data;
  (void) upload_data_size;
  if (GNUNET_SYSERR ==
      TAH_plugin->preflight (TAH_plugin->cls))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_SETUP_FAILED,
                                       NULL);
  }
  ja = json_array ();
  GNUNET_break (NULL != ja);

  bool return_suppressed = false;

  int64_t limit = -20;   // unused here
  uint64_t offset;

  TALER_MHD_parse_request_snumber (connection,
                                   "limit",
                                   &limit);

  if (limit < 0)
    offset = INT64_MAX;
  else
    offset = 0;

  TALER_MHD_parse_request_number (connection,
                                  "offset",
                                  &offset);


  const char *ret_s = MHD_lookup_connection_value (connection,
                                                   MHD_GET_ARGUMENT_KIND,
                                                   "return_suppressed");
  if (ret_s != NULL && strcmp (ret_s, "true") == 0)
  {
    return_suppressed = true;
  }

  qs = TAH_plugin->get_deposit_confirmations (
    TAH_plugin->cls,
    limit,
    offset,
    return_suppressed,
    &add_deposit_confirmation,
    ja);

  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
    json_decref (ja);
    TALER_LOG_WARNING (
      "Failed to handle GET /deposit-confirmation in database\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_FETCH_FAILED,
                                       "deposit-confirmation");
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_array_steal ("deposit_confirmation",
                                  ja));
}


/* end of taler-auditor-httpd_deposit-confirmation-get.c */
