/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file taler-exchange-httpd_responses.c
 * @brief API for generating generic replies of the exchange; these
 *        functions are called TEH_RESPONSE_reply_ and they generate
 *        and queue MHD response objects for a given connection.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_json_lib.h>
#include <microhttpd.h>
#include <zlib.h>
#include "taler-exchange-httpd_responses.h"
#include "taler_exchangedb_plugin.h"
#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_keys.h"


MHD_RESULT
TEH_RESPONSE_reply_unknown_denom_pub_hash (
  struct MHD_Connection *connection,
  const struct TALER_DenominationHashP *dph)
{
  struct TALER_ExchangePublicKeyP epub;
  struct TALER_ExchangeSignatureP esig;
  struct GNUNET_TIME_Timestamp now;
  enum TALER_ErrorCode ec;

  now = GNUNET_TIME_timestamp_get ();
  ec = TALER_exchange_online_denomination_unknown_sign (
    &TEH_keys_exchange_sign_,
    now,
    dph,
    &epub,
    &esig);
  if (TALER_EC_NONE != ec)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       ec,
                                       NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_NOT_FOUND,
    TALER_JSON_pack_ec (TALER_EC_EXCHANGE_GENERIC_DENOMINATION_KEY_UNKNOWN),
    GNUNET_JSON_pack_timestamp ("timestamp",
                                now),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &epub),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &esig),
    GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                dph));
}


MHD_RESULT
TEH_RESPONSE_reply_expired_denom_pub_hash (
  struct MHD_Connection *connection,
  const struct TALER_DenominationHashP *dph,
  enum TALER_ErrorCode ec,
  const char *oper)
{
  struct TALER_ExchangePublicKeyP epub;
  struct TALER_ExchangeSignatureP esig;
  enum TALER_ErrorCode ecr;
  struct GNUNET_TIME_Timestamp now
    = GNUNET_TIME_timestamp_get ();

  ecr = TALER_exchange_online_denomination_expired_sign (
    &TEH_keys_exchange_sign_,
    now,
    dph,
    oper,
    &epub,
    &esig);
  if (TALER_EC_NONE != ecr)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       ec,
                                       NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_GONE,
    TALER_JSON_pack_ec (ec),
    GNUNET_JSON_pack_string ("oper",
                             oper),
    GNUNET_JSON_pack_timestamp ("timestamp",
                                now),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &epub),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &esig),
    GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                dph));
}


MHD_RESULT
TEH_RESPONSE_reply_invalid_denom_cipher_for_operation (
  struct MHD_Connection *connection,
  const struct TALER_DenominationHashP *dph)
{
  struct TALER_ExchangePublicKeyP epub;
  struct TALER_ExchangeSignatureP esig;
  struct GNUNET_TIME_Timestamp now;
  enum TALER_ErrorCode ec;

  now = GNUNET_TIME_timestamp_get ();
  ec = TALER_exchange_online_denomination_unknown_sign (
    &TEH_keys_exchange_sign_,
    now,
    dph,
    &epub,
    &esig);
  if (TALER_EC_NONE != ec)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       ec,
                                       NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_NOT_FOUND,
    TALER_JSON_pack_ec (
      TALER_EC_EXCHANGE_GENERIC_INVALID_DENOMINATION_CIPHER_FOR_OPERATION),
    GNUNET_JSON_pack_timestamp ("timestamp",
                                now),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &epub),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &esig),
    GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                dph));
}


MHD_RESULT
TEH_RESPONSE_reply_coin_insufficient_funds (
  struct MHD_Connection *connection,
  enum TALER_ErrorCode ec,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub)
{
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    TALER_ErrorCode_get_http_status_safe (ec),
    TALER_JSON_pack_ec (ec),
    GNUNET_JSON_pack_data_auto ("coin_pub",
                                coin_pub),
    // FIXME - #7267: to be kept only for some of the error types!
    GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                h_denom_pub));
}


MHD_RESULT
TEH_RESPONSE_reply_coin_conflicting_contract (
  struct MHD_Connection *connection,
  enum TALER_ErrorCode ec,
  const struct TALER_MerchantWireHashP *h_wire)
{
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    TALER_ErrorCode_get_http_status_safe (ec),
    GNUNET_JSON_pack_data_auto ("h_wire",
                                h_wire),
    TALER_JSON_pack_ec (ec));
}


MHD_RESULT
TEH_RESPONSE_reply_coin_denomination_conflict (
  struct MHD_Connection *connection,
  enum TALER_ErrorCode ec,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_DenominationPublicKey *prev_denom_pub,
  const struct TALER_DenominationSignature *prev_denom_sig)
{
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    TALER_ErrorCode_get_http_status_safe (ec),
    TALER_JSON_pack_ec (ec),
    GNUNET_JSON_pack_data_auto ("coin_pub",
                                coin_pub),
    TALER_JSON_pack_denom_pub ("prev_denom_pub",
                               prev_denom_pub),
    TALER_JSON_pack_denom_sig ("prev_denom_sig",
                               prev_denom_sig)
    );

}


