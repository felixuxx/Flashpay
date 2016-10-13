/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 Inria & GNUnet e.V.

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
 * @file taler-exchange-httpd_refresh.c
 * @brief Handle /refresh/ requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler-exchange-httpd_parsing.h"
#include "taler-exchange-httpd_mhd.h"
#include "taler-exchange-httpd_refresh.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"


/**
 * Handle a "/refresh/melt" request after the main JSON parsing has happened.
 * We now need to validate the coins being melted and the session signature
 * and then hand things of to execute the melt operation.
 *
 * @param connection the MHD connection to handle
 * @param num_new_denoms number of coins to be created, size of y-dimension of @a commit_link array
 * @param denom_pubs array of @a num_new_denoms keys
 * @param coin_melt_details melting details
 * @param session_hash hash over the data that the client commits to
 * @param commit_coin 2d array of coin commitments (what the exchange is to sign
 *                    once the "/refres/reveal" of cut and choose is done)
 * @param transfer_pubs array of transfer public keys (which the exchange is
 *                    to return via "/refresh/link" to enable linkage in the
 *                    future) of length #TALER_CNC_KAPPA
 * @return MHD result code
 */
static int
handle_refresh_melt_binary (struct MHD_Connection *connection,
                            unsigned int num_new_denoms,
                            const struct TALER_DenominationPublicKey *denom_pubs,
                            const struct TEH_DB_MeltDetails *coin_melt_details,
                            const struct GNUNET_HashCode *session_hash,
                            struct TALER_EXCHANGEDB_RefreshCommitCoin *const* commit_coin,
                            const struct TALER_TransferPublicKeyP *transfer_pubs)
{
  unsigned int i;
  struct TEH_KS_StateHandle *key_state;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dk;
  struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct TALER_Amount cost;
  struct TALER_Amount total_cost;
  struct TALER_Amount value;
  struct TALER_Amount fee_withdraw;
  struct TALER_Amount fee_melt;
  struct TALER_Amount total_melt;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "melt request for session %s\n",
              GNUNET_h2s (session_hash));

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (TEH_exchange_currency_string,
                                        &total_cost));
  key_state = TEH_KS_acquire ();
  for (i=0;i<num_new_denoms;i++)
  {
    dk = TEH_KS_denomination_key_lookup (key_state,
                                         &denom_pubs[i],
                                         TEH_KS_DKU_WITHDRAW);
    if (NULL == dk)
    {
      GNUNET_break_op (0);
      TEH_KS_release (key_state);
      return TEH_RESPONSE_reply_arg_invalid (connection,
                                             "new_denoms");
    }
    dki = &dk->issue;
    TALER_amount_ntoh (&value,
                       &dki->properties.value);
    TALER_amount_ntoh (&fee_withdraw,
                       &dki->properties.fee_withdraw);
    if ( (GNUNET_OK !=
          TALER_amount_add (&cost,
                            &value,
                            &fee_withdraw)) ||
         (GNUNET_OK !=
          TALER_amount_add (&total_cost,
                            &cost,
                            &total_cost)) )
    {
      GNUNET_break_op (0);
      TEH_KS_release (key_state);
      return TEH_RESPONSE_reply_internal_error (connection,
                                                "cost calculation failure");
    }
  }

  dk = TEH_KS_denomination_key_lookup (key_state,
                                       &coin_melt_details->coin_info.denom_pub,
                                       TEH_KS_DKU_DEPOSIT);
  if (NULL == dk)
  {
    GNUNET_break (0);
    return TEH_RESPONSE_reply_arg_invalid (connection,
                                           "denom_pub");
  }
  dki = &dk->issue;
  TALER_amount_ntoh (&fee_melt,
                     &dki->properties.fee_refresh);
  if (GNUNET_OK !=
      TALER_amount_subtract (&total_melt,
                             &coin_melt_details->melt_amount_with_fee,
                             &fee_melt))
  {
    GNUNET_break_op (0);
    TEH_KS_release (key_state);
    return TEH_RESPONSE_reply_external_error (connection,
                                              "Melt contribution below melting fee");
  }
  TEH_KS_release (key_state);
  if (0 !=
      TALER_amount_cmp (&total_cost,
                        &total_melt))
  {
    GNUNET_break_op (0);
    /* We require total value of coins being melted and
       total value of coins being generated to match! */
    return TEH_RESPONSE_reply_json_pack (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         "{s:s}",
                                         "error", "value mismatch");
  }
  return TEH_DB_execute_refresh_melt (connection,
                                      session_hash,
                                      num_new_denoms,
                                      denom_pubs,
                                      coin_melt_details,
                                      commit_coin,
                                      transfer_pubs);
}


