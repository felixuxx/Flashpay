/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file taler-exchange-httpd_aml-attributes-get.c
 * @brief Return summary information about KYC attributes
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_signatures.h"
#include "taler-exchange-httpd.h"
#include "taler_exchangedb_plugin.h"
#include "taler-exchange-httpd_aml-attributes-get.h"
#include "taler-exchange-httpd_metrics.h"

/**
 * Maximum number of records we return in one request.
 */
#define MAX_RECORDS 1024

/**
 * Return AML account attributes.
 *
 * @param cls closure
 * @param row_id current row in kyc_attributes table
 * @param collection_time when were the attributes collected
 * @param enc_attributes_size length of @a enc_attributes
 * @param enc_attributes the encrypted collected attributes
 */
static void
detail_cb (
  void *cls,
  uint64_t row_id,
  struct GNUNET_TIME_Timestamp collection_time,
  size_t enc_attributes_size,
  const void *enc_attributes)
{
  json_t *records = cls;
  json_t *attrs;

  attrs = TALER_CRYPTO_kyc_attributes_decrypt (&TEH_attribute_key,
                                               enc_attributes,
                                               enc_attributes_size);
  if (NULL == attrs)
  {
    GNUNET_break (0);
    return;
  }
  GNUNET_assert (
    0 ==
    json_array_append (
      records,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_int64 ("rowid",
                                row_id),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_object_steal ("attributes",
                                         attrs)),
        GNUNET_JSON_pack_timestamp ("collection_time",
                                    collection_time)
        )));
}


MHD_RESULT
TEH_handler_aml_attributes_get (
  struct TEH_RequestContext *rc,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const char *const args[])
{
  int64_t limit = -20;
  uint64_t offset;
  struct TALER_PaytoHashP h_payto;

  if ( (NULL == args[0]) ||
       (NULL != args[1]) )
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      rc->connection,
      MHD_HTTP_NOT_FOUND,
      TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
      rc->url);
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &h_payto,
                                     sizeof (h_payto)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      rc->connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_PATH_SEGMENT_MALFORMED,
      "h_payto");
  }

  TALER_MHD_parse_request_snumber (rc->connection,
                                   "limit",
                                   &limit);
  if (limit > 0)
    offset = 0;
  else
    offset = INT64_MAX;
  TALER_MHD_parse_request_number (rc->connection,
                                  "offset",
                                  &offset);
  {
    json_t *details;
    enum GNUNET_DB_QueryStatus qs;

    details = json_array ();
    GNUNET_assert (NULL != details);
    if (limit > MAX_RECORDS)
      limit = MAX_RECORDS;
    if (limit < -MAX_RECORDS)
      limit = -MAX_RECORDS;
    qs = TEH_plugin->select_aml_attributes (
      TEH_plugin->cls,
      &h_payto,
      offset,
      limit,
      &detail_cb,
      details);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
    case GNUNET_DB_STATUS_SOFT_ERROR:
      json_decref (details);
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_FETCH_FAILED,
        "select_aml_attributes");
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      json_decref (details);
      return TALER_MHD_reply_static (
        rc->connection,
        MHD_HTTP_NO_CONTENT,
        NULL,
        NULL,
        0);
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      break;
    }
    return TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_array_steal ("details",
                                    details));
  }
}


/* end of taler-exchange-httpd_aml-attributes_get.c */
