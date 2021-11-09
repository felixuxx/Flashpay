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
 * @file taler-exchange-httpd_kyc-check.c
 * @brief Handle request for generic KYC check.
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
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_kyc-wallet.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Context for the request.
 */
struct KycCheckContext
{
  /**
   * UUID being checked.
   */
  uint64_t payment_target_uuid;

  /**
   * Current KYC status.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Hash of the payto:// URI we are confirming to
   * have finished the KYC for.
   */
  struct TALER_PaytoHash h_payto;
};


/**
 * Function implementing database transaction to check wallet's KYC status.
 * Runs the transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls closure with a `struct KycCheckContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
kyc_check (void *cls,
           struct MHD_Connection *connection,
           MHD_RESULT *mhd_ret)
{
  struct KycCheckContext *kcc = cls;
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->select_kyc_status (TEH_plugin->cls,
                                      kcc->payment_target_uuid,
                                      &kcc->h_payto,
                                      &kcc->kyc);
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
TEH_handler_kyc_check (
  struct TEH_RequestContext *rc,
  const char *const args[])
{
  unsigned long long payment_target_uuid;
  MHD_RESULT res;
  enum GNUNET_GenericReturnValue ret;
  char dummy;
  struct TALER_PaytoHash h_payto;

  if (1 !=
      sscanf (args[0],
              "%llu%c",
              &payment_target_uuid,
              &dummy))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       "payment_target_uuid");
  }
  {
    const char *ts;

    ts = MHD_lookup_connection_value (rc->connection,
                                      MHD_GET_ARGUMENT_KIND,
                                      "timeout_ms");
    if (NULL != ts)
    {
      unsigned long long tms;

      if (1 !=
          sscanf (ts,
                  "%llu%c",
                  &tms,
                  &dummy))
      {
        GNUNET_break_op (0);
        return TALER_MHD_reply_with_error (rc->connection,
                                           MHD_HTTP_BAD_REQUEST,
                                           TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                           "timeout_ms");
      }
      /* FIXME: write long polling logic ... */
    }
  }
  {
    const char *hps;

    hps = MHD_lookup_connection_value (rc->connection,
                                       MHD_GET_ARGUMENT_KIND,
                                       "h_payto");
    if (NULL == hps)
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_PARAMETER_MISSING,
                                         "h_payto");
    }
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (hps,
                                       strlen (hps),
                                       &h_payto,
                                       sizeof (h_payto)))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                         "h_payto");
    }
  }

  if (TEH_KYC_NONE == TEH_kyc_config.mode)
    return TALER_MHD_reply_static (
      rc->connection,
      MHD_HTTP_NO_CONTENT,
      NULL,
      NULL,
      0);
  {
    struct GNUNET_TIME_Absolute now;
    struct KycCheckContext kcc = {
      .payment_target_uuid = payment_target_uuid
    };

    now = GNUNET_TIME_absolute_get ();
    (void) GNUNET_TIME_round_abs (&now);
    ret = TEH_DB_run_transaction (rc->connection,
                                  "kyc check",
                                  &res,
                                  &kyc_check,
                                  &kcc);
    if (GNUNET_SYSERR == ret)
      return res;
    if (0 !=
        GNUNET_memcmp (&kcc.h_payto,
                       &h_payto))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_UNAUTHORIZED,
                                         TALER_EC_EXCHANGE_KYC_CHECK_AUTHORIZATION_FAILED,
                                         "h_payto");
    }
    if (! kcc.kyc.ok)
    {
      char *url;
      char *redirect_uri;
      char *redirect_uri_encoded;

      GNUNET_assert (TEH_KYC_OAUTH2 == TEH_kyc_config.mode);
      GNUNET_asprintf (&redirect_uri,
                       "%s/kyc-proof/%llu",
                       TEH_base_url,
                       payment_target_uuid);
      redirect_uri_encoded = TALER_urlencode (redirect_uri);
      GNUNET_free (redirect_uri);
      GNUNET_asprintf (&url,
                       "%s/login?client_id=%s&redirect_uri=%s",
                       TEH_kyc_config.details.oauth2.url,
                       TEH_kyc_config.details.oauth2.client_id,
                       redirect_uri_encoded);
      GNUNET_free (redirect_uri_encoded);

      res = TALER_MHD_REPLY_JSON_PACK (
        rc->connection,
        MHD_HTTP_ACCEPTED,
        GNUNET_JSON_pack_string ("kyc_url",
                                 url));
      GNUNET_free (url);
      return res;
    }
    {
      struct TALER_ExchangePublicKeyP pub;
      struct TALER_ExchangeSignatureP sig;
      struct TALER_ExchangeAccountSetupSuccessPS as = {
        .purpose.purpose = htonl (
          TALER_SIGNATURE_EXCHANGE_ACCOUNT_SETUP_SUCCESS),
        .purpose.size = htonl (sizeof (as)),
        .h_payto = kcc.h_payto,
        .timestamp = GNUNET_TIME_absolute_hton (now)
      };
      enum TALER_ErrorCode ec;

      if (TALER_EC_NONE !=
          (ec = TEH_keys_exchange_sign (&as,
                                        &pub,
                                        &sig)))
      {
        return TALER_MHD_reply_with_ec (rc->connection,
                                        ec,
                                        NULL);
      }
      return TALER_MHD_REPLY_JSON_PACK (
        rc->connection,
        MHD_HTTP_OK,
        GNUNET_JSON_pack_data_auto ("exchange_sig",
                                    &sig),
        GNUNET_JSON_pack_data_auto ("exchange_pub",
                                    &pub),
        GNUNET_JSON_pack_time_abs ("now",
                                   now));
    }
  }
}


/* end of taler-exchange-httpd_kyc-check.c */
