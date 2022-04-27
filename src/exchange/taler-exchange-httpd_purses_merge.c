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
 * @file taler-exchange-httpd_purses_merge.c
 * @brief Handle /purses/$PID/merge requests; parses the POST and JSON and
 *        verifies the reserve signature before handing things off
 *        to the database.
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
#include "taler-exchange-httpd_purses_merge.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_exchangedb_lib.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_wire.h"


/**
 * Closure for #merge_transaction.
 */
struct PurseMergeContext
{
  /**
   * Public key of the purse we are creating.
   */
  const struct TALER_PurseContractPublicKeyP *purse_pub;

  /**
   * Total amount to be put into the purse.
   */
  struct TALER_Amount target_amount;

  /**
   * Current amount in the purse.
   */
  struct TALER_Amount balance;

  /**
   * When should the purse expire.
   */
  struct GNUNET_TIME_Timestamp purse_expiration;

  /**
   * When the client signed the merge.
   */
  struct GNUNET_TIME_Timestamp merge_timestamp;

  /**
   * Our current time.
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * Merge key for the purse.
   */
  struct TALER_PurseMergePublicKeyP merge_pub;

  /**
   * Signature of the reservce affiming this request.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * Signature of the client affiming the merge.
   */
  struct TALER_PurseMergeSignatureP merge_sig;

  /**
   * Public key of the reserve, as extracted from @e payto_uri.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Hash of the contract terms of the purse.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Fees that apply to this operation.
   */
  const struct TALER_WireFeeSet *wf;

  /**
   * URI of the account the purse is to be merged into.
   * Must be of the form 'payto://taler/$EXCHANGE_URL/RESERVE_PUB'.
   */
  const char *payto_uri;

  /**
   * Base URL of the exchange provider hosting the reserve.
   */
  char *provider_url;

  /**
   * Minimum age for deposits into this purse.
   */
  uint32_t min_age;
};


/**
 * Send confirmation of purse creation success to client.
 *
 * @param connection connection to the client
 * @param pcc details about the request that succeeded
 * @return MHD result code
 */
static MHD_RESULT
reply_merge_success (struct MHD_Connection *connection,
                     const struct PurseMergeContext *pcc)
{
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  enum TALER_ErrorCode ec;
  struct TALER_Amount merge_amount;

  if (0 <
      TALER_amount_cmp (&pcc->balance,
                        &pcc->target_amount))
  {
    return TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_ACCEPTED,
      TALER_JSON_pack_amount ("balance",
                              &pcc->balance));
  }
  if ( (NULL == pcc->provider_url) ||
       (0 == strcmp (pcc->provider_url,
                     TEH_base_url)) )
  {
    /* wad fee is always zero if we stay at our own exchange */
    merge_amount = pcc->target_amount;
  }
  else
  {
    if (0 >
        TALER_amount_subtract (&merge_amount,
                               &pcc->target_amount,
                               &pcc->wf->wad))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Purse merged, balance of %s benefits exchange as it is below wad fee.\n",
                  TALER_amount2s (&pcc->target_amount));
      return TALER_MHD_reply_with_ec (
        connection,
        TALER_EC_EXCHANGE_PURSE_MERGE_WAD_FEE_EXCEEDS_PURSE_VALUE,
        TALER_amount2s (&pcc->wf->wad));
    }
  }
  if (TALER_EC_NONE !=
      (ec = TALER_exchange_online_purse_merged_sign (
         &TEH_keys_exchange_sign_,
         pcc->exchange_timestamp,
         pcc->purse_expiration,
         &merge_amount,
         pcc->purse_pub,
         &pcc->h_contract_terms,
         &pcc->reserve_pub,
         (NULL != pcc->provider_url)
         ? pcc->provider_url
         : TEH_base_url,
         &pub,
         &sig)))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_ec (connection,
                                    ec,
                                    NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    TALER_JSON_pack_amount ("merge_amount",
                            &merge_amount),
    GNUNET_JSON_pack_timestamp ("exchange_timestamp",
                                pcc->exchange_timestamp),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &sig),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &pub));
}


