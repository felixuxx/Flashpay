/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

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
 * @file taler-exchange-httpd_age-withdraw_reveal.c
 * @brief Handle /age-withdraw/$ACH/reveal requests
 * @author Özgür Kesim
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_mhd.h"
#include "taler-exchange-httpd_age-withdraw_reveal.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"

/**
 * State for an /age-withdraw/$ACH/reveal operation.
 */
struct AgeRevealContext
{

  /**
   * Commitment for the age-withdraw operation.
   */
  struct TALER_AgeWithdrawCommitmentHashP ach;

  /**
   * Public key of the reserve for with the age-withdraw commitment was
   * originally made.  This parameter is provided by the client again
   * during the call to reveal in order to save a database-lookup .
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Number of coins/denonations in the reveal
   */
  uint32_t num_coins;

  /**
   * TODO:oec num_coins denoms
   */
  struct TALER_DenominationHashP *denoms_h;

  /**
   * TODO:oec num_coins blinded coins
   */
  struct TALER_BlindedCoinHashP *coin_evs;

  /**
   * TODO:oec num_coins*(kappa - 1) disclosed coins
   */
  struct GNUNET_CRYPTO_EddsaPrivateKey *disclosed_coins;

};

/**
 * Helper function to free resources in the context
 */
void
age_reveal_context_free (struct AgeRevealContext *actx)
{
  GNUNET_free (actx->denoms_h);
  GNUNET_free (actx->coin_evs);
  GNUNET_free (actx->disclosed_coins);
}


/**
 * Handle a "/age-withdraw/$ACH/reveal request.  Parses the given JSON
 * ... TODO:oec:description
 *
 * @param connection The MHD connection to handle
 * @param actx The context of the operation, only partially built at call time
 * @param j_denoms_h Array of hashes of the denominations for the withdrawal, in JSON format
 * @param j_coin_evs The blinded envelopes in JSON format for the coins that are not revealed and will be signed on success
 * @param j_disclosed_coins The n*(kappa-1) disclosed coins' private keys in JSON format, from which all other attributes (age restriction, blinding, nonce) will be derived from
 */
