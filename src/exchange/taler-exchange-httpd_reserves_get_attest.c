/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

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
 * @file taler-exchange-httpd_reserves_get_attest.c
 * @brief Handle GET /reserves/$RESERVE_PUB/attest requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler_json_lib.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_reserves_get_attest.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Closure for #reserve_attest_transaction.
 */
struct ReserveAttestContext
{
  /**
   * Public key of the reserve the inquiry is about.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Hash of the payto URI of this reserve.
   */
  struct TALER_NormalizedPaytoHashP h_payto;

  /**
   * Available attributes.
   */
  json_t *attributes;

};


/**
 * Function called with information about all applicable
 * legitimization processes for the given user.
 *
 * @param cls our `struct ReserveAttestContext *`
 * @param h_payto account for which the attribute data is stored
 * @param provider_name provider that must be checked
 * @param collection_time when was the data collected
 * @param expiration_time when does the data expire
 * @param enc_attributes_size number of bytes in @a enc_attributes
 * @param enc_attributes encrypted attribute data
 */
static void
kyc_process_cb (void *cls,
                const struct TALER_NormalizedPaytoHashP *h_payto,
                const char *provider_name,
                struct GNUNET_TIME_Timestamp collection_time,
                struct GNUNET_TIME_Timestamp expiration_time,
                size_t enc_attributes_size,
                const void *enc_attributes)
{
  struct ReserveAttestContext *rsc = cls;
  json_t *attrs;
  json_t *val;
  const char *name;

  if (GNUNET_TIME_absolute_is_past (
        expiration_time.abs_time))
    return;
  attrs = TALER_CRYPTO_kyc_attributes_decrypt (
    &TEH_attribute_key,
    enc_attributes,
    enc_attributes_size);
  json_object_foreach (attrs, name, val)
  {
    bool duplicate = false;
    size_t idx;
    json_t *str;

    json_array_foreach (rsc->attributes, idx, str)
    {
      if (0 == strcmp (json_string_value (str),
                       name))
      {
        duplicate = true;
        break;
      }
    }
    if (duplicate)
      continue;
    GNUNET_assert (0 ==
                   json_array_append_new (rsc->attributes,
                                          json_string (name)));
  }
  json_decref (attrs);
}


MHD_RESULT
TEH_handler_reserves_get_attest (
  struct TEH_RequestContext *rc,
  const char *const args[1])
{
  struct ReserveAttestContext rsc = {
    .attributes = NULL
  };

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (
        args[0],
        strlen (args[0]),
        &rsc.reserve_pub,
        sizeof (rsc.reserve_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      rc->connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_RESERVE_PUB_MALFORMED,
      args[0]);
  }
  {
    struct TALER_NormalizedPayto payto_uri;

    payto_uri
      = TALER_reserve_make_payto (TEH_base_url,
                                  &rsc.reserve_pub);
    TALER_normalized_payto_hash (payto_uri,
                                 &rsc.h_payto);
    GNUNET_free (payto_uri.normalized_payto);
  }
  {
    enum GNUNET_DB_QueryStatus qs;

    rsc.attributes = json_array ();
    GNUNET_assert (NULL != rsc.attributes);
    qs = TEH_plugin->select_kyc_attributes (TEH_plugin->cls,
                                            &rsc.h_payto,
                                            &kyc_process_cb,
                                            &rsc);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
      GNUNET_break (0);
      json_decref (rsc.attributes);
      rsc.attributes = NULL;
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         "select_kyc_attributes");
    case GNUNET_DB_STATUS_SOFT_ERROR:
      GNUNET_break (0);
      json_decref (rsc.attributes);
      rsc.attributes = NULL;
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         "select_kyc_attributes");
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      GNUNET_break_op (0);
      json_decref (rsc.attributes);
      rsc.attributes = NULL;
      return TALER_MHD_reply_with_error (
        rc->connection,
        MHD_HTTP_NOT_FOUND,
        TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
        NULL);
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      break;
    }
  }
  return TALER_MHD_REPLY_JSON_PACK (
    rc->connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_array_steal ("details",
                                  rsc.attributes));
}


/* end of taler-exchange-httpd_reserves_get_attest.c */
