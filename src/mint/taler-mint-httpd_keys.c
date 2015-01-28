/*
  This file is part of TALER
  (C) 2014 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-mint-httpd_keys.c
 * @brief Handle /keys requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "mint.h"
#include "taler-mint-httpd_keys.h"
#include "taler-mint-httpd_keystate.h"


/**
 * Function to call to handle the request by sending
 * back static data from the @a rh.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[IN|OUT] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[IN|OUT] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TALER_MINT_handler_keys (struct RequestHandler *rh,
                         struct MHD_Connection *connection,
                         void **connection_cls,
                         const char *upload_data,
                         size_t *upload_data_size)
{
  struct MintKeyState *key_state;
  struct MHD_Response *response;
  int ret;

  key_state = TALER_MINT_key_state_acquire ();
  response = MHD_create_response_from_buffer (strlen (key_state->keys_json),
                                              key_state->keys_json,
                                              MHD_RESPMEM_MUST_COPY);
  TALER_MINT_key_state_release (key_state);
  if (NULL == response)
  {
    GNUNET_break (0);
    return MHD_NO;
  }
  (void) MHD_add_response_header (response,
                                  "Content-Type",
                                  rh->mime_type);
  ret = MHD_queue_response (connection,
                            rh->response_code,
                            response);
  MHD_destroy_response (response);
  return ret;
}


/**
 * Check if a coin is valid; that is, whether the denomination key exists,
 * is not expired, and the signature is correct.
 *
 * @param key_state the key state to use for checking the coin's validity
 * @param coin_public_info the coin public info to check for validity
 * @return #GNUNET_YES if the coin is valid,
 *         #GNUNET_NO if it is invalid
 *         #GNUNET_SYSERROR if an internal error occured
 */
int
TALER_MINT_test_coin_valid (const struct MintKeyState *key_state,
                            const struct TALER_CoinPublicInfo *coin_public_info)
{
  struct TALER_MINT_DenomKeyIssuePriv *dki;
  struct GNUNET_HashCode c_hash;

  dki = TALER_MINT_get_denom_key (key_state, coin_public_info->denom_pub);
  if (NULL == dki)
    return GNUNET_NO;
  /* FIXME: we had envisioned a more complex scheme... */
  GNUNET_CRYPTO_hash (&coin_public_info->coin_pub,
                      sizeof (struct GNUNET_CRYPTO_EcdsaPublicKey),
                      &c_hash);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_rsa_verify (&c_hash,
                                coin_public_info->denom_sig,
                                dki->issue.denom_pub))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "coin signature is invalid\n");
    return GNUNET_NO;
  }
  return GNUNET_YES;
}


/**
 * Sign the message in @a purpose with the mint's signing
 * key.
 *
 * @param purpose the message to sign
 * @param[OUT] sig signature over purpose using current signing key
 */
void
TALER_MINT_keys_sign (const struct GNUNET_CRYPTO_EccSignaturePurpose *purpose,
                      struct GNUNET_CRYPTO_EddsaSignature *sig)

{
  struct MintKeyState *key_state;

  key_state = TALER_MINT_key_state_acquire ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (&key_state->current_sign_key_issue.signkey_priv,
                                           purpose,
                                           sig));

  TALER_MINT_key_state_release (key_state);
}


/* end of taler-mint-httpd_keys.c */
