/*
  This file is part of TALER
  Copyright (C) 2020 Taler Systems SA

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
 * @file taler-exchange-httpd_auditors.c
 * @brief Handle request to add auditor signature on a denomination.
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
#include "taler-exchange-httpd_auditors.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Closure for the #add_auditor_denom_sig transaction.
 */
struct AddAuditorDenomContext
{
  /**
   * Auditor's signature affirming the AUDITORS XXX operation
   * (includes timestamp).
   */
  struct TALER_AuditorSignatureP auditor_sig;

  /**
   * Denomination this is about.
   */
  const struct GNUNET_HashCode *h_denom_pub;

  /**
   * Auditor this is about.
   */
  const struct TALER_AuditorPublicKeyP *auditor_pub;

};


/**
 * Function implementing database transaction to add an auditors.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction logic
 * MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct AddAuditorDenomContext`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
add_auditor_denom_sig (void *cls,
                       struct MHD_Connection *connection,
                       struct TALER_EXCHANGEDB_Session *session,
                       MHD_RESULT *mhd_ret)
{
  struct AddAuditorDenomContext *awc = cls;
  struct TALER_EXCHANGEDB_DenominationKeyMetaData meta;
  enum GNUNET_DB_QueryStatus qs;
  char *auditor_url;
  bool enabled;

  qs = TEH_plugin->lookup_denomination_key (
    TEH_plugin->cls,
    session,
    awc->h_denom_pub,
    &meta);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_FETCH_FAILED,
                                           "lookup denomination key");
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_NOT_FOUND,
      TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN,
      GNUNET_h2s (awc->h_denom_pub));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  qs = TEH_plugin->lookup_auditor_status (
    TEH_plugin->cls,
    session,
    awc->auditor_pub,
    &auditor_url,
    &enabled);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_FETCH_FAILED,
                                           "lookup auditor");
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_PRECONDITION_FAILED,
      TALER_EC_EXCHANGE_AUDITORS_AUDITOR_UNKNOWN,
      TALER_B2S (awc->auditor_pub));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! enabled)
  {
    GNUNET_free (auditor_url);
    *mhd_ret = TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_GONE,
      TALER_EC_EXCHANGE_AUDITORS_AUDITOR_INACTIVE,
      TALER_B2S (awc->auditor_pub));
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  {
    struct TALER_ExchangeKeyValidityPS kv = {
      .purpose.purpose = htonl (TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS),
      .purpose.size = htonl (sizeof (kv)),
      .master = TEH_master_public_key,
      .start = GNUNET_TIME_absolute_hton (meta.start),
      .expire_withdraw = GNUNET_TIME_absolute_hton (meta.expire_withdraw),
      .expire_deposit = GNUNET_TIME_absolute_hton (meta.expire_deposit),
      .expire_legal = GNUNET_TIME_absolute_hton (meta.expire_legal),
      .denom_hash = *awc->h_denom_pub
    };

    TALER_amount_hton (&kv.value,
                       &meta.value);
    TALER_amount_hton (&kv.fee_withdraw,
                       &meta.fee_withdraw);
    TALER_amount_hton (&kv.fee_deposit,
                       &meta.fee_deposit);
    TALER_amount_hton (&kv.fee_refresh,
                       &meta.fee_refresh);
    TALER_amount_hton (&kv.fee_refund,
                       &meta.fee_refund);
    GNUNET_CRYPTO_hash (auditor_url,
                        strlen (auditor_url) + 1,
                        &kv.auditor_url_hash);
    GNUNET_free (auditor_url);
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (
          TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS,
          &kv,
          &awc->auditor_sig.eddsa_sig,
          &TEH_master_public_key.eddsa_pub))
    {
      /* signature invalid */
      GNUNET_break_op (0);
      *mhd_ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_AUDITORS_AUDITOR_SIGNATURE_INVALID,
        NULL);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }

  qs = TEH_plugin->insert_auditor_denom_sig (TEH_plugin->cls,
                                             session,
                                             awc->h_denom_pub,
                                             awc->auditor_pub,
                                             &awc->auditor_sig);
  if (qs < 0)
  {
    GNUNET_break (0);
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_STORE_FAILED,
                                           "add auditor signature");
    return qs;
  }
  return qs;
}


MHD_RESULT
TEH_handler_auditors (
  struct MHD_Connection *connection,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct GNUNET_HashCode *h_denom_pub,
  const json_t *root)
{
  struct AddAuditorDenomContext awc = {
    .auditor_pub = auditor_pub,
    .h_denom_pub = h_denom_pub
  };
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("auditor_sig",
                                 &awc.auditor_sig),
    GNUNET_JSON_spec_end ()
  };
  enum GNUNET_DB_QueryStatus qs;
  MHD_RESULT res;

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

  qs = TEH_DB_run_transaction (connection,
                               "add auditor denom sig",
                               &res,
                               &add_auditor_denom_sig,
                               &awc);
  if (qs < 0)
    return res;
  return TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);
}


/* end of taler-exchange-httpd_auditors.c */
