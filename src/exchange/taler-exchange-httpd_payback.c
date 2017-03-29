/*
  This file is part of TALER
  Copyright (C) 2017 Inria and GNUnet e.V.

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
 * @file taler-exchange-httpd_payback.c
 * @brief Handle /payback requests; parses the POST and JSON and
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
#include "taler-exchange-httpd_parsing.h"
#include "taler-exchange-httpd_payback.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_validation.h"


/**
 * We have parsed the JSON information about the payback request. Do
 * some basic sanity checks (especially that the signature on the
 * request and coin is valid) and then execute the payback operation.
 * Note that we need the DB to check the fee structure, so this is not
 * done here.
 *
 * @param connection the MHD connection to handle
 * @param coin information about the coin
 * @param coin_bks blinding data of the coin (to be checked)
 * @param coin_sig signature of the coin
 * @return MHD result code
 */
static int
verify_and_execute_payback (struct MHD_Connection *connection,
                            const struct TALER_CoinPublicInfo *coin,
                            const struct TALER_DenominationBlindingKeyP *coin_bks,
                            const struct TALER_CoinSpendSignatureP *coin_sig)
{
  struct TEH_KS_StateHandle *key_state;
  const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;
  struct TALER_PaybackRequestPS pr;


  /* check denomination exists and is in payback mode */
  key_state = TEH_KS_acquire ();
  dki = TEH_KS_denomination_key_lookup (key_state,
                                        &coin->denom_pub,
					TEH_KS_DKU_PAYBACK);
  if (NULL == dki)
  {
    TEH_KS_release (key_state);
    TALER_LOG_WARNING ("Denomination key in /payback request not in payback mode\n");
    return TEH_RESPONSE_reply_arg_unknown (connection,
					   TALER_EC_PAYBACK_DENOMINATION_KEY_UNKNOWN,
                                           "denom_pub");
  }

  /* check denomination signature */
  if (GNUNET_YES !=
      TALER_test_coin_valid (coin))
  {
    TALER_LOG_WARNING ("Invalid coin passed for /payback\n");
    TEH_KS_release (key_state);
    return TEH_RESPONSE_reply_signature_invalid (connection,
						 TALER_EC_PAYBACK_DENOMINATION_SIGNATURE_INVALID,
                                                 "denom_sig");
  }

  /* check payback request signature */
  pr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_PAYBACK);
  pr.purpose.size = htonl (sizeof (struct TALER_PaybackRequestPS));
  pr.coin_pub = coin->coin_pub;
  pr.h_denom_pub = dki->issue.properties.denom_hash;
  pr.coin_blind = *coin_bks;

  TEH_KS_release (key_state);

  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_PAYBACK,
                                  &pr.purpose,
                                  &coin_sig->eddsa_signature,
                                  &coin->coin_pub.eddsa_pub))
  {
    TALER_LOG_WARNING ("Invalid signature on /payback request\n");
    return TEH_RESPONSE_reply_signature_invalid (connection,
						 TALER_EC_PAYBACK_SIGNATURE_INVALID,
                                                 "coin_sig");
  }

  return TEH_DB_execute_payback (connection,
                                 coin,
                                 coin_bks,
                                 coin_sig);
}


/**
 * Handle a "/payback" request.  Parses the JSON, and, if successful,
 * passes the JSON data to #parse_and_handle_payback_request() to
 * further check the details of the operation specified.  If
 * everything checks out, this will ultimately lead to the "/refund"
 * being executed, or rejected.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TEH_PAYBACK_handler_payback (struct TEH_RequestHandler *rh,
                             struct MHD_Connection *connection,
                             void **connection_cls,
                             const char *upload_data,
                             size_t *upload_data_size)
{
  json_t *json;
  int res;
  struct TALER_CoinPublicInfo coin;
  struct TALER_DenominationBlindingKeyP coin_bks;
  struct TALER_CoinSpendSignatureP coin_sig;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_denomination_public_key ("denom_pub",
                                             &coin.denom_pub),
    TALER_JSON_spec_denomination_signature ("ub_sig",
                                            &coin.denom_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 &coin.coin_pub),
    GNUNET_JSON_spec_fixed_auto ("coin_blind_key_secret",
                                 &coin_bks),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &coin_sig),
    GNUNET_JSON_spec_end ()
  };

  res = TEH_PARSE_post_json (connection,
                             connection_cls,
                             upload_data,
                             upload_data_size,
                             &json);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) || (NULL == json) )
    return MHD_YES;
  res = TEH_PARSE_json_data (connection,
                             json,
                             spec);
  json_decref (json);
  if (GNUNET_SYSERR == res)
    return MHD_NO; /* hard failure */
  if (GNUNET_NO == res)
    return MHD_YES; /* failure */
  res = verify_and_execute_payback (connection,
                                    &coin,
                                    &coin_bks,
                                    &coin_sig);
  GNUNET_JSON_parse_free (spec);
  return res;
}


/* end of taler-exchange-httpd_payback.c */