MHD_RESULT
TEH_RESPONSE_reply_coin_age_commitment_conflict (
  struct MHD_Connection *connection,
  enum TALER_ErrorCode ec,
  enum TALER_EXCHANGEDB_CoinKnownStatus status,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_AgeCommitmentHash *h_age_commitment)
{
  const char *conflict_detail;

  switch (status)
  {

  case TALER_EXCHANGEDB_CKS_AGE_CONFLICT_EXPECTED_NULL:
    conflict_detail = "expected NULL age commitment hash";
    h_age_commitment = NULL;
    break;
  case TALER_EXCHANGEDB_CKS_AGE_CONFLICT_EXPECTED_NON_NULL:
    conflict_detail = "expected non-NULL age commitment hash";
    break;
  case TALER_EXCHANGEDB_CKS_AGE_CONFLICT_VALUE_DIFFERS:
    conflict_detail = "expected age commitment hash differs";
    break;
  default:
    GNUNET_assert (0);
  }

  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    TALER_ErrorCode_get_http_status_safe (ec),
    TALER_JSON_pack_ec (ec),
    GNUNET_JSON_pack_data_auto ("coin_pub",
                                coin_pub),
    GNUNET_JSON_pack_data_auto ("h_denom_pub",
                                h_denom_pub),
    GNUNET_JSON_pack_allow_null (
      GNUNET_JSON_pack_data_auto ("expected_age_commitment_hash",
                                  h_age_commitment)),
    GNUNET_JSON_pack_string ("conflict_detail",
                             conflict_detail)
    );
}


MHD_RESULT
TEH_RESPONSE_reply_reserve_insufficient_balance (
  struct MHD_Connection *connection,
  enum TALER_ErrorCode ec,
  const struct TALER_Amount *reserve_balance,
  const struct TALER_Amount *balance_required,
  const struct TALER_ReservePublicKeyP *reserve_pub)
{
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_CONFLICT,
    TALER_JSON_pack_ec (ec),
    TALER_JSON_pack_amount ("balance",
                            reserve_balance),
    TALER_JSON_pack_amount ("requested_amount",
                            balance_required));
}


MHD_RESULT
TEH_RESPONSE_reply_reserve_age_restriction_required (
  struct MHD_Connection *connection,
  uint16_t maximum_allowed_age)
{
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_CONFLICT,
    TALER_JSON_pack_ec (TALER_EC_EXCHANGE_RESERVES_AGE_RESTRICTION_REQUIRED),
    GNUNET_JSON_pack_uint64 ("maximum_allowed_age",
                             maximum_allowed_age));
}


MHD_RESULT
TEH_RESPONSE_reply_purse_created (
  struct MHD_Connection *connection,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  const struct TALER_Amount *purse_balance,
  const struct TEH_PurseDetails *pd)
{
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  enum TALER_ErrorCode ec;

  if (TALER_EC_NONE !=
      (ec = TALER_exchange_online_purse_created_sign (
         &TEH_keys_exchange_sign_,
         exchange_timestamp,
         pd->purse_expiration,
         &pd->target_amount,
         purse_balance,
         &pd->purse_pub,
         &pd->h_contract_terms,
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
                            purse_balance),
    GNUNET_JSON_pack_timestamp ("exchange_timestamp",
                                exchange_timestamp),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &sig),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &pub));
}


MHD_RESULT
TEH_RESPONSE_reply_kyc_required (struct MHD_Connection *connection,
                                 const struct TALER_PaytoHashP *h_payto,
                                 const struct TALER_EXCHANGEDB_KycStatus *kyc)
{
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS,
    TALER_JSON_pack_ec (TALER_EC_EXCHANGE_GENERIC_KYC_REQUIRED),
    GNUNET_JSON_pack_data_auto ("h_payto",
                                h_payto),
    GNUNET_JSON_pack_uint64 ("requirement_row",
                             kyc->requirement_row));
}


MHD_RESULT
TEH_RESPONSE_reply_not_modified (
  struct MHD_Connection *connection,
  const char *etags,
  TEH_RESPONSE_SetHeaders cb,
  void *cb_cls)
{
  MHD_RESULT ret;
  struct MHD_Response *resp;

  resp = MHD_create_response_from_buffer (0,
                                          NULL,
                                          MHD_RESPMEM_PERSISTENT);
  if (NULL != cb)
    cb (cb_cls,
        resp);
  GNUNET_break (MHD_YES ==
                MHD_add_response_header (resp,
                                         MHD_HTTP_HEADER_ETAG,
                                         etags));
  ret = MHD_queue_response (connection,
                            MHD_HTTP_NOT_MODIFIED,
                            resp);
  GNUNET_break (MHD_YES == ret);
  MHD_destroy_response (resp);
  return ret;
}


/* end of taler-exchange-httpd_responses.c */
