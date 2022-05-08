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
#include "taler_mhd_lib.h"
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
   * Public key of the reserve we are creating a purse for.
   */
  const struct TALER_ReservePublicKeyP *reserve_pub;

  /**
   * Fees for the operation.
   */
  const struct TEH_GlobalFee *gf;

  /**
   * Signature of the reserve affirming the merge.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * Total amount to be put into the purse.
   */
  struct TALER_Amount amount;

  /**
   * Purse fee the client is willing to pay.
   */
  struct TALER_Amount purse_fee;

  /**
   * Total amount already put into the purse.
   */
  struct TALER_Amount deposit_total;

  /**
   * When should the purse expire.
   */
  struct GNUNET_TIME_Timestamp purse_expiration;

  /**
   * Merge time.
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
   * Merge affirmation by the @e merge_pub.
   */
  struct TALER_PurseMergeSignatureP merge_sig;

  /**
   * Contract decryption key for the purse.
   */
  struct TALER_ContractDiffiePublicP contract_pub;

  /**
   * Public key of the purse we are creating.
   */
  struct TALER_PurseContractPublicKeyP purse_pub;

  /**
   * Signature of the client affiming this request.
   */
  struct TALER_PurseContractSignatureP purse_sig;

  /**
   * Signature of the client affiming this encrypted contract.
   */
  struct TALER_PurseContractSignatureP econtract_sig;

  /**
   * Hash of the contract terms of the purse.
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Encrypted contract, can be NULL.
   */
  void *econtract;

  /**
   * Number of bytes in @e econtract.
   */
  size_t econtract_size;

  /**
   * Minimum age for deposits into this purse.
   */
  uint32_t min_age;

  /**
   * Flags for the operation.
   */
  enum TALER_WalletAccountMergeFlags flags;
};


/**
 * Send confirmation of purse creation success to client.
 *
 * @param connection connection to the client
 * @param rpc details about the request that succeeded
 * @return MHD result code
 */