/**
 * Extract public coin information from a JSON object.
 *
 * @param connection the connection to send error responses to
 * @param coin_info the JSON object to extract the coin info from
 * @param[out] r_melt_detail set to details about the coin's melting permission (if valid)
 * @return #GNUNET_YES if coin public info in JSON was valid
 *         #GNUNET_NO JSON was invalid, response was generated
 *         #GNUNET_SYSERR on internal error
 */
static int
get_coin_public_info (struct MHD_Connection *connection,
                      const json_t *coin_info,
                      struct TEH_DB_MeltDetails *r_melt_detail)
{
  int ret;
  struct TALER_CoinSpendSignatureP melt_sig;
  struct TALER_DenominationSignature sig;
  struct TALER_DenominationPublicKey pk;
  struct TALER_Amount amount;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("coin_pub", &r_melt_detail->coin_info.coin_pub),
    TALER_JSON_spec_denomination_signature ("denom_sig", &sig),
    TALER_JSON_spec_denomination_public_key ("denom_pub", &pk),
    GNUNET_JSON_spec_fixed_auto ("confirm_sig", &melt_sig),
    TALER_JSON_spec_amount ("value_with_fee", &amount),
    GNUNET_JSON_spec_end ()
  };

  ret = TEH_PARSE_json_data (connection,
                             coin_info,
                             spec);
  if (GNUNET_OK != ret)
  {
    GNUNET_break_op (0);
    return ret;
  }
  /* check exchange signature on the coin */
  r_melt_detail->coin_info.denom_sig = sig;
  r_melt_detail->coin_info.denom_pub = pk;
  if (GNUNET_OK !=
      TALER_test_coin_valid (&r_melt_detail->coin_info))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    r_melt_detail->coin_info.denom_sig.rsa_signature = NULL;
    r_melt_detail->coin_info.denom_pub.rsa_public_key = NULL;
    return (MHD_YES ==
            TEH_RESPONSE_reply_signature_invalid (connection,
                                                  "denom_sig"))
      ? GNUNET_NO : GNUNET_SYSERR;
  }
  r_melt_detail->melt_sig = melt_sig;
  r_melt_detail->melt_amount_with_fee = amount;
  return GNUNET_OK;
}


/**
 * Verify that the signature shows that this coin is to be melted into
 * the given @a session_hash melting session, and that this is a valid
 * coin (we know the denomination key and the signature on it is
 * valid).  Essentially, this does all of the per-coin checks that can
 * be done before the transaction starts.
 *
 * @param connection the connection to send error responses to
 * @param session_hash hash over refresh session the coin is melted into
 * @param[in,out] melt_detail details about the coin's melting permission,
 *                            the `melt_fee` is updated
 * @return #GNUNET_YES if coin public info in JSON was valid
 *         #GNUNET_NO JSON was invalid, response was generated
 *         #GNUNET_SYSERR on internal error
 */
static int
verify_coin_public_info (struct MHD_Connection *connection,
                         const struct GNUNET_HashCode *session_hash,
                         struct TEH_DB_MeltDetails *melt_detail)
{
  struct TALER_RefreshMeltCoinAffirmationPS body;
  struct TEH_KS_StateHandle *key_state;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;
  struct TALER_Amount fee_refresh;

  key_state = TEH_KS_acquire ();
  dki = TEH_KS_denomination_key_lookup (key_state,
                                        &melt_detail->coin_info.denom_pub,
					TEH_KS_DKU_DEPOSIT);
  if (NULL == dki)
  {
    TEH_KS_release (key_state);
    TALER_LOG_WARNING ("Unknown denomination key in /refresh/melt request\n");
    return TEH_RESPONSE_reply_arg_unknown (connection,
                                           "denom_pub");
  }
  TALER_amount_ntoh (&fee_refresh,
                     &dki->issue.properties.fee_refresh);
  melt_detail->melt_fee = fee_refresh;
  body.purpose.size = htonl (sizeof (struct TALER_RefreshMeltCoinAffirmationPS));
  body.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT);
  body.session_hash = *session_hash;
  TALER_amount_hton (&body.amount_with_fee,
                     &melt_detail->melt_amount_with_fee);
  TALER_amount_hton (&body.melt_fee,
                     &fee_refresh);
  body.coin_pub = melt_detail->coin_info.coin_pub;
  if (TALER_amount_cmp (&fee_refresh,
                        &melt_detail->melt_amount_with_fee) > 0)
  {
    GNUNET_break_op (0);
    TEH_KS_release (key_state);
    return (MHD_YES ==
            TEH_RESPONSE_reply_external_error (connection,
                                               "melt amount smaller than melting fee"))
      ? GNUNET_NO : GNUNET_SYSERR;
  }

  TEH_KS_release (key_state);
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_MELT,
                                  &body.purpose,
                                  &melt_detail->melt_sig.eddsa_signature,
                                  &melt_detail->coin_info.coin_pub.eddsa_pub))
  {
    GNUNET_break_op (0);
    if (MHD_YES !=
        TEH_RESPONSE_reply_signature_invalid (connection,
                                              "confirm_sig"))
      return GNUNET_SYSERR;
    return GNUNET_NO;
  }
  return GNUNET_OK;
}


