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
 * @file taler-exchange-httpd_aml-decision-get.c
 * @brief Return summary information about AML decision
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
#include "taler-exchange-httpd_aml-decision.h"
#include "taler-exchange-httpd_metrics.h"


/**
 * Maximum number of records we return per request.
 */
#define MAX_RECORDS 1024

/**
 * Callback with KYC attributes about a particular user.
 *
 * @param[in,out] cls closure with a `json_t *` array to update
 * @param h_payto account for which the attribute data is stored
 * @param provider_section provider that must be checked
 * @param birthdate birthdate of user, in format YYYY-MM-DD; can be NULL;
 *        digits can be 0 if exact day, month or year are unknown
 * @param collection_time when was the data collected
 * @param expiration_time when does the data expire
 * @param enc_attributes_size number of bytes in @a enc_attributes
 * @param enc_attributes encrypted attribute data
 */
static void
kyc_attribute_cb (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const char *provider_section,
  const char *birthdate,
  struct GNUNET_TIME_Timestamp collection_time,
  struct GNUNET_TIME_Timestamp expiration_time,
  size_t enc_attributes_size,
  const void *enc_attributes)
{
  json_t *kyc_attributes = cls;
  json_t *attributes;

  attributes = TALER_CRYPTO_kyc_attributes_decrypt (&TEH_attribute_key,
                                                    enc_attributes,
                                                    enc_attributes_size);
  GNUNET_break (NULL != attributes);
  GNUNET_assert (
    0 ==
    json_array_append (
      kyc_attributes,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_string ("provider_section",
                                 provider_section),
        GNUNET_JSON_pack_timestamp ("collection_time",
                                    collection_time),
        GNUNET_JSON_pack_timestamp ("expiration_time",
                                    expiration_time),
        GNUNET_JSON_pack_allow_null (
          GNUNET_JSON_pack_object_steal ("attributes",
                                         attributes))
        )));
}


/**
 * Return historic AML decision(s).
 *
 * @param[in,out] cls closure with a `json_t *` array to update
 * @param new_threshold new monthly threshold that would trigger an AML check
 * @param new_status AML decision status
 * @param decision_time when was the decision made
 * @param justification human-readable text justifying the decision
 * @param decider_pub public key of the staff member
 * @param decider_sig signature of the staff member
 */
static void
aml_history_cb (
  void *cls,
  const struct TALER_Amount *new_threshold,
  enum TALER_AmlDecisionState new_state,
  struct GNUNET_TIME_Timestamp decision_time,
  const char *justification,
  const struct TALER_AmlOfficerPublicKeyP *decider_pub,
  const struct TALER_AmlOfficerSignatureP *decider_sig)
{
  json_t *aml_history = cls;

  GNUNET_assert (
    0 ==
    json_array_append (
      aml_history,
      GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("decider_pub",
                                    decider_pub),
        GNUNET_JSON_pack_string ("justification",
                                 justification),
        TALER_JSON_pack_amount ("new_threshold",
                                new_threshold),
        GNUNET_JSON_pack_int64 ("new_state",
                                new_state),
        GNUNET_JSON_pack_timestamp ("decision_time",
                                    decision_time)
        )));
}


MHD_RESULT
TEH_handler_aml_decision_get (
  struct TEH_RequestContext *rc,
  const struct TALER_AmlOfficerPublicKeyP *officer_pub,
  const char *const args[])
{
  struct TALER_PaytoHashP h_payto;

  if ( (NULL == args[0]) ||
       (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (args[0],
                                       strlen (args[0]),
                                       &h_payto,
                                       sizeof (h_payto))) )
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       "h_payto");
  }

  if (NULL != args[1])
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_ENDPOINT_UNKNOWN,
                                       args[1]);
  }

  {
    json_t *aml_history;
    json_t *kyc_attributes;
    enum GNUNET_DB_QueryStatus qs;
    bool none;

    aml_history = json_array ();
    GNUNET_assert (NULL != aml_history);
    qs = TEH_plugin->select_aml_history (TEH_plugin->cls,
                                         &h_payto,
                                         &aml_history_cb,
                                         aml_history);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
    case GNUNET_DB_STATUS_SOFT_ERROR:
      json_decref (aml_history);
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         NULL);
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      none = true;
      break;
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      none = false;
      break;
    }

    kyc_attributes = json_array ();
    GNUNET_assert (NULL != kyc_attributes);
    qs = TEH_plugin->select_kyc_attributes (TEH_plugin->cls,
                                            &h_payto,
                                            &kyc_attribute_cb,
                                            kyc_attributes);
    switch (qs)
    {
    case GNUNET_DB_STATUS_HARD_ERROR:
    case GNUNET_DB_STATUS_SOFT_ERROR:
      json_decref (aml_history);
      json_decref (kyc_attributes);
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_DB_FETCH_FAILED,
                                         NULL);
    case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
      if (none)
      {
        json_decref (aml_history);
        json_decref (kyc_attributes);
        return TALER_MHD_reply_static (
          rc->connection,
          MHD_HTTP_NO_CONTENT,
          NULL,
          NULL,
          0);
      }
      break;
    case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
      break;
    }
    return TALER_MHD_REPLY_JSON_PACK (
      rc->connection,
      MHD_HTTP_OK,
      GNUNET_JSON_pack_array_steal ("aml_history",
                                    aml_history),
      GNUNET_JSON_pack_array_steal ("kyc_attributes",
                                    kyc_attributes));
  }
}


/* end of taler-exchange-httpd_aml-decision_get.c */