static MHD_RESULT
reply_purse_success (struct MHD_Connection *connection,
                     const struct ReservePurseContext *rpc)
{
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  enum TALER_ErrorCode ec;

  if (TALER_EC_NONE !=
      (ec = TALER_exchange_online_purse_created_sign (
         &TEH_keys_exchange_sign_,
         rpc->exchange_timestamp,
         rpc->purse_expiration,
         &rpc->amount,
         &rpc->deposit_total,
         &rpc->purse_pub,
         &rpc->merge_pub,
         &rpc->h_contract_terms,
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
    TALER_JSON_pack_amount ("total_deposited",
                            &rpc->deposit_total),
    GNUNET_JSON_pack_timestamp ("exchange_timestamp",
                                rpc->exchange_timestamp),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &sig),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &pub));
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
    qs = TEH_plugin->insert_purse_request (TEH_plugin->cls,
                                           &rpc->purse_pub,
                                           &rpc->merge_pub,
                                           rpc->purse_expiration,
                                           &rpc->h_contract_terms,
                                           rpc->min_age,
                                           rpc->flags,
                                           &rpc->purse_fee,
                                           &rpc->amount,
                                           &rpc->purse_sig,
                                           &in_conflict);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      TALER_LOG_WARNING (
        "Failed to store purse purse information in database\n");
      *mhd_ret =
        TALER_MHD_reply_with_error (connection,
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
      qs = TEH_plugin->select_purse_request (TEH_plugin->cls,
                                             &rpc->purse_pub,
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
        *mhd_ret = TALER_MHD_reply_with_error (connection,
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

    qs = TEH_plugin->do_reserve_purse (TEH_plugin->cls,
                                       &rpc->purse_pub,
                                       &rpc->merge_sig,
                                       rpc->merge_timestamp,
                                       &rpc->reserve_sig,
                                       &rpc->gf->fees.purse,
                                       rpc->reserve_pub,
                                       &in_conflict,
                                       &insufficient_funds);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      TALER_LOG_WARNING (
        "Failed to store purse merge information in database\n");
      *mhd_ret =
        TALER_MHD_reply_with_error (connection,
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

      TEH_plugin->rollback (TEH_plugin->cls);
      qs = TEH_plugin->select_purse_merge (
        TEH_plugin->cls,
        &purse_pub,
        &merge_sig,
        &merge_timestamp,
        &partner_url,
        &reserve_pub);
      if (qs <= 0)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
        GNUNET_break (0 != qs);
        TALER_LOG_WARNING (
          "Failed to fetch purse merge information from database\n");
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_FETCH_FAILED,
                                               "select purse merge");
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
  if (NULL != rpc->econtract)
  {
    bool in_conflict = true;

    qs = TEH_plugin->insert_contract (TEH_plugin->cls,
                                      &rpc->purse_pub,
                                      &rpc->contract_pub,
                                      rpc->econtract_size,
                                      rpc->econtract,
                                      &rpc->econtract_sig,
                                      &in_conflict);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      TALER_LOG_WARNING ("Failed to store purse information in database\n");
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "purse purse contract");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (in_conflict)
    {
      struct TALER_ContractDiffiePublicP pub_ckey;
      struct TALER_PurseContractSignatureP econtract_sig;
      size_t econtract_size;
      void *econtract;
      struct GNUNET_HashCode h_econtract;

      qs = TEH_plugin->select_contract_by_purse (TEH_plugin->cls,
                                                 &rpc->purse_pub,
                                                 &pub_ckey,
                                                 &econtract_sig,
                                                 &econtract_size,
                                                 &econtract);
      if (qs <= 0)
      {
        if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
          return qs;
        GNUNET_break (0 != qs);
        TALER_LOG_WARNING (
          "Failed to store fetch contract information from database\n");
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_GENERIC_DB_FETCH_FAILED,
                                               "select contract");
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
      GNUNET_CRYPTO_hash (econtract,
                          econtract_size,
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
                                        &econtract_sig),
            GNUNET_JSON_pack_data_auto ("pub_ckey",
                                        &pub_ckey));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  return qs;
}


MHD_RESULT
TEH_handler_reserves_purse (
  struct TEH_RequestContext *rc,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  const json_t *root)
{
  struct MHD_Connection *connection = rc->connection;
  struct ReservePurseContext rpc = {
    .reserve_pub = reserve_pub,
    .exchange_timestamp = GNUNET_TIME_timestamp_get ()
  };
  bool no_purse_fee = true;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("purse_value",
                            TEH_currency,
                            &rpc.amount),
    GNUNET_JSON_spec_uint32 ("min_age",
                             &rpc.min_age),
    GNUNET_JSON_spec_mark_optional (
      TALER_JSON_spec_amount ("purse_fee",
                              TEH_currency,
                              &rpc.purse_fee),
      &no_purse_fee),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_varsize ("econtract",
                                &rpc.econtract,
                                &rpc.econtract_size),
      NULL),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("econtract_sig",
                                   &rpc.econtract_sig),
      NULL),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("contract_pub",
                                   &rpc.contract_pub),
      NULL),
    GNUNET_JSON_spec_fixed_auto ("merge_pub",
                                 &rpc.merge_pub),
    GNUNET_JSON_spec_fixed_auto ("merge_sig",
                                 &rpc.merge_sig),
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &rpc.reserve_sig),
    GNUNET_JSON_spec_fixed_auto ("purse_pub",
                                 &rpc.purse_pub),
    GNUNET_JSON_spec_fixed_auto ("purse_sig",
                                 &rpc.purse_sig),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &rpc.h_contract_terms),
    GNUNET_JSON_spec_timestamp ("merge_timestamp",
                                &rpc.merge_timestamp),
    GNUNET_JSON_spec_timestamp ("purse_expiration",
                                &rpc.purse_expiration),
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
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &rpc.deposit_total));
  if (GNUNET_TIME_timestamp_cmp (rpc.purse_expiration,
                                 <,
                                 rpc.exchange_timestamp))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_RESERVES_PURSE_EXPIRATION_BEFORE_NOW,
                                       NULL);
  }
  if (GNUNET_TIME_absolute_is_never (rpc.purse_expiration.abs_time))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_RESERVES_PURSE_EXPIRATION_IS_NEVER,
                                       NULL);
  }
  rpc.gf = TEH_keys_global_fee_by_time (TEH_keys_get_state (),
                                        rpc.exchange_timestamp);
  if (NULL == rpc.gf)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Cannot purse purse: global fees not configured!\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_GLOBAL_FEES_MISSING,
                                       NULL);
  }
  if (no_purse_fee)
  {
    rpc.flags = TALER_WAMF_MODE_CREATE_FROM_PURSE_QUOTA;
    TALER_amount_set_zero (TEH_currency,
                           &rpc.purse_fee);
  }
  else
  {
    rpc.flags = TALER_WAMF_MODE_CREATE_WITH_PURSE_FEE;
    // FIXME: check rpc.purse_fee is at or above gf.fees.purse!
  }
  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_wallet_purse_create_verify (rpc.purse_expiration,
                                        &rpc.h_contract_terms,
                                        &rpc.merge_pub,
                                        rpc.min_age,
                                        &rpc.amount,
                                        &rpc.purse_pub,
                                        &rpc.purse_sig))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_PURSE_CREATE_SIGNATURE_INVALID,
      NULL);
  }
  if (GNUNET_OK !=
      TALER_wallet_purse_merge_verify (TEH_base_url,
                                       rpc.merge_timestamp,
                                       &rpc.purse_pub,
                                       &rpc.merge_pub,
                                       &rpc.merge_sig))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_RESERVES_PURSE_MERGE_SIGNATURE_INVALID,
      NULL);
  }
  if (GNUNET_OK !=
      TALER_wallet_account_merge_verify (rpc.merge_timestamp,
                                         &rpc.purse_pub,
                                         rpc.purse_expiration,
                                         &rpc.h_contract_terms,
                                         &rpc.amount,
                                         &rpc.purse_fee,
                                         rpc.min_age,
                                         rpc.flags,
                                         rpc.reserve_pub,
                                         &rpc.reserve_sig))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_RESERVES_PURSE_MERGE_SIGNATURE_INVALID,
      NULL);
  }
  if ( (NULL != rpc.econtract) &&
       (GNUNET_OK !=
        TALER_wallet_econtract_upload_verify (rpc.econtract,
                                              rpc.econtract_size,
                                              &rpc.contract_pub,
                                              &rpc.purse_pub,
                                              &rpc.econtract_sig)) )
  {
    TALER_LOG_WARNING ("Invalid signature on /reserves/$PID/purse request\n");
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_PURSE_ECONTRACT_SIGNATURE_INVALID,
                                       NULL);
  }


  if (GNUNET_SYSERR ==
      TEH_plugin->preflight (TEH_plugin->cls))
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_START_FAILED,
                                       "preflight failure");
  }

  /* execute transaction */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "execute purse purse",
                                TEH_MT_REQUEST_RESERVE_PURSE,
                                &mhd_ret,
                                &purse_transaction,
                                &rpc))
    {
      GNUNET_JSON_parse_free (spec);
      return mhd_ret;
    }
  }

  /* generate regular response */
  {
    MHD_RESULT res;

    res = reply_purse_success (connection,
                               &rpc);
    GNUNET_JSON_parse_free (spec);
    return res;
  }
}


/* end of taler-exchange-httpd_reserves_purse.c */