/**
 * Release memory from the @a commit_coin array.
 *
 * @param commit_coin array to release
 * @param kappa size of 1st dimension
 * @param num_new_coins size of 2nd dimension
 */
static void
free_commit_coins (struct TALER_EXCHANGEDB_RefreshCommitCoin **commit_coin,
                   unsigned int kappa,
                   unsigned int num_new_coins)
{
  unsigned int i;
  unsigned int j;

  for (i=0;i<kappa;i++)
  {
    if (NULL == commit_coin[i])
      break;
    for (j=0;j<num_new_coins;j++)
      GNUNET_free_non_null (commit_coin[i][j].coin_ev);
    GNUNET_free (commit_coin[i]);
  }
}


/**
 * Handle a "/refresh/melt" request after the first parsing has happened.
 * We now need to validate the coins being melted and the session signature
 * and then hand things of to execute the melt operation.  This function
 * parses the JSON arrays and then passes processing on to
 * #handle_refresh_melt_binary().
 *
 * @param connection the MHD connection to handle
 * @param new_denoms array of denomination keys
 * @param melt_coin coin to melt
 * @param transfer_pubs #TALER_CNC_KAPPA-dimensional array of transfer keys
 * @param coin_evs #TALER_CNC_KAPPA-dimensional array of envelopes to sign
 * @return MHD result code
 */
