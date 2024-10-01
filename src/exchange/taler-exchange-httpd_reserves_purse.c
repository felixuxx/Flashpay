/*
  This file is part of TALER
  Copyright (C) 2022-2024 Taler Systems SA

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
 * @file taler-exchange-httpd_reserves_purse.c
 * @brief Handle /reserves/$RID/purse requests; parses the POST and JSON and
 *        verifies the coin signature before handing things off
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
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_common_kyc.h"
#include "taler-exchange-httpd_reserves_purse.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_exchangedb_lib.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Closure for #purse_transaction.
 */
struct ReservePurseContext
{

  /**
   * Kept in a DLL.
   */
  struct ReservePurseContext *next;

  /**
   * Kept in a DLL.
   */
  struct ReservePurseContext *prev;

  /**
   * Our request context.
   */
  struct TEH_RequestContext *rc;

  /**
   * Handle for legitimization check.
   */
  struct TEH_LegitimizationCheckHandle *lch;

  /**
   * Response to return. Note that the response must
   * be queued or destroyed by the callee.  NULL
   * if the legitimization check was successful and the handler should return
   * a handler-specific result.
   */
  struct MHD_Response *response;

  /**
   * Payto URI for the reserve.
   */
  char *payto_uri;

  /**
   * Public key of the account (reserve) we are creating a purse for.
   */
  union TALER_AccountPublicKeyP account_pub;

  /**
   * Signature of the reserve affirming the merge.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * Purse fee the client is willing to pay.
   */
  struct TALER_Amount purse_fee;

  /**
   * Total amount already put into the purse.
   */
  struct TALER_Amount deposit_total;

  /**
   * Merge time.
   */
  struct GNUNET_TIME_Timestamp merge_timestamp;

  /**
   * Our current time.
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * Details about an encrypted contract, if any.
   */
  struct TALER_EncryptedContract econtract;

  /**
   * Merge key for the purse.
   */
  struct TALER_PurseMergePublicKeyP merge_pub;

  /**
   * Merge affirmation by the @e merge_pub.
   */
  struct TALER_PurseMergeSignatureP merge_sig;

  /**
   * Signature of the client affiming this request.
   */
  struct TALER_PurseContractSignatureP purse_sig;

  /**
   * Fundamental details about the purse.
   */
  struct TEH_PurseDetails pd;

  /**
   * Hash of the @e payto_uri.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * KYC status of the operation.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Minimum age for deposits into this purse.
   */
  uint32_t min_age;

  /**
   * Flags for the operation.
   */
  enum TALER_WalletAccountMergeFlags flags;

  /**
   * HTTP status code for @a response, or 0
   */
  unsigned int http_status;

  /**
   * Do we lack an @e econtract?
   */
  bool no_econtract;

  /**
   * Set to true if the purse_fee was not given in the REST request.
   */
  bool no_purse_fee;

};

/**
 * Kept in a DLL.
 */
static struct ReservePurseContext *rpc_head;

/**
 * Kept in a DLL.
 */
static struct ReservePurseContext *rpc_tail;


void
TEH_reserves_purse_cleanup ()
{
  struct ReservePurseContext *rpc;

  while (NULL != (rpc = rpc_head))
  {
    GNUNET_CONTAINER_DLL_remove (rpc_head,
                                 rpc_tail,
                                 rpc);
    MHD_resume_connection (rpc->rc->connection);
  }
}


/**
 * Function called to iterate over KYC-relevant
 * transaction amounts for a particular time range.
 * Called within a database transaction, so must
 * not start a new one.
 *
 * @param cls a `struct ReservePurseContext`
 * @param limit maximum time-range for which events
 *        should be fetched (timestamp in the past)
 * @param cb function to call on each event found,
 *        events must be returned in reverse chronological
 *        order
 * @param cb_cls closure for @a cb
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
amount_iterator (void *cls,
                 struct GNUNET_TIME_Absolute limit,
                 TALER_EXCHANGEDB_KycAmountCallback cb,
                 void *cb_cls)
{
  struct ReservePurseContext *rpc = cls;
  enum GNUNET_DB_QueryStatus qs;
  enum GNUNET_GenericReturnValue ret;

  ret = cb (cb_cls,
            &rpc->pd.target_amount,
            GNUNET_TIME_absolute_get ());
  GNUNET_break (GNUNET_SYSERR != ret);
  if (GNUNET_OK != ret)
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  qs = TEH_plugin->select_merge_amounts_for_kyc_check (
    TEH_plugin->cls,
    &rpc->h_payto,
    limit,
    cb,
    cb_cls);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Got %d additional transactions for this merge and limit %llu\n",
              qs,
              (unsigned long long) limit.abs_value_us);
  GNUNET_break (qs >= 0);
  return qs;
}


/**
 * Function called with the result of a legitimization
 * check.
 *
 * @param cls closure
 * @param lcr legitimization check result
 */
