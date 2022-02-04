/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
   * Reserve private key.
   */
  const struct TALER_ReservePrivateKeyP *reserve_priv;

  /**
   * Secrets of the planchet.
   */
  struct TALER_PlanchetSecretsP ps;

  /**
   * Details of the planchet.
   */
  struct TALER_PlanchetDetail pd;

  /**
   * Values of the @cipher selected
   */
  struct TALER_ExchangeWithdrawValues alg_values;

  /**
   * Denomination key we are withdrawing.
   */
  struct TALER_EXCHANGE_DenomPublicKey pk;

  /**
   * Hash of the public key of the coin we are signing.
   */
  struct TALER_CoinPubHash c_hash;

  /**
   * Handler for the CS R request (only used for TALER_DENOMINATION_CS denominations)
   */
  struct TALER_EXCHANGE_CsRHandle *csrh;

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
  const struct TALER_BlindedDenominationSignature *blind_sig)
{
  struct TALER_EXCHANGE_WithdrawHandle *wh = cls;
  struct TALER_EXCHANGE_WithdrawResponse wr = {
    .hr = *hr
  };

  wh->wh2 = NULL;
  switch (hr->http_status)
  {
  case MHD_HTTP_OK:
    {
      struct TALER_FreshCoin fc;

      if (GNUNET_OK !=
          TALER_planchet_to_coin (&wh->pk.key,
                                  blind_sig,
                                  &wh->ps,
                                  &wh->c_hash,
                                  &wh->alg_values,
                                  &fc))
      {
        wr.hr.http_status = 0;
        wr.hr.ec = TALER_EC_EXCHANGE_WITHDRAW_UNBLIND_FAILURE;
        break;
      }
      wr.details.success.sig = fc.sig;
      break;
    }
  case MHD_HTTP_ACCEPTED:
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_uint64 ("payment_target_uuid",
                                 &wr.details.accepted.payment_target_uuid),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (hr->reply,
                             spec,
                             NULL, NULL))
      {
        GNUNET_break_op (0);
        wr.hr.http_status = 0;
        wr.hr.ec = TALER_EC_GENERIC_REPLY_MALFORMED;
        break;
      }
    }
    break;
  default:
    break;
  }
  wh->cb (wh->cb_cls,
          &wr);
  if (MHD_HTTP_OK == hr->http_status)
    TALER_denom_sig_free (&wr.details.success.sig);
  TALER_EXCHANGE_withdraw_cancel (wh);
}


/**
 * Function called when stage 1 of CS withdraw is finished (request r_pub's)
 *
 * @param cls
 */
static void
withdraw_cs_stage_two_callback (void *cls,
                                const struct TALER_EXCHANGE_CsRResponse *csrr)
{
  struct TALER_EXCHANGE_WithdrawHandle *wh = cls;

  wh->csrh = NULL;

  GNUNET_assert (TALER_DENOMINATION_CS == wh->pk.key.cipher);

  switch (csrr->hr.http_status)
  {
  case MHD_HTTP_OK:
    wh->alg_values.details.cs_values.r_pub = csrr->details.success.r_pubs;
    TALER_planchet_blinding_secret_create (&wh->ps,
                                           &wh->alg_values);
    if (GNUNET_OK !=
        TALER_planchet_prepare (&wh->pk.key,
                                &wh->alg_values,
                                &wh->ps,
                                &wh->c_hash,
                                &wh->pd))
    {
      GNUNET_break (0);
      GNUNET_free (wh);
    }
    wh->wh2 = TALER_EXCHANGE_withdraw2 (wh->exchange,
                                        &wh->pd,
                                        wh->reserve_priv,
                                        &handle_reserve_withdraw_finished,
                                        wh);
    break;
  default:
    {
      // the CSR request went wrong -> serve response to the callback
      struct TALER_EXCHANGE_WithdrawResponse wr = {
        .hr = csrr->hr
      };
      wh->cb (wh->cb_cls,
              &wr);
      TALER_EXCHANGE_withdraw_cancel (wh);
      break;
    }
  }
}


struct TALER_EXCHANGE_WithdrawHandle *
TALER_EXCHANGE_withdraw (
  struct TALER_EXCHANGE_Handle *exchange,
  const struct TALER_EXCHANGE_DenomPublicKey *pk,
  const struct TALER_ReservePrivateKeyP *reserve_priv,
  struct TALER_PlanchetSecretsP *ps,
  TALER_EXCHANGE_WithdrawCallback res_cb,
  void *res_cb_cls)
{
  struct TALER_EXCHANGE_WithdrawHandle *wh;

  wh = GNUNET_new (struct TALER_EXCHANGE_WithdrawHandle);
  wh->exchange = exchange;
  wh->cb = res_cb;
  wh->cb_cls = res_cb_cls;
  wh->reserve_priv = reserve_priv;
  wh->ps = *ps;
  wh->pk = *pk;
  wh->csrh = NULL;

  TALER_denom_pub_deep_copy (&wh->pk.key,
                             &pk->key);

  switch (pk->key.cipher)
  {
  case TALER_DENOMINATION_RSA:
    struct TALER_CoinSpendPrivateKeyP priv;
    alg_values.cipher = TALER_DENOMINATION_RSA;

    TALER_planchet_setup_coin_priv (ps, &wh->alg_values, &priv);

    if (GNUNET_OK !=
        TALER_planchet_prepare (&pk->key,
                                &wh->alg_values,
                                ps,
                                &wh->c_hash,
                                &wh->pd))
    {
      GNUNET_break (0);
      GNUNET_free (wh);
      return NULL;
    }
    wh->wh2 = TALER_EXCHANGE_withdraw2 (exchange,
                                        &wh->pd,
                                        wh->reserve_priv,
                                        &handle_reserve_withdraw_finished,
                                        wh);
    break;
  case TALER_DENOMINATION_CS:
    wh->pd.blinded_planchet.cipher = TALER_DENOMINATION_CS;

    /**
     * This part is a bit hacky..
     * due to the reason that Withdraw tests use the same private key coin to sign,
     * the same Withdraw nonce will be derived.
     * In a normal withdrawal TALER_cs_withdraw_nonce_derive is used.
     * As a hacky solution, we generate the nonce here randomly.
     */
    TALER_cs_withdraw_nonce_generate (&wh->pd.blinded_planchet.details.
                                      cs_blinded_planchet.nonce);
    wh->csrh = TALER_EXCHANGE_csr (exchange,
                                   pk,
                                   &wh->pd.blinded_planchet.details.
                                   cs_blinded_planchet.nonce,
                                   &withdraw_cs_stage_two_callback,
                                   wh);
    break;
  default:
    GNUNET_break (0);
    GNUNET_free (wh);
    return NULL;
  }
  TALER_blinded_planchet_free (&wh->pd.blinded_planchet);
  return wh;
}


void
TALER_EXCHANGE_withdraw_cancel (struct TALER_EXCHANGE_WithdrawHandle *wh)
{
  if (NULL != wh->csrh)
  {
    TALER_EXCHANGE_csr_cancel (wh->csrh);
    wh->csrh = NULL;
  }
  if (NULL != wh->wh2)
  {
    TALER_EXCHANGE_withdraw2_cancel (wh->wh2);
    wh->wh2 = NULL;
  }
  TALER_denom_pub_free (&wh->pk.key);
  GNUNET_free (wh);
}