/**
 * Execute database transaction for /purses/$PID/merge.  Runs the transaction
 * logic; IF it returns a non-error code, the transaction logic MUST NOT queue
 * a MHD response.  IF it returns an hard error, the transaction logic MUST
 * queue a MHD response and set @a mhd_ret.  IF it returns the soft error
 * code, the function MAY be called again to retry and MUST not queue a MHD
 * response.
 *
 * @param cls a `struct PurseMergeContext`
 * @param connection MHD request context
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
merge_transaction (void *cls,
                   struct MHD_Connection *connection,
                   MHD_RESULT *mhd_ret)
{
  struct PurseMergeContext *pcc = cls;
  enum GNUNET_DB_QueryStatus qs;
  bool in_conflict = true;
  bool no_balance = true;
  bool no_partner = true;

  qs = TEH_plugin->do_purse_merge (TEH_plugin->cls,
                                   pcc->purse_pub,
                                   &pcc->merge_sig,
                                   pcc->merge_timestamp,
                                   &pcc->reserve_sig,
                                   pcc->provider_url,
                                   &pcc->reserve_pub,
                                   &no_partner,
                                   &no_balance,
                                   &in_conflict);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    TALER_LOG_WARNING (
      "Failed to store merge purse information in database\n");
    *mhd_ret =
      TALER_MHD_reply_with_error (connection,
                                  MHD_HTTP_INTERNAL_SERVER_ERROR,
                                  TALER_EC_GENERIC_DB_STORE_FAILED,
                                  "purse merge");
    return qs;
  }
  if (no_partner)
  {
    *mhd_ret =
      TALER_MHD_reply_with_error (connection,
                                  MHD_HTTP_BAD_REQUEST,
                                  TALER_EC_EXCHANGE_MERGE_PURSE_PARTNER_UNKNOWN,
                                  pcc->provider_url);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (no_balance)
  {
    *mhd_ret =
      TALER_MHD_reply_with_error (connection,
                                  MHD_HTTP_CONFLICT,
                                  TALER_EC_EXCHANGE_PURSE_NOT_FULL,
                                  NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (in_conflict)
  {
    struct TALER_PurseMergeSignatureP merge_sig;
    struct GNUNET_TIME_Timestamp merge_timestamp;
    char *partner_url = NULL;
    struct TALER_ReservePublicKeyP reserve_pub;

    qs = TEH_plugin->select_purse_merge (TEH_plugin->cls,
                                         pcc->purse_pub,
                                         &merge_sig,
                                         &merge_timestamp,
                                         &partner_url,
                                         &reserve_pub);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      TALER_LOG_WARNING (
        "Failed to fetch merge purse information from database\n");
      *mhd_ret =
        TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_INTERNAL_SERVER_ERROR,
                                    TALER_EC_GENERIC_DB_FETCH_FAILED,
                                    "select purse merge");
      return qs;
    }
    *mhd_ret = TALER_MHD_REPLY_JSON_PACK (
      connection,
      MHD_HTTP_CONFLICT,
      GNUNET_JSON_pack_timestamp ("merge_timestamp",
                                  merge_timestamp),
      GNUNET_JSON_pack_data_auto ("merge_sig",
                                  &merge_sig),
      GNUNET_JSON_pack_allow_null (
        GNUNET_JSON_pack_string ("partner_base_url",
                                 partner_url)),
      GNUNET_JSON_pack_data_auto ("reserve_pub",
                                  &reserve_pub));
    GNUNET_free (partner_url);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}


MHD_RESULT
TEH_handler_purses_merge (
  struct MHD_Connection *connection,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const json_t *root)
{
  struct PurseMergeContext pcc = {
    .purse_pub = purse_pub,
    .exchange_timestamp = GNUNET_TIME_timestamp_get ()
  };
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("payto_uri",
                             &pcc.payto_uri),
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &pcc.reserve_sig),
    GNUNET_JSON_spec_fixed_auto ("merge_sig",
                                 &pcc.merge_sig),
    GNUNET_JSON_spec_timestamp ("merge_timestamp",
                                &pcc.merge_timestamp),
    GNUNET_JSON_spec_end ()
  };
  struct TALER_PurseContractSignatureP purse_sig;
  enum GNUNET_DB_QueryStatus qs;
  bool http;

  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
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

  /* Fetch purse details */
  qs = TEH_plugin->select_purse_request (TEH_plugin->cls,
                                         pcc.purse_pub,
                                         &pcc.merge_pub,
                                         &pcc.purse_expiration,
                                         &pcc.h_contract_terms,
                                         &pcc.min_age,
                                         &pcc.target_amount,
                                         &pcc.balance,
                                         &purse_sig);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_INTERNAL_SERVER_ERROR,
      TALER_EC_GENERIC_DB_FETCH_FAILED,
      "select purse request");
  case GNUNET_DB_STATUS_SOFT_ERROR:
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_INTERNAL_SERVER_ERROR,
      TALER_EC_GENERIC_DB_FETCH_FAILED,
      "select purse request");
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_NOT_FOUND,
      TALER_EC_EXCHANGE_GENERIC_PURSE_UNKNOWN,
      NULL);
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    /* continued below */
    break;
  }
  /* parse 'payto_uri' into pcc.reserve_pub and provider_url */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received payto: `%s'\n",
              pcc.payto_uri);
  if ( (0 != strncmp (pcc.payto_uri,
                      "payto://taler/",
                      strlen ("payto://taler/"))) &&
       (0 != strncmp (pcc.payto_uri,
                      "payto://taler+http/",
                      strlen ("payto://taler+http/"))) )
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      "payto_uri");
  }

  http = (0 == strncmp (pcc.payto_uri,
                        "payto://taler+http/",
                        strlen ("payto://taler+http/")));

  {
    const char *host = &pcc.payto_uri[http
                                      ? strlen ("payto://taler+http/")
                                      : strlen ("payto://taler/")];
    const char *slash = strchr (host,
                                '/');

    if (NULL == slash)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "payto_uri");
    }
    GNUNET_asprintf (&pcc.provider_url,
                     "%s://%.*s/",
                     http ? "http" : "https",
                     (int) (slash - host),
                     host);
    slash++;
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (slash,
                                       strlen (slash),
                                       &pcc.reserve_pub,
                                       sizeof (pcc.reserve_pub)))
    {
      GNUNET_break_op (0);
      GNUNET_free (pcc.provider_url);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "payto_uri");
    }
    slash++;
  }
  if (0 == strcmp (pcc.provider_url,
                   TEH_base_url))
  {
    /* we use NULL to represent 'self' as the provider */
    GNUNET_free (pcc.provider_url);
  }
  else
  {
    char *method = GNUNET_strdup ("FIXME-WAD");

    /* FIXME: lookup wire method by pcc.provider_url! */
    pcc.wf = TEH_wire_fees_by_time (pcc.exchange_timestamp,
                                    method);
    if (NULL == pcc.wf)
    {
      MHD_RESULT res;

      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Cannot merge purse: wire fees not configured!\n");
      res = TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_INTERNAL_SERVER_ERROR,
                                        TALER_EC_EXCHANGE_GENERIC_WIRE_FEES_MISSING,
                                        method);
      GNUNET_free (method);
      return res;
    }
    GNUNET_free (method);
  }
  /* check signatures */
  if (GNUNET_OK !=
      TALER_wallet_purse_merge_verify (
        pcc.payto_uri,
        pcc.merge_timestamp,
        pcc.purse_pub,
        &pcc.merge_pub,
        &pcc.merge_sig))
  {
    GNUNET_break_op (0);
    GNUNET_free (pcc.provider_url);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_EXCHANGE_PURSE_MERGE_INVALID_MERGE_SIGNATURE,
      NULL);
  }
  if (GNUNET_OK !=
      TALER_wallet_account_merge_verify (
        pcc.merge_timestamp,
        pcc.purse_pub,
        pcc.purse_expiration,
        &pcc.h_contract_terms,
        &pcc.target_amount,
        pcc.min_age,
        &pcc.reserve_pub,
        &pcc.reserve_sig))
  {
    GNUNET_break_op (0);
    GNUNET_free (pcc.provider_url);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_EXCHANGE_PURSE_MERGE_INVALID_RESERVE_SIGNATURE,
      NULL);
  }

  /* execute transaction */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "execute purse merge",
                                TEH_MT_REQUEST_PURSE_MERGE,
                                &mhd_ret,
                                &merge_transaction,
                                &pcc))
    {
      GNUNET_free (pcc.provider_url);
      return mhd_ret;
    }
  }

  GNUNET_free (pcc.provider_url);
  /* generate regular response */
  return reply_merge_success (connection,
                              &pcc);
}


/* end of taler-exchange-httpd_purses_merge.c */
