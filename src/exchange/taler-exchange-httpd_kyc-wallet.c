/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_kyc-wallet.c
 * @brief Handle request for wallet for KYC check.
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
#include "taler-exchange-httpd_kyc-wallet.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Context for the request.
 */
struct KycRequestContext
{
  /**
   * Public key of the reserve/wallet this is about.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Current KYC status.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;
};


/**
 * Function implementing database transaction to check wallet's KYC status.
 * Runs the transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct KycRequestContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
wallet_kyc_check (void *cls,
                  struct MHD_Connection *connection,
                  MHD_RESULT *mhd_ret)
{
  struct KycRequestContext *krc = cls;
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->inselect_wallet_kyc_status (TEH_plugin->cls,
                                               &krc->reserve_pub,
                                               &krc->kyc);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_FETCH_FAILED,
                                           "inselect_wallet_status");
    return qs;
  }
  return qs;
}


MHD_RESULT
TEH_handler_kyc_wallet (
  struct TEH_RequestContext *rc,
  const json_t *root,
  const char *const args[])
{
  struct TALER_ReserveSignatureP reserve_sig;
  struct KycRequestContext krc;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &reserve_sig),
    GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                 &krc.reserve_pub),
    GNUNET_JSON_spec_end ()
  };
  MHD_RESULT res;
  enum GNUNET_GenericReturnValue ret;
  struct GNUNET_CRYPTO_EccSignaturePurpose purpose = {
    .size = htonl (sizeof (purpose)),
    .purpose = htonl (TALER_SIGNATURE_WALLET_ACCOUNT_SETUP)
  };

  (void) args;
  ret = TALER_MHD_parse_json_data (rc->connection,
                                   root,
                                   spec);
  if (GNUNET_SYSERR == ret)
    return MHD_NO;   /* hard failure */
  if (GNUNET_NO == ret)
    return MHD_YES;   /* failure */

  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify_ (TALER_SIGNATURE_WALLET_ACCOUNT_SETUP,
                                   &purpose,
                                   &reserve_sig.eddsa_signature,
                                   &krc.reserve_pub.eddsa_pub))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (
      rc->connection,
      MHD_HTTP_FORBIDDEN,
      TALER_EC_EXCHANGE_KYC_WALLET_SIGNATURE_INVALID,
      NULL);
  }
  if (TEH_KYC_NONE == TEH_kyc_config.mode)
    return TALER_MHD_reply_static (
      rc->connection,
      MHD_HTTP_NO_CONTENT,
      NULL,
      NULL,
      0);
  ret = TEH_DB_run_transaction (rc->connection,
                                "check wallet kyc",
                                TEH_MT_REQUEST_OTHER,
                                &res,
                                &wallet_kyc_check,
                                &krc);
  if (GNUNET_SYSERR == ret)
    return res;
  return TALER_MHD_REPLY_JSON_PACK (
    rc->connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_uint64 ("payment_target_uuid",
                             krc.kyc.payment_target_uuid));
}


/* end of taler-exchange-httpd_kyc-wallet.c */