static void
reserve_purse_legi_cb (
  void *cls,
  const struct TEH_LegitimizationCheckResult *lcr)
{
  struct ReservePurseContext *rpc = cls;

  rpc->lch = NULL;
  rpc->http_status = lcr->http_status;
  rpc->response = lcr->response;
  rpc->kyc = lcr->kyc;
  GNUNET_CONTAINER_DLL_remove (rpc_head,
                               rpc_tail,
                               rpc);
  MHD_resume_connection (rpc->rc->connection);
  TALER_MHD_daemon_trigger ();
}


/**
 * Execute database transaction for /reserves/$PID/purse.  Runs the transaction
 * logic; IF it returns a non-error code, the transaction logic MUST NOT queue
 * a MHD response.  IF it returns an hard error, the transaction logic MUST
 * queue a MHD response and set @a mhd_ret.  IF it returns the soft error
 * code, the function MAY be called again to retry and MUST not queue a MHD
 * response.
 *
 * @param cls a `struct ReservePurseContext`
 * @param connection MHD request context
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
purse_transaction (void *cls,
                   struct MHD_Connection *connection,
                   MHD_RESULT *mhd_ret)
{
  struct ReservePurseContext *rpc = cls;
  enum GNUNET_DB_QueryStatus qs;

  {
    bool in_conflict = true;

    /* 1) store purse */
    qs = TEH_plugin->insert_purse_request (
      TEH_plugin->cls,
      &rpc->pd.purse_pub,
      &rpc->merge_pub,
      rpc->pd.purse_expiration,
      &rpc->pd.h_contract_terms,
      rpc->min_age,
      rpc->flags,
      &rpc->purse_fee,
      &rpc->pd.target_amount,
      &rpc->purse_sig,
      &in_conflict);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      GNUNET_break (0);
      *mhd_ret =
        TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_GENERIC_DB_STORE_FAILED,
          "insert purse request");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
      return qs;
    if (in_conflict)
    {
      struct TALER_PurseMergePublicKeyP merge_pub;
      struct GNUNET_TIME_Timestamp purse_expiration;
      struct TALER_PrivateContractHashP h_contract_terms;
      struct TALER_Amount target_amount;
      struct TALER_Amount balance;
      struct TALER_PurseContractSignatureP purse_sig;
      uint32_t min_age;

      TEH_plugin->rollback (TEH_plugin->cls);
      qs = TEH_plugin->get_purse_request (
        TEH_plugin->cls,
        &rpc->pd.purse_pub,
        &merge_pub,
        &purse_expiration,
        &h_contract_terms,
        &min_age,
        &target_amount,
        &balance,
        &purse_sig);
      if (qs <= 0)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
        GNUNET_break (0 != qs);
        TALER_LOG_WARNING ("Failed to fetch purse information from database\n");
        *mhd_ret = TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_GENERIC_DB_FETCH_FAILED,
          "select purse request");
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
      *mhd_ret
        = TALER_MHD_REPLY_JSON_PACK (
            connection,
            MHD_HTTP_CONFLICT,
            TALER_JSON_pack_ec (
              TALER_EC_EXCHANGE_RESERVES_PURSE_CREATE_CONFLICTING_META_DATA),
            TALER_JSON_pack_amount ("amount",
                                    &target_amount),
            GNUNET_JSON_pack_uint64 ("min_age",
                                     min_age),
            GNUNET_JSON_pack_timestamp ("purse_expiration",
                                        purse_expiration),
            GNUNET_JSON_pack_data_auto ("purse_sig",
                                        &purse_sig),
            GNUNET_JSON_pack_data_auto ("h_contract_terms",
                                        &h_contract_terms),
            GNUNET_JSON_pack_data_auto ("merge_pub",
                                        &merge_pub));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }

  }

  /* 2) create purse with reserve (and debit reserve for purse creation!) */
  {
    bool in_conflict = true;
    bool insufficient_funds = true;
    bool no_reserve = true;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Creating purse with flags %d\n",
                rpc->flags);
    qs = TEH_plugin->do_reserve_purse (
      TEH_plugin->cls,
      &rpc->pd.purse_pub,
      &rpc->merge_sig,
      rpc->merge_timestamp,
      &rpc->reserve_sig,
      (TALER_WAMF_MODE_CREATE_FROM_PURSE_QUOTA
       == rpc->flags)
      ? NULL
      : &rpc->purse_fee,
      &rpc->account_pub.reserve_pub,
      &in_conflict,
      &no_reserve,
      &insufficient_funds);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      TALER_LOG_WARNING (
        "Failed to store purse merge information in database\n");
      *mhd_ret =
        TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_GENERIC_DB_STORE_FAILED,
          "do reserve purse");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (in_conflict)
    {
      /* same purse already merged into a different reserve!? */
      struct TALER_PurseContractPublicKeyP purse_pub;
      struct TALER_PurseMergeSignatureP merge_sig;
      struct GNUNET_TIME_Timestamp merge_timestamp;
      char *partner_url;
      struct TALER_ReservePublicKeyP reserve_pub;
      bool refunded;

      TEH_plugin->rollback (TEH_plugin->cls);
      qs = TEH_plugin->select_purse_merge (
        TEH_plugin->cls,
        &purse_pub,
        &merge_sig,
        &merge_timestamp,
        &partner_url,
        &reserve_pub,
        &refunded);
      if (qs <= 0)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
        GNUNET_break (0 != qs);
        TALER_LOG_WARNING (
          "Failed to fetch purse merge information from database\n");
        *mhd_ret = TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_GENERIC_DB_FETCH_FAILED,
          "select purse merge");
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
      if (refunded)
      {
        /* This is a bit of a strange case ... */
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Purse was already refunded\n");
        *mhd_ret = TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_GONE,
          TALER_EC_EXCHANGE_GENERIC_PURSE_EXPIRED,
          NULL);
        GNUNET_free (partner_url);
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
      *mhd_ret
        = TALER_MHD_REPLY_JSON_PACK (
            connection,
            MHD_HTTP_CONFLICT,
            TALER_JSON_pack_ec (
              TALER_EC_EXCHANGE_RESERVES_PURSE_MERGE_CONFLICTING_META_DATA),
            GNUNET_JSON_pack_string ("partner_url",
                                     NULL == partner_url
                                     ? TEH_base_url
                                     : partner_url),
            GNUNET_JSON_pack_timestamp ("merge_timestamp",
                                        merge_timestamp),
            GNUNET_JSON_pack_data_auto ("merge_sig",
                                        &merge_sig),
            GNUNET_JSON_pack_data_auto ("reserve_pub",
                                        &reserve_pub));
      GNUNET_free (partner_url);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if ( (no_reserve) &&
         ( (TALER_WAMF_MODE_CREATE_FROM_PURSE_QUOTA
            == rpc->flags) ||
           (! TALER_amount_is_zero (&rpc->purse_fee)) ) )
    {
      *mhd_ret
        = TALER_MHD_REPLY_JSON_PACK (
            connection,
            MHD_HTTP_NOT_FOUND,
            TALER_JSON_pack_ec (
              TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (insufficient_funds)
    {
      *mhd_ret
        = TALER_MHD_REPLY_JSON_PACK (
            connection,
            MHD_HTTP_CONFLICT,
            TALER_JSON_pack_ec (
              TALER_EC_EXCHANGE_RESERVES_PURSE_CREATE_INSUFFICIENT_FUNDS));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  /* 3) if present, persist contract */
  if (! rpc->no_econtract)
  {
    bool in_conflict = true;

    qs = TEH_plugin->insert_contract (TEH_plugin->cls,
                                      &rpc->pd.purse_pub,
                                      &rpc->econtract,
                                      &in_conflict);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      TALER_LOG_WARNING ("Failed to store purse information in database\n");
      *mhd_ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_DB_STORE_FAILED,
        "purse purse contract");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (in_conflict)
    {
      struct TALER_EncryptedContract econtract;
      struct GNUNET_HashCode h_econtract;

      qs = TEH_plugin->select_contract_by_purse (
        TEH_plugin->cls,
        &rpc->pd.purse_pub,
        &econtract);
      if (qs <= 0)
      {
        if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
          return qs;
        GNUNET_break (0 != qs);
        TALER_LOG_WARNING (
          "Failed to store fetch contract information from database\n");
        *mhd_ret = TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_GENERIC_DB_FETCH_FAILED,
          "select contract");
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
      GNUNET_CRYPTO_hash (econtract.econtract,
                          econtract.econtract_size,
                          &h_econtract);
      *mhd_ret
        = TALER_MHD_REPLY_JSON_PACK (
            connection,
            MHD_HTTP_CONFLICT,
            TALER_JSON_pack_ec (
              TALER_EC_EXCHANGE_PURSE_ECONTRACT_CONFLICTING_META_DATA),
            GNUNET_JSON_pack_data_auto ("h_econtract",
                                        &h_econtract),
            GNUNET_JSON_pack_data_auto ("econtract_sig",
                                        &econtract.econtract_sig),
            GNUNET_JSON_pack_data_auto ("contract_pub",
                                        &econtract.contract_pub));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  return qs;
}


/**
 * Function to clean up our rh_ctx in @a rc
 *
 * @param[in,out] rc context to clean up
 */
static void
rpc_cleaner (struct TEH_RequestContext *rc)
{
  struct ReservePurseContext *rpc = rc->rh_ctx;

  if (NULL != rpc->lch)
  {
    TEH_legitimization_check_cancel (rpc->lch);
    rpc->lch = NULL;
  }
  GNUNET_free (rpc->econtract.econtract);
  GNUNET_free (rpc->payto_uri);
  GNUNET_free (rpc);
}


MHD_RESULT
TEH_handler_reserves_purse (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *root)
{
  struct ReservePurseContext *rpc = rc->rh_ctx;
  struct MHD_Connection *connection = rc->connection;

  if (NULL == rpc)
  {
    rpc = GNUNET_new (struct ReservePurseContext);
    rc->rh_ctx = rpc;
    rc->rh_cleaner = &rpc_cleaner;
    rpc->rc = rc;
    rpc->account_pub.reserve_pub = *reserve_pub;
    rpc->exchange_timestamp
      = GNUNET_TIME_timestamp_get ();
    rpc->no_purse_fee = true;


    {
      struct GNUNET_JSON_Specification spec[] = {
        TALER_JSON_spec_amount ("purse_value",
                                TEH_currency,
                                &rpc->pd.target_amount),
        GNUNET_JSON_spec_uint32 ("min_age",
                                 &rpc->min_age),
        GNUNET_JSON_spec_mark_optional (
          TALER_JSON_spec_amount ("purse_fee",
                                  TEH_currency,
                                  &rpc->purse_fee),
          &rpc->no_purse_fee),
        GNUNET_JSON_spec_mark_optional (
          TALER_JSON_spec_econtract ("econtract",
                                     &rpc->econtract),
          &rpc->no_econtract),
        GNUNET_JSON_spec_fixed_auto ("merge_pub",
                                     &rpc->merge_pub),
        GNUNET_JSON_spec_fixed_auto ("merge_sig",
                                     &rpc->merge_sig),
        GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                     &rpc->reserve_sig),
        GNUNET_JSON_spec_fixed_auto ("purse_pub",
                                     &rpc->pd.purse_pub),
        GNUNET_JSON_spec_fixed_auto ("purse_sig",
                                     &rpc->purse_sig),
        GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                     &rpc->pd.h_contract_terms),
        GNUNET_JSON_spec_timestamp ("merge_timestamp",
                                    &rpc->merge_timestamp),
        GNUNET_JSON_spec_timestamp ("purse_expiration",
                                    &rpc->pd.purse_expiration),
        GNUNET_JSON_spec_end ()
      };

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
    }

    rpc->payto_uri
      = TALER_reserve_make_payto (TEH_base_url,
                                  &rpc->account_pub.reserve_pub);
    TALER_payto_hash (rpc->payto_uri,
                      &rpc->h_payto);
    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;


    if (GNUNET_OK !=
        TALER_wallet_purse_merge_verify (rpc->payto_uri,
                                         rpc->merge_timestamp,
                                         &rpc->pd.purse_pub,
                                         &rpc->merge_pub,
                                         &rpc->merge_sig))
    {
      MHD_RESULT ret;

      GNUNET_break_op (0);
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_RESERVES_PURSE_MERGE_SIGNATURE_INVALID,
        rpc->payto_uri);
      GNUNET_free (rpc->payto_uri);
      return ret;
    }
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (TEH_currency,
                                          &rpc->deposit_total));
    if (GNUNET_TIME_timestamp_cmp (rpc->pd.purse_expiration,
                                   <,
                                   rpc->exchange_timestamp))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_EXCHANGE_RESERVES_PURSE_EXPIRATION_BEFORE_NOW,
        NULL);
    }
    if (GNUNET_TIME_absolute_is_never (
          rpc->pd.purse_expiration.abs_time))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_EXCHANGE_RESERVES_PURSE_EXPIRATION_IS_NEVER,
        NULL);
    }

    {
      struct TEH_KeyStateHandle *keys;
      const struct TEH_GlobalFee *gf;

      keys = TEH_keys_get_state ();
      if (NULL == keys)
      {
        GNUNET_break (0);
        return TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
          NULL);
      }
      gf = TEH_keys_global_fee_by_time (keys,
                                        rpc->exchange_timestamp);
      if (NULL == gf)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                    "Cannot create purse: global fees not configured!\n");
        return TALER_MHD_reply_with_error (
          connection,
          MHD_HTTP_INTERNAL_SERVER_ERROR,
          TALER_EC_EXCHANGE_GENERIC_GLOBAL_FEES_MISSING,
          NULL);
      }
      if (rpc->no_purse_fee)
      {
        rpc->flags = TALER_WAMF_MODE_CREATE_FROM_PURSE_QUOTA;
        GNUNET_assert (GNUNET_OK ==
                       TALER_amount_set_zero (TEH_currency,
                                              &rpc->purse_fee));
      }
      else
      {
        rpc->flags = TALER_WAMF_MODE_CREATE_WITH_PURSE_FEE;
        if (-1 ==
            TALER_amount_cmp (&rpc->purse_fee,
                              &gf->fees.purse))
        {
          /* rpc->purse_fee is below gf.fees.purse! */
          GNUNET_break_op (0);
          return TALER_MHD_reply_with_error (
            connection,
            MHD_HTTP_BAD_REQUEST,
            TALER_EC_EXCHANGE_RESERVES_PURSE_FEE_TOO_LOW,
            TALER_amount2s (&gf->fees.purse));
        }
      }
    }

    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
    if (GNUNET_OK !=
        TALER_wallet_purse_create_verify (
          rpc->pd.purse_expiration,
          &rpc->pd.h_contract_terms,
          &rpc->merge_pub,
          rpc->min_age,
          &rpc->pd.target_amount,
          &rpc->pd.purse_pub,
          &rpc->purse_sig))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_PURSE_CREATE_SIGNATURE_INVALID,
        NULL);
    }
    if (GNUNET_OK !=
        TALER_wallet_account_merge_verify (
          rpc->merge_timestamp,
          &rpc->pd.purse_pub,
          rpc->pd.purse_expiration,
          &rpc->pd.h_contract_terms,
          &rpc->pd.target_amount,
          &rpc->purse_fee,
          rpc->min_age,
          rpc->flags,
          &rpc->account_pub.reserve_pub,
          &rpc->reserve_sig))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_RESERVES_RESERVE_MERGE_SIGNATURE_INVALID,
        NULL);
    }
    if ( (! rpc->no_econtract) &&
         (GNUNET_OK !=
          TALER_wallet_econtract_upload_verify (
            rpc->econtract.econtract,
            rpc->econtract.econtract_size,
            &rpc->econtract.contract_pub,
            &rpc->pd.purse_pub,
            &rpc->econtract.econtract_sig))
         )
    {
      TALER_LOG_WARNING ("Invalid signature on /reserves/$PID/purse request\n");
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_EXCHANGE_PURSE_ECONTRACT_SIGNATURE_INVALID,
                                         NULL);
    }

    rpc->lch = TEH_legitimization_check (
      &rpc->rc->async_scope_id,
      TALER_KYCLOGIC_KYC_TRIGGER_P2P_RECEIVE,
      rpc->payto_uri,
      &rpc->h_payto,
      &rpc->account_pub,
      &amount_iterator,
      rpc,
      &reserve_purse_legi_cb,
      rpc);
    GNUNET_assert (NULL != rpc->lch);
    MHD_suspend_connection (rc->connection);
    GNUNET_CONTAINER_DLL_insert (rpc_head,
                                 rpc_tail,
                                 rpc);
    return MHD_YES;
  }
  if (NULL != rpc->response)
    return MHD_queue_response (connection,
                               rpc->http_status,
                               rpc->response);
  if (! rpc->kyc.ok)
  {
    if (0 == rpc->kyc.requirement_row)
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
        "requirement row not set");
    }
    return TEH_RESPONSE_reply_kyc_required (
      connection,
      &rpc->h_payto,
      &rpc->kyc,
      false);
  }

  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "execute reserve purse",
                                TEH_MT_REQUEST_RESERVE_PURSE,
                                &mhd_ret,
                                &purse_transaction,
                                rpc))
    {
      return mhd_ret;
    }
  }

  /* generate regular response */
  {
    MHD_RESULT res;

    res = TEH_RESPONSE_reply_purse_created (
      connection,
      rpc->exchange_timestamp,
      &rpc->deposit_total,
      &rpc->pd);
    return res;
  }
}


/* end of taler-exchange-httpd_reserves_purse.c */
