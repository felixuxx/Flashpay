/*
  This file is part of TALER
  Copyright (C) 2014-2022, 2024 Taler Systems SA

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
 * @file taler-exchange-httpd_reserves_attest.c
 * @brief Handle /reserves/$RESERVE_PUB/attest requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_dbevents.h"
#include "taler_kyclogic_lib.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_reserves_attest.h"
#include "taler-exchange-httpd_responses.h"


/**
 * How far do we allow a client's time to be off when
 * checking the request timestamp?
 */
#define TIMESTAMP_TOLERANCE \
        GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MINUTES, 15)


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
   * Timestamp of the request.
   */
  struct GNUNET_TIME_Timestamp timestamp;

  /**
   * Expiration time for the attestation.
   */
  struct GNUNET_TIME_Timestamp etime;

  /**
   * List of requested details.
   */
  const json_t *details;

  /**
   * Client signature approving the request.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * Attributes we are affirming. JSON object.
   */
  json_t *json_attest;

  /**
   * Database error codes encountered.
   */
  enum GNUNET_DB_QueryStatus qs;

  /**
   * Set to true if we did not find the reserve.
   */
  bool not_found;

};


/**
 * Send reserve attest to client.
 *
 * @param connection connection to the client
 * @param rhc reserve attest to return
 * @return MHD result code
 */
static MHD_RESULT
reply_reserve_attest_success (struct MHD_Connection *connection,
                              const struct ReserveAttestContext *rhc)
{
  struct TALER_ExchangeSignatureP exchange_sig;
  struct TALER_ExchangePublicKeyP exchange_pub;
  enum TALER_ErrorCode ec;
  struct GNUNET_TIME_Timestamp now;

  if (NULL == rhc->json_attest)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                       NULL);
  }
  now = GNUNET_TIME_timestamp_get ();
  ec = TALER_exchange_online_reserve_attest_details_sign (
    &TEH_keys_exchange_sign_,
    now,
    rhc->etime,
    &rhc->reserve_pub,
    rhc->json_attest,
    &exchange_pub,
    &exchange_sig);
  if (TALER_EC_NONE != ec)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_ec (connection,
                                    ec,
                                    NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &exchange_sig),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &exchange_pub),
    GNUNET_JSON_pack_timestamp ("exchange_timestamp",
                                now),
    GNUNET_JSON_pack_timestamp ("expiration_time",
                                rhc->etime),
    GNUNET_JSON_pack_object_steal ("attributes",
                                   rhc->json_attest));
}


/**
 * Function called with information about all applicable
 * legitimization processes for the given user.  Finds the
 * available attributes and merges them into our result
 * set based on the details requested by the client.
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
  bool match = false;

  if (GNUNET_TIME_absolute_is_past (expiration_time.abs_time))
    return;
  attrs = TALER_CRYPTO_kyc_attributes_decrypt (&TEH_attribute_key,
                                               enc_attributes,
                                               enc_attributes_size);
  if (NULL == attrs)
  {
    GNUNET_break (0);
    return;
  }
  json_object_foreach (attrs, name, val)
  {
    bool requested = false;
    size_t idx;
    json_t *str;

    if (NULL != json_object_get (rsc->json_attest,
                                 name))
      continue;   /* duplicate */
    json_array_foreach (rsc->details, idx, str)
    {
      if (0 == strcmp (json_string_value (str),
                       name))
      {
        requested = true;
        break;
      }
    }
    if (! requested)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Skipping attribute `%s': not requested\n",
                  name);
      continue;
    }
    match = true;
    GNUNET_assert (0 ==
                   json_object_set (rsc->json_attest,   /* NOT set_new! */
                                    name,
                                    val));
  }
  json_decref (attrs);
  if (! match)
    return;
  rsc->etime = GNUNET_TIME_timestamp_min (expiration_time,
                                          rsc->etime);
}


/**
 * Function implementing /reserves/$RID/attest transaction.  Given the public
 * key of a reserve, return the associated transaction attest.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction logic
 * MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls a `struct ReserveAttestContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!); unused
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserve_attest_transaction (void *cls,
                            struct MHD_Connection *connection,
                            MHD_RESULT *mhd_ret)
{
  struct ReserveAttestContext *rsc = cls;
  enum GNUNET_DB_QueryStatus qs;

  rsc->json_attest = json_object ();
  GNUNET_assert (NULL != rsc->json_attest);
  qs = TEH_plugin->select_kyc_attributes (TEH_plugin->cls,
                                          &rsc->h_payto,
                                          &kyc_process_cb,
                                          rsc);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    *mhd_ret
      = TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_INTERNAL_SERVER_ERROR,
                                    TALER_EC_GENERIC_DB_FETCH_FAILED,
                                    "select_kyc_attributes");
    return qs;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    return qs;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    rsc->not_found = true;
    return qs;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    rsc->not_found = false;
    break;
  }
  return qs;
}


MHD_RESULT
TEH_handler_reserves_attest (struct TEH_RequestContext *rc,
                             const json_t *root,
                             const char *const args[1])
{
  struct ReserveAttestContext rsc = {
    .etime = GNUNET_TIME_UNIT_FOREVER_TS
  };
  MHD_RESULT mhd_ret;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_timestamp ("request_timestamp",
                                &rsc.timestamp),
    GNUNET_JSON_spec_array_const ("details",
                                  &rsc.details),
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &rsc.reserve_sig),
    GNUNET_JSON_spec_end ()
  };
  struct GNUNET_TIME_Timestamp now;

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &rsc.reserve_pub,
                                     sizeof (rsc.reserve_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_RESERVE_PUB_MALFORMED,
                                       args[0]);
  }
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (rc->connection,
                                     root,
                                     spec);
    if (GNUNET_SYSERR == res)
    {
      GNUNET_break (0);
      return MHD_NO; /* hard failure */
    }
    if (GNUNET_NO == res)
    {
      GNUNET_break_op (0);
      return MHD_YES; /* failure */
    }
  }
  now = GNUNET_TIME_timestamp_get ();
  if (! GNUNET_TIME_absolute_approx_eq (now.abs_time,
                                        rsc.timestamp.abs_time,
                                        TIMESTAMP_TOLERANCE))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_GENERIC_CLOCK_SKEW,
                                       NULL);
  }

  if (GNUNET_OK !=
      TALER_wallet_reserve_attest_request_verify (rsc.timestamp,
                                                  rsc.details,
                                                  &rsc.reserve_pub,
                                                  &rsc.reserve_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_RESERVES_ATTEST_BAD_SIGNATURE,
                                       NULL);
  }

  {
    struct TALER_NormalizedPayto payto_uri;

    payto_uri = TALER_reserve_make_payto (TEH_base_url,
                                          &rsc.reserve_pub);
    TALER_normalized_payto_hash (payto_uri,
                                 &rsc.h_payto);
    GNUNET_free (payto_uri.normalized_payto);
  }

  if (GNUNET_OK !=
      TEH_DB_run_transaction (rc->connection,
                              "post reserve attest",
                              TEH_MT_REQUEST_OTHER,
                              &mhd_ret,
                              &reserve_attest_transaction,
                              &rsc))
  {
    return mhd_ret;
  }
  if (rsc.not_found)
  {
    json_decref (rsc.json_attest);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
                                       args[0]);
  }
  return reply_reserve_attest_success (rc->connection,
                                       &rsc);
}


/* end of taler-exchange-httpd_reserves_attest.c */
