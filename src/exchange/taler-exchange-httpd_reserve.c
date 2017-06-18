/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 GNUnet e.V.

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
 * @file taler-exchange-httpd_reserve.c
 * @brief Handle /reserve/ requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler-exchange-httpd_reserve.h"
#include "taler-exchange-httpd_parsing.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"


/**
 * Handle a "/reserve/withdraw" request.  Parses the "reserve_pub"
 * EdDSA key of the reserve and the requested "denom_pub" which
 * specifies the key/value of the coin to be withdrawn, and checks
 * that the signature "reserve_sig" makes this a valid withdrawal
 * request from the specified reserve.  If so, the envelope
 * with the blinded coin "coin_ev" is passed down to execute the
 * withdrawl operation.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TEH_RESERVE_handler_reserve_withdraw (struct TEH_RequestHandler *rh,
                                      struct MHD_Connection *connection,
                                      void **connection_cls,
                                      const char *upload_data,
                                      size_t *upload_data_size)
{
  json_t *root;
  struct TALER_WithdrawRequestPS wsrd;
  int res;
  struct TALER_DenominationPublicKey denomination_pub;
  char *blinded_msg;
  size_t blinded_msg_len;
  struct TALER_Amount amount;
  struct TALER_Amount amount_with_fee;
  struct TALER_Amount fee_withdraw;
  struct TALER_ReserveSignatureP signature;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;
  struct TEH_KS_StateHandle *ks;

  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_varsize ("coin_ev",
                              (void **) &blinded_msg,
                              &blinded_msg_len),
    GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                 &wsrd.reserve_pub),
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &signature),
    TALER_JSON_spec_denomination_public_key ("denom_pub",
                                             &denomination_pub),
    GNUNET_JSON_spec_end ()
  };

  res = TEH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &root);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == root) )
    return MHD_YES;
  res = TEH_PARSE_json_data (connection,
                             root,
                             spec);
  json_decref (root);
  if (GNUNET_OK != res)
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  ks = TEH_KS_acquire ();
  dki = TEH_KS_denomination_key_lookup (ks,
                                        &denomination_pub,
					TEH_KS_DKU_WITHDRAW);
  if (NULL == dki)
  {
    GNUNET_JSON_parse_free (spec);
    TEH_KS_release (ks);
    return TEH_RESPONSE_reply_arg_unknown (connection,
					   TALER_EC_WITHDRAW_DENOMINATION_KEY_NOT_FOUND,
                                           "denom_pub");
  }
  TALER_amount_ntoh (&amount,
                     &dki->issue.properties.value);
  TALER_amount_ntoh (&fee_withdraw,
                     &dki->issue.properties.fee_withdraw);
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_add (&amount_with_fee,
                                   &amount,
                                   &fee_withdraw));
  TALER_amount_hton (&wsrd.amount_with_fee,
                     &amount_with_fee);
  TALER_amount_hton (&wsrd.withdraw_fee,
                     &fee_withdraw);
  TEH_KS_release (ks);
  /* verify signature! */
  wsrd.purpose.size = htonl (sizeof (struct TALER_WithdrawRequestPS));
  wsrd.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW);

  GNUNET_CRYPTO_rsa_public_key_hash (denomination_pub.rsa_public_key,
                                     &wsrd.h_denomination_pub);
  GNUNET_CRYPTO_hash (blinded_msg,
                      blinded_msg_len,
                      &wsrd.h_coin_envelope);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW,
                                  &wsrd.purpose,
                                  &signature.eddsa_signature,
                                  &wsrd.reserve_pub.eddsa_pub))
  {
    TALER_LOG_WARNING ("Client supplied invalid signature for /reserve/withdraw request\n");
    GNUNET_JSON_parse_free (spec);
    return TEH_RESPONSE_reply_signature_invalid (connection,
						 TALER_EC_WITHDRAW_RESERVE_SIGNATURE_INVALID,
                                                 "reserve_sig");
  }
  res = TEH_DB_execute_reserve_withdraw (connection,
                                         &wsrd.reserve_pub,
                                         &denomination_pub,
                                         blinded_msg,
                                         blinded_msg_len,
                                         &signature);
  GNUNET_JSON_parse_free (spec);
  return res;
}

/* end of taler-exchange-httpd_reserve.c */