MHD_RESULT
handle_age_withdraw_reveal_json (
  struct MHD_Connection *connection,
  struct AgeRevealContext *actx,
  const json_t *j_denoms_h,
  const json_t *j_coin_evs,
  const json_t *j_disclosed_coins)
{
  MHD_RESULT mhd_ret = MHD_NO;

  /* Verify JSON-structure consistency */
  {
    const char *error = NULL;

    actx->num_coins = json_array_size (j_denoms_h); /* 0, if j_denoms_h is not an array */

    if (! json_is_array (j_denoms_h))
      error = "denoms_h must be an array";
    else if (! json_is_array (j_coin_evs))
      error = "coin_evs must be an array";
    else if (! json_is_array (j_disclosed_coins))
      error = "disclosed_coins must be an array";
    else if (actx->num_coins == 0)
      error = "denoms_h must not be empty";
    else if (actx->num_coins != json_array_size (j_coin_evs))
      error = "denoms_h and coins_evs must be arrays of the same size";
    else if (actx->num_coins * (TALER_CNC_KAPPA - 1)
             != json_array_size (j_disclosed_coins))
      error = "the size of array disclosed_coins must be "
              TALER_CNC_KAPPA_MINUS_ONE_STR " times of the size of denoms_h";
    else if (actx->num_coins > TALER_MAX_FRESH_COINS)
      /**
       * FIXME?: If the user had commited to more than the maximum coins allowed,
       * the reserve has been charged, but now the user can not withdraw any money
       * from it. How can the user get their money back?
       **/
      error = "maximum number of coins that can be withdrawn has been exceeded";

    if (NULL != error)
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                         error);
  }

  /* Parse denomination keys */
  {
    unsigned int idx;
    json_t *jh;

    actx->denoms_h = GNUNET_new_array (actx->num_coins,
                                       struct TALER_DenominationHashP);

    json_array_foreach (j_denoms_h, idx, jh) {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto (NULL, &actx->denoms_h[idx]),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (jh, spec, NULL, NULL))
      {
        char msg[256] = {0};
        GNUNET_snprintf (msg,
                         sizeof(msg),
                         "couldn't parse entry no. %d in array denoms_h",
                         idx + 1);
        mhd_ret = TALER_MHD_reply_with_error (connection,
                                              MHD_HTTP_BAD_REQUEST,
                                              TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                              msg);
        goto EXIT;
      }

    };
  }

  /* Parse blinded envelopes */
  {
    unsigned int idx;
    json_t *ce;

    actx->coin_evs = GNUNET_new_array (actx->num_coins,
                                       struct TALER_BlindedCoinHashP);

    json_array_foreach (j_coin_evs, idx, ce) {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto (NULL, &actx->coin_evs[idx]),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (ce, spec, NULL, NULL))
      {
        char msg[256] = {0};
        GNUNET_snprintf (msg,
                         sizeof(msg),
                         "couldn't parse entry no. %d in array coin_evs",
                         idx + 1);
        mhd_ret = TALER_MHD_reply_with_error (connection,
                                              MHD_HTTP_BAD_REQUEST,
                                              TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                              msg);
        goto EXIT;
      }
    };
  }

  /* Parse diclosed keys */
  {
    unsigned int idx;
    json_t *dc;

    actx->disclosed_coins = GNUNET_new_array (
      actx->num_coins * (TALER_CNC_KAPPA),
      struct GNUNET_CRYPTO_EddsaPrivateKey);

    json_array_foreach (j_coin_evs, idx, dc) {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto (NULL, &actx->disclosed_coins[idx]),
        GNUNET_JSON_spec_end ()
      };

      if (GNUNET_OK !=
          GNUNET_JSON_parse (dc, spec, NULL, NULL))
      {
        char msg[256] = {0};
        GNUNET_snprintf (msg,
                         sizeof(msg),
                         "couldn't parse entry no. %d in array disclosed_coins",
                         idx + 1);
        mhd_ret = TALER_MHD_reply_with_error (connection,
                                              MHD_HTTP_BAD_REQUEST,
                                              TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                              msg);
        goto EXIT;
      }
    };

  }

  /* TODO:oec: find commitment */
  /* TODO:oec: check validity of denoms */
  /* TODO:oec: check amount total against denoms */
  /* TODO:oec: compute the disclosed blinded coins */
  /* TODO:oec: generate h_commitment_comp */
  /* TODO:oec: compare h_commitment_comp against h_commitment */
  /* TODO:oec: sign the coins */
  /* TODO:oec: send response */


  /* TODO */
EXIT:
  age_reveal_context_free (actx);
  return mhd_ret;
}


MHD_RESULT
TEH_handler_age_withdraw_reveal (
  struct TEH_RequestContext *rc,
  const struct TALER_AgeWithdrawCommitmentHashP *ach,
  const json_t *root)
{
  struct AgeRevealContext actx = {0};
  json_t *j_denoms_h;
  json_t *j_coin_evs;
  json_t *j_disclosed_coins;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("reserve_pub", &actx.reserve_pub),
    GNUNET_JSON_spec_json ("denoms_h", &j_denoms_h),
    GNUNET_JSON_spec_json ("coin_evs", &j_coin_evs),
    GNUNET_JSON_spec_json ("disclosed_coins", &j_disclosed_coins),
    GNUNET_JSON_spec_end ()
  };

  actx.ach = *ach;

  /* Parse JSON body*/
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (rc->connection,
                                     root,
                                     spec);
    if (GNUNET_OK != res)
    {
      GNUNET_break_op (0);
      return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
    }
  }


  /* handle reveal request */
  {
    MHD_RESULT res;

    res = handle_age_withdraw_reveal_json (rc->connection,
                                           &actx,
                                           j_denoms_h,
                                           j_coin_evs,
                                           j_disclosed_coins);

    GNUNET_JSON_parse_free (spec);
    return res;
  }

}


/* end of taler-exchange-httpd_age-withdraw_reveal.c */