static int
handle_refresh_melt_json (struct MHD_Connection *connection,
                          const json_t *new_denoms,
                          const json_t *melt_coin,
                          const json_t *transfer_pubs,
                          const json_t *coin_evs)
{
  int res;
  unsigned int i;
  unsigned int j;
  struct TALER_DenominationPublicKey *denom_pubs;
  unsigned int num_newcoins;
  struct TEH_DB_MeltDetails coin_melt_details;
  struct GNUNET_HashCode session_hash;
  struct GNUNET_HashContext *hash_context;
  struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coin[TALER_CNC_KAPPA];
  struct TALER_TransferPublicKeyP transfer_pub[TALER_CNC_KAPPA];

  /* For the signature check, we hash most of the inputs together
     (except for the signatures on the coins). */
  hash_context = GNUNET_CRYPTO_hash_context_start ();

  for (i = 0; i < TALER_CNC_KAPPA; i++)
  {
    struct GNUNET_JSON_Specification trans_spec[] = {
      GNUNET_JSON_spec_fixed_auto (NULL, &transfer_pub[i]),
      GNUNET_JSON_spec_end ()
    };

    res = TEH_PARSE_json_array (connection,
                                transfer_pubs,
                                trans_spec,
                                i, -1);
    if (GNUNET_OK != res)
    {
      GNUNET_break_op (0);
      res = (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
      goto cleanup_hc;
    }
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &transfer_pub[i],
                                     sizeof (struct TALER_TransferPublicKeyP));
  }


  num_newcoins = json_array_size (new_denoms);
  denom_pubs = GNUNET_new_array (num_newcoins,
                                 struct TALER_DenominationPublicKey);
  for (i=0;i<num_newcoins;i++)
  {
    char *buf;
    size_t buf_size;
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_denomination_public_key (NULL,
                                               &denom_pubs[i]),
      GNUNET_JSON_spec_end ()
    };

    res = TEH_PARSE_json_array (connection,
                                new_denoms,
                                spec,
                                i, -1);
    if (GNUNET_OK != res)
    {
      res = (GNUNET_NO == res) ? MHD_YES : MHD_NO;
      goto cleanup_denoms;
    }
    buf_size = GNUNET_CRYPTO_rsa_public_key_encode (denom_pubs[i].rsa_public_key,
                                                    &buf);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     buf,
                                     buf_size);
    GNUNET_free (buf);
  }

  {
    /* decode JSON data on coin to melt */
    struct TALER_AmountNBO melt_amount;

    res = get_coin_public_info (connection,
                                melt_coin,
                                &coin_melt_details);
    if (GNUNET_OK != res)
    {
      GNUNET_break_op (0);
      res = (GNUNET_NO == res) ? MHD_YES : MHD_NO;
      goto cleanup_melt_details;
    }
    TALER_amount_hton (&melt_amount,
                       &coin_melt_details.melt_amount_with_fee);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &coin_melt_details.coin_info.coin_pub,
                                     sizeof (struct TALER_CoinSpendPublicKeyP));
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &melt_amount,
                                     sizeof (struct TALER_AmountNBO));
  }

  /* parse JSON arrays into binary arrays and hash everything
     together for the signature check */
  memset (commit_coin,
          0,
          sizeof (commit_coin));
  for (i = 0; i < TALER_CNC_KAPPA; i++)
  {
    commit_coin[i] = GNUNET_new_array (num_newcoins,
                                       struct TALER_EXCHANGEDB_RefreshCommitCoin);
    for (j = 0; j < num_newcoins; j++)
    {
      struct TALER_EXCHANGEDB_RefreshCommitCoin *rcc = &commit_coin[i][j];
      struct GNUNET_JSON_Specification coin_spec[] = {
        GNUNET_JSON_spec_varsize (NULL,
                                  (void **) &rcc->coin_ev,
                                  &rcc->coin_ev_size),
        GNUNET_JSON_spec_end ()
      };

      res = TEH_PARSE_json_array (connection,
                                  coin_evs,
                                  coin_spec,
                                  i, j, -1);
      if (GNUNET_OK != res)
      {
        GNUNET_break_op (0);
        res = (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
        goto cleanup;
      }

      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       rcc->coin_ev,
                                       rcc->coin_ev_size);
    }
  }

  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &session_hash);
  hash_context = NULL;
  /* verify signature on coins to melt */
  res = verify_coin_public_info (connection,
                                 &session_hash,
                                 &coin_melt_details);
  if (GNUNET_OK != res)
  {
    GNUNET_break_op (0);
    res = (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    goto cleanup;
  }

  /* execute commit */
  res = handle_refresh_melt_binary (connection,
                                    num_newcoins,
                                    denom_pubs,
                                    &coin_melt_details,
                                    &session_hash,
                                    commit_coin,
                                    transfer_pub);
 cleanup:
  free_commit_coins (commit_coin,
                     TALER_CNC_KAPPA,
                     num_newcoins);
 cleanup_melt_details:
  if (NULL != coin_melt_details.coin_info.denom_pub.rsa_public_key)
    GNUNET_CRYPTO_rsa_public_key_free (coin_melt_details.coin_info.denom_pub.rsa_public_key);
  if (NULL != coin_melt_details.coin_info.denom_sig.rsa_signature)
    GNUNET_CRYPTO_rsa_signature_free (coin_melt_details.coin_info.denom_sig.rsa_signature);
 cleanup_denoms:
  if (NULL != denom_pubs)
  {
    for (j=0;j<num_newcoins;j++)
      if (NULL != denom_pubs[j].rsa_public_key)
        GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j].rsa_public_key);
    GNUNET_free (denom_pubs);
  }
 cleanup_hc:
  if (NULL != hash_context)
    GNUNET_CRYPTO_hash_context_abort (hash_context);
  return res;
}


/**
 * Handle a "/refresh/melt" request.  Parses the request into the JSON
 * components and then hands things of to #handle_refresh_melt_json()
 * to validate the melted coins, the signature and execute the melt
 * using TEH_DB_execute_refresh_melt().
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
 */
int
TEH_REFRESH_handler_refresh_melt (struct TEH_RequestHandler *rh,
                                  struct MHD_Connection *connection,
                                  void **connection_cls,
                                  const char *upload_data,
                                  size_t *upload_data_size)
{
  json_t *root;
  json_t *new_denoms;
  json_t *melt_coin;
  json_t *coin_evs;
  json_t *transfer_pubs;
  int res;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_json ("new_denoms", &new_denoms),
    GNUNET_JSON_spec_json ("melt_coin", &melt_coin),
    GNUNET_JSON_spec_json ("coin_evs", &coin_evs),
    GNUNET_JSON_spec_json ("transfer_pubs", &transfer_pubs),
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

  /* Determine dimensionality of the request (kappa, #old and #new coins) */
  if (TALER_CNC_KAPPA != json_array_size (coin_evs))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TEH_RESPONSE_reply_arg_invalid (connection,
                                           "coin_evs");
  }
  if (TALER_CNC_KAPPA != json_array_size (transfer_pubs))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TEH_RESPONSE_reply_arg_invalid (connection,
                                           "transfer_pubs");
  }
  res = handle_refresh_melt_json (connection,
                                  new_denoms,
                                  melt_coin,
                                  transfer_pubs,
                                  coin_evs);
  GNUNET_JSON_parse_free (spec);
  return res;
}


