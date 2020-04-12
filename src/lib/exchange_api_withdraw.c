/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_withdraw.c
 * @brief Implementation of /reserves/$RESERVE_PUB/withdraw requests with blinding/unblinding
 * @author Christian Grothoff
 */
#include "platform.h"
#include <jansson.h>
#include <microhttpd.h> /* just for HTTP status codes */
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include "exchange_api_handle.h"
#include "taler_signatures.h"
#include "exchange_api_curl_defaults.h"


/**
 * @brief A Withdraw Handle
 */
struct TALER_EXCHANGE_WithdrawHandle
{

  /**
   * The connection to exchange this request handle will use
   */
  struct TALER_EXCHANGE_Handle *exchange;

  /**
   * Handle for the actual (internal) withdraw operation.
   */
  struct TALER_EXCHANGE_Withdraw2Handle *wh2;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_WithdrawCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Secrets of the planchet.
   */
  struct TALER_PlanchetSecretsP ps;

  /**
   * Denomination key we are withdrawing.
   */
  struct TALER_EXCHANGE_DenomPublicKey pk;

  /**
   * Hash of the public key of the coin we are signing.
   */
  struct GNUNET_HashCode c_hash;

};


/**
 * Function called when we're done processing the
 * HTTP /reserves/$RESERVE_PUB/withdraw request.
 *
 * @param cls the `struct TALER_EXCHANGE_WithdrawHandle`
 * @param hr HTTP response data
 * @param blind_sig blind signature over the coin, NULL on error
 */
static void
handle_reserve_withdraw_finished (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr,
  const struct GNUNET_CRYPTO_RsaSignature *blind_sig)
{
  struct TALER_EXCHANGE_WithdrawHandle *wh = cls;

  wh->wh2 = NULL;
  if (MHD_HTTP_OK != hr->http_status)
  {
    wh->cb (wh->cb_cls,
            hr,
            NULL);
  }
  else
  {
    struct TALER_FreshCoin fc;

    if (GNUNET_OK !=
        TALER_planchet_to_coin (&wh->pk.key,
                                blind_sig,
                                &wh->ps,
                                &wh->c_hash,
                                &fc))
    {
      struct TALER_EXCHANGE_HttpResponse hrx = {
        .reply = hr->reply,
        .http_status = 0,
        .ec = TALER_EC_WITHDRAW_UNBLIND_FAILURE
      };

      wh->cb (wh->cb_cls,
              &hrx,
              NULL);
    }
    else
    {
      wh->cb (wh->cb_cls,
              hr,
              &fc.sig);
      GNUNET_CRYPTO_rsa_signature_free (fc.sig.rsa_signature);
    }

  }
  TALER_EXCHANGE_withdraw_cancel (wh);
}


/**
 * Withdraw a coin from the exchange using a /reserve/withdraw request.  Note
 * that to ensure that no money is lost in case of hardware failures,
 * the caller must have committed (most of) the arguments to disk
 * before calling, and be ready to repeat the request with the same
 * arguments in case of failures.
 *
 * @param exchange the exchange handle; the exchange must be ready to operate
 * @param pk kind of coin to create
 * @param reserve_priv private key of the reserve to withdraw from
 * @param ps secrets of the planchet
 *        caller must have committed this value to disk before the call (with @a pk)
 * @param res_cb the callback to call when the final result for this request is available
 * @param res_cb_cls closure for the above callback
 * @return handle for the operation on success, NULL on error, i.e.
 *         if the inputs are invalid (i.e. denomination key not with this exchange).
 *         In this case, the callback is not called.
 */
struct TALER_EXCHANGE_WithdrawHandle *
TALER_EXCHANGE_withdraw (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_EXCHANGE_DenomPublicKey *pk,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  const struct TALER_PlanchetSecretsP *ps,
  TALER_EXCHANGE_WithdrawCallback res_cb,
  void *res_cb_cls)
{
  struct TALER_PlanchetDetail pd;
  struct TALER_EXCHANGE_WithdrawHandle *wh;

  wh = GNUNET_new (struct TALER_EXCHANGE_WithdrawHandle);
  wh->exchange = exchange;
  wh->cb = res_cb;
  wh->cb_cls = res_cb_cls;
  wh->pk = *pk;
  wh->ps = *ps;
  if (GNUNET_OK !=
      TALER_planchet_prepare (&pk->key,
                              ps,
                              &wh->c_hash,
                              &pd))
  {
    GNUNET_break_op (0);
    GNUNET_free (wh);
    return NULL;
  }
  wh->pk.key.rsa_public_key
    = GNUNET_CRYPTO_rsa_public_key_dup (pk->key.rsa_public_key);
  wh->wh2 = TALER_EXCHANGE_withdraw2 (exchange,
                                      &pd,
                                      reserve_priv,
                                      &handle_reserve_withdraw_finished,
                                      wh);
  GNUNET_free (pd.coin_ev);
  return wh;
}


/**
 * Cancel a withdraw status request.  This function cannot be used
 * on a request handle if a response is already served for it.
 *
 * @param wh the withdraw sign request handle
 */
void
TALER_EXCHANGE_withdraw_cancel (struct TALER_EXCHANGE_WithdrawHandle *wh)
{
  if (NULL != wh->wh2)
  {
    TALER_EXCHANGE_withdraw2_cancel (wh->wh2);
    wh->wh2 = NULL;
  }
  GNUNET_CRYPTO_rsa_public_key_free (wh->pk.key.rsa_public_key);
  GNUNET_free (wh);
}