/**
 * Handle a "/refresh/reveal" request.   Parses the given JSON
 * transfer private keys and if successful, passes everything to
 * #TEH_DB_execute_refresh_reveal() which will verify that the
 * revealed information is valid then returns the signed refreshed
 * coins.
 *
 * @param connection the MHD connection to handle
 * @param session_hash hash identifying the melting session
 * @param tp_json private transfer keys in JSON format
 * @return MHD result code
  */
static int
handle_refresh_reveal_json (struct MHD_Connection *connection,
                            const struct GNUNET_HashCode *session_hash,
                            const json_t *tp_json)
{
  struct TALER_TransferPrivateKeyP transfer_privs[TALER_CNC_KAPPA - 1];
  unsigned int i;
  int res;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "reveal request for session %s\n",
              GNUNET_h2s (session_hash));

  res = GNUNET_OK;
  for (i = 0; i < TALER_CNC_KAPPA - 1; i++)
  {
    struct GNUNET_JSON_Specification tp_spec[] = {
      GNUNET_JSON_spec_fixed_auto (NULL, &transfer_privs[i]),
      GNUNET_JSON_spec_end ()
    };

    if (GNUNET_OK != res)
      break;
    res = TEH_PARSE_json_array (connection,
                                tp_json,
                                tp_spec,
                                i, -1);
    GNUNET_break_op (GNUNET_OK == res);
  }
  if (GNUNET_OK != res)
    res = (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  else
    res = TEH_DB_execute_refresh_reveal (connection,
					 session_hash,
					 transfer_privs);
  return res;
}


/**
 * Handle a "/refresh/reveal" request. This time, the client reveals
 * the private transfer keys except for the cut-and-choose value
 * returned from "/refresh/melt".  This function parses the revealed
 * keys and secrets and ultimately passes everything to
 * #TEH_DB_execute_refresh_reveal() which will verify that the
 * revealed information is valid then returns the signed refreshed
 * coins.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TEH_REFRESH_handler_refresh_reveal (struct TEH_RequestHandler *rh,
                                    struct MHD_Connection *connection,
                                    void **connection_cls,
                                    const char *upload_data,
                                    size_t *upload_data_size)
{
  struct GNUNET_HashCode session_hash;
  int res;
  json_t *root;
  json_t *transfer_privs;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("session_hash", &session_hash),
    GNUNET_JSON_spec_json ("transfer_privs", &transfer_privs),
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
  {
    GNUNET_break_op (0);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }
  /* Determine dimensionality of the request (kappa and #old coins) */
  /* Note we do +1 as 1 row (cut-and-choose!) is missing! */
  if (TALER_CNC_KAPPA != json_array_size (transfer_privs) + 1)
  {
    GNUNET_JSON_parse_free (spec);
    GNUNET_break_op (0);
    return TEH_RESPONSE_reply_arg_invalid (connection,
                                           "transfer_privs");
  }
  res = handle_refresh_reveal_json (connection,
                                    &session_hash,
                                    transfer_privs);
  GNUNET_JSON_parse_free (spec);
  return res;
}


/**
 * Handle a "/refresh/link" request.  Note that for "/refresh/link"
 * we do use a simple HTTP GET, and a HTTP POST!
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param[in,out] connection_cls the connection's closure (can be updated)
 * @param upload_data upload data
 * @param[in,out] upload_data_size number of bytes (left) in @a upload_data
 * @return MHD result code
  */
int
TEH_REFRESH_handler_refresh_link (struct TEH_RequestHandler *rh,
                                  struct MHD_Connection *connection,
                                  void **connection_cls,
                                  const char *upload_data,
                                  size_t *upload_data_size)
{
  struct TALER_CoinSpendPublicKeyP coin_pub;
  int res;

  res = TEH_PARSE_mhd_request_arg_data (connection,
                                        "coin_pub",
                                        &coin_pub,
                                        sizeof (struct TALER_CoinSpendPublicKeyP));
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if (GNUNET_OK != res)
    return MHD_YES;
  return TEH_DB_execute_refresh_link (connection,
                                      &coin_pub);
}


/* end of taler-exchange-httpd_refresh.c */
