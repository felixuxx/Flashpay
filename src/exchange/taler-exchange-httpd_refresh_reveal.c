/*
  This file is part of TALER
  Copyright (C) 2014-2017 Inria & GNUnet e.V.

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
 * @file taler-exchange-httpd_refresh_reveal.c
 * @brief Handle /refresh/reveal requests
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
#include "taler-exchange-httpd_refresh_reveal.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"


/**
 * How often should we retry a transaction before giving up
 * (for transactions resulting in serialization/dead locks only).
 */
#define MAX_TRANSACTION_COMMIT_RETRIES 3

/**
 * Code to begin a transaction, must be inline as we define a block
 * that ends with #COMMIT_TRANSACTION() within which we perform a number
 * of retries.  Note that this code may call "return" internally, so
 * it must be called within a function where any cleanup will be done
 * by the caller. Furthermore, the function's return value must
 * match that of a #TEH_RESPONSE_reply_internal_db_error() status code.
 *
 * @param session session handle
 * @param connection connection handle
 */
#define START_TRANSACTION(session,connection)                 \
{ /* start new scope, will be ended by COMMIT_TRANSACTION() */\
  unsigned int transaction_retries = 0;                       \
  enum GNUNET_DB_QueryStatus transaction_commit_result;       \
transaction_start_label: /* we will use goto for retries */   \
  if (GNUNET_OK !=                                            \
      TEH_plugin->start (TEH_plugin->cls,                     \
                         session))                            \
  {                                                           \
    GNUNET_break (0);                                         \
    return TEH_RESPONSE_reply_internal_db_error (connection, \
						 TALER_EC_DB_START_FAILED);	     \
  }

/**
 * Code to conclude a transaction, dual to #START_TRANSACTION().  Note
 * that this code may call "return" internally, so it must be called
 * within a function where any cleanup will be done by the caller.
 * Furthermore, the function's return value must match that of a
 * #TEH_RESPONSE_reply_internal_db_error() status code.
 *
 * @param session session handle
 * @param connection connection handle
 */
#define COMMIT_TRANSACTION(session,connection)                             \
  transaction_commit_result =                                              \
    TEH_plugin->commit (TEH_plugin->cls,                                   \
                        session);                                          \
  if (GNUNET_DB_STATUS_HARD_ERROR == transaction_commit_result)            \
  {                                                                        \
    TALER_LOG_WARNING ("Transaction commit failed in %s\n", __FUNCTION__); \
    return TEH_RESPONSE_reply_commit_error (connection, \
					    TALER_EC_DB_COMMIT_FAILED_HARD); \
  }                                                       \
  if (GNUNET_DB_STATUS_SOFT_ERROR == transaction_commit_result)            \
  {                                                                        \
    TALER_LOG_WARNING ("Transaction commit failed in %s\n", __FUNCTION__); \
    if (transaction_retries++ <= MAX_TRANSACTION_COMMIT_RETRIES)           \
      goto transaction_start_label;                                        \
    TALER_LOG_WARNING ("Transaction commit failed %u times in %s\n",       \
                       transaction_retries,                                \
                       __FUNCTION__);                                      \
    return TEH_RESPONSE_reply_commit_error (connection, \
					    TALER_EC_DB_COMMIT_FAILED_ON_RETRY);				\
  }                                                                        \
} /* end of scope opened by BEGIN_TRANSACTION */


/**
 * Code to include to retry a transaction, must only be used in between
 * #START_TRANSACTION and #COMMIT_TRANSACTION.
 *
 * @param session session handle
 * @param connection connection handle
 */
#define RETRY_TRANSACTION(session,connection)                                    \
  do {                                                                           \
    TEH_plugin->rollback (TEH_plugin->cls,                                       \
                          session);                                              \
    if (transaction_retries++ <= MAX_TRANSACTION_COMMIT_RETRIES)                 \
      goto transaction_start_label;                                              \
    TALER_LOG_WARNING ("Transaction commit failed %u times in %s\n",             \
                       transaction_retries,                                      \
                       __FUNCTION__);                                            \
    return TEH_RESPONSE_reply_commit_error (connection,                          \
					    TALER_EC_DB_COMMIT_FAILED_ON_RETRY); \
  } while (0)





/**
 * Send a response for "/refresh/reveal".
 *
 * @param connection the connection to send the response to
 * @param num_newcoins number of new coins for which we reveal data
 * @param sigs array of @a num_newcoins signatures revealed
 * @return a MHD result code
 */
static int
reply_refresh_reveal_success (struct MHD_Connection *connection,
			      unsigned int num_newcoins,
			      const struct TALER_DenominationSignature *sigs)
{
  int newcoin_index;
  json_t *root;
  json_t *obj;
  json_t *list;
  int ret;

  list = json_array ();
  for (newcoin_index = 0; newcoin_index < num_newcoins; newcoin_index++)
  {
    obj = json_object ();
    json_object_set_new (obj,
			 "ev_sig",
			 GNUNET_JSON_from_rsa_signature (sigs[newcoin_index].rsa_signature));
    GNUNET_assert (0 ==
                   json_array_append_new (list,
                                          obj));
  }
  root = json_object ();
  json_object_set_new (root,
                       "ev_sigs",
                       list);
  ret = TEH_RESPONSE_reply_json (connection,
                                 root,
                                 MHD_HTTP_OK);
  json_decref (root);
  return ret;
}


/**
 * Send a response for a failed "/refresh/reveal", where the
 * revealed value(s) do not match the original commitment.
 *
 * @param connection the connection to send the response to
 * @param session info about session
 * @param commit_coins array of @a num_newcoins committed envelopes at offset @a gamma
 * @param denom_pubs array of @a num_newcoins denomination keys for the new coins
 * @param gamma_tp transfer public key at offset @a gamma
 * @return a MHD result code
 */
static int
reply_refresh_reveal_missmatch (struct MHD_Connection *connection,
				const struct TALER_EXCHANGEDB_RefreshSession *session,
				const struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coins,
				const struct TALER_DenominationPublicKey *denom_pubs,
				const struct TALER_TransferPublicKeyP *gamma_tp)
{
  json_t *info_new;
  json_t *info_commit_k;
  unsigned int i;

  info_new = json_array ();
  info_commit_k = json_array ();
  for (i=0;i<session->num_newcoins;i++)
  {
    const struct TALER_EXCHANGEDB_RefreshCommitCoin *cc;
    json_t *cc_json;

    GNUNET_assert (0 ==
                   json_array_append_new (info_new,
                                          GNUNET_JSON_from_rsa_public_key (denom_pubs[i].rsa_public_key)));

    cc = &commit_coins[i];
    cc_json = json_pack ("{s:o}",
                         "coin_ev",
                         GNUNET_JSON_from_data (cc->coin_ev,
                                                cc->coin_ev_size));
    GNUNET_assert (0 ==
                   json_array_append_new (info_commit_k,
                                          cc_json));
  }
  return TEH_RESPONSE_reply_json_pack (connection,
                                       MHD_HTTP_CONFLICT,
                                       "{s:s, s:I, s:o, s:o, s:o, s:o, s:o, s:o, s:o, s:i}",
                                       "error", "commitment violation",
				       "code", (json_int_t) TALER_EC_REFRESH_REVEAL_COMMITMENT_VIOLATION,
                                       "coin_sig", GNUNET_JSON_from_data_auto (&session->melt.coin_sig),
                                       "coin_pub", GNUNET_JSON_from_data_auto (&session->melt.coin.coin_pub),
                                       "melt_amount_with_fee", TALER_JSON_from_amount (&session->melt.amount_with_fee),
                                       "melt_fee", TALER_JSON_from_amount (&session->melt.melt_fee),
                                       "newcoin_infos", info_new,
                                       "commit_infos", info_commit_k,
                                       "gamma_tp", GNUNET_JSON_from_data_auto (gamma_tp),
                                       "gamma", (int) session->noreveal_index);
}



/**
 * Check if the given @a transfer_privs correspond to an honest
 * commitment for the given session.
 * Checks that the transfer private keys match their commitments.
 * Then derives the shared secret for each #TALER_CNC_KAPPA, and check that they match.
 *
 * @param connection the MHD connection to handle
 * @param session database connection to use
 * @param session_hash hash of session to query
 * @param off commitment offset to check
 * @param transfer_priv private transfer key
 * @param melt information about the melted coin
 * @param num_newcoins number of newcoins being generated
 * @param denom_pubs array of @a num_newcoins keys for the new coins
 * @param hash_context hash context to update by hashing in the data
 *                     from this offset
 * @return #GNUNET_OK if the committment was honest,
 *         #GNUNET_NO if there was a problem and we generated an error message
 *         #GNUNET_SYSERR if we could not even generate an error message
 */
static int
check_commitment (struct MHD_Connection *connection,
                  struct TALER_EXCHANGEDB_Session *session,
                  const struct GNUNET_HashCode *session_hash,
                  unsigned int off,
                  const struct TALER_TransferPrivateKeyP *transfer_priv,
                  const struct TALER_EXCHANGEDB_RefreshMelt *melt,
                  unsigned int num_newcoins,
                  const struct TALER_DenominationPublicKey *denom_pubs,
                  struct GNUNET_HashContext *hash_context)
{
  struct TALER_TransferSecretP transfer_secret;
  unsigned int j;

  TALER_link_reveal_transfer_secret (transfer_priv,
                                     &melt->coin.coin_pub,
                                     &transfer_secret);

  /* Check that the commitments for all new coins were correct */
  for (j = 0; j < num_newcoins; j++)
  {
    struct TALER_FreshCoinP fc;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct GNUNET_HashCode h_msg;
    char *buf;
    size_t buf_len;

    TALER_setup_fresh_coin (&transfer_secret,
                            j,
                            &fc);
    GNUNET_CRYPTO_eddsa_key_get_public (&fc.coin_priv.eddsa_priv,
                                        &coin_pub.eddsa_pub);
    GNUNET_CRYPTO_hash (&coin_pub,
                        sizeof (struct TALER_CoinSpendPublicKeyP),
                        &h_msg);
    if (GNUNET_YES !=
        GNUNET_CRYPTO_rsa_blind (&h_msg,
                                 &fc.blinding_key.bks,
                                 denom_pubs[j].rsa_public_key,
                                 &buf,
                                 &buf_len))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Blind failed (bad denomination key!?)\n");
      return (MHD_YES ==
	      TEH_RESPONSE_reply_internal_error (connection,
						 TALER_EC_REFRESH_REVEAL_BLINDING_ERROR,
						 "Blinding error"))
        ? GNUNET_NO : GNUNET_SYSERR;
    }
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     buf,
                                     buf_len);
    GNUNET_free (buf);
  }
  return GNUNET_OK;
}


/**
 * Exchange a coin as part of a refresh operation.  Obtains the
 * envelope from the database and performs the signing operation.
 *
 * @param connection the MHD connection to handle
 * @param session database connection to use
 * @param session_hash hash of session to query
 * @param key_state key state to lookup denomination pubs
 * @param denom_pub denomination key for the coin to create
 * @param commit_coin the coin that was committed
 * @param coin_off number of the coin
 * @return NULL on error, otherwise signature over the coin
 */
static struct TALER_DenominationSignature
refresh_exchange_coin (struct MHD_Connection *connection,
                       struct TALER_EXCHANGEDB_Session *session,
                       const struct GNUNET_HashCode *session_hash,
                       struct TEH_KS_StateHandle *key_state,
                       const struct TALER_DenominationPublicKey *denom_pub,
                       const struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coin,
                       unsigned int coin_off)
{
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation *dki;
  struct TALER_DenominationSignature ev_sig;

  dki = TEH_KS_denomination_key_lookup (key_state,
                                        denom_pub,
					TEH_KS_DKU_WITHDRAW);
  if (NULL == dki)
  {
    GNUNET_break (0);
    ev_sig.rsa_signature = NULL;
    return ev_sig;
  }
  if (GNUNET_OK ==
      TEH_plugin->get_refresh_out (TEH_plugin->cls,
                                   session,
                                   session_hash,
                                   coin_off,
                                   &ev_sig))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Returning cached reply for /refresh/reveal signature\n");
    return ev_sig;
  }

  ev_sig.rsa_signature
    = GNUNET_CRYPTO_rsa_sign_blinded (dki->denom_priv.rsa_private_key,
                                      commit_coin->coin_ev,
                                      commit_coin->coin_ev_size);
  if (NULL == ev_sig.rsa_signature)
  {
    GNUNET_break (0);
    return ev_sig;
  }
  if (GNUNET_SYSERR ==
      TEH_plugin->insert_refresh_out (TEH_plugin->cls,
                                      session,
                                      session_hash,
                                      coin_off,
                                      &ev_sig))
  {
    GNUNET_break (0);
    GNUNET_CRYPTO_rsa_signature_free (ev_sig.rsa_signature);
    ev_sig.rsa_signature = NULL;
  }

  return ev_sig;
}


/**
 * The client request was well-formed, now execute the DB transaction
 * of a "/refresh/reveal" operation.  We use the @a ev_sigs and
 * @a commit_coins to clean up resources after this function returns
 * as we might experience retries of the database transaction.
 *
 * @param connection the MHD connection to handle
 * @param session database session
 * @param session_hash hash identifying the refresh session
 * @param refresh_session information about the refresh operation we are doing
 * @param denom_pubs array of "num_newcoins" denomination keys for the new coins
 * @param[out] ev_sigs where to store generated signatures for the new coins,
 *                     array of length "num_newcoins", memory released by the
 *                     caller
 * @param[out] commit_coins array of length "num_newcoins" to be used for
 *                     information about the new coins from the commitment.
 * @return MHD result code
 */
static int
execute_refresh_reveal_transaction (struct MHD_Connection *connection,
                                    struct TALER_EXCHANGEDB_Session *session,
                                    const struct GNUNET_HashCode *session_hash,
                                    const struct TALER_EXCHANGEDB_RefreshSession *refresh_session,
                                    const struct TALER_DenominationPublicKey *denom_pubs,
                                    struct TALER_DenominationSignature *ev_sigs,
                                    struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coins)
{
  unsigned int j;
  struct TEH_KS_StateHandle *key_state;
  int ret;

  START_TRANSACTION (session, connection);
  key_state = TEH_KS_acquire ();
  for (j=0;j<refresh_session->num_newcoins;j++)
  {
    if (NULL == ev_sigs[j].rsa_signature) /* could be non-NULL during retries */
      ev_sigs[j] = refresh_exchange_coin (connection,
                                          session,
                                          session_hash,
                                          key_state,
                                          &denom_pubs[j],
                                          &commit_coins[j],
                                          j);
    if (NULL == ev_sigs[j].rsa_signature)
    {
      TEH_plugin->rollback (TEH_plugin->cls,
                            session);
      ret = TEH_RESPONSE_reply_internal_db_error (connection,
						  TALER_EC_REFRESH_REVEAL_SIGNING_ERROR);
      goto cleanup;
    }
  }
  COMMIT_TRANSACTION (session, connection);
  ret = reply_refresh_reveal_success (connection,
				      refresh_session->num_newcoins,
				      ev_sigs);
 cleanup:
  TEH_KS_release (key_state);
  return ret;
}


/**
 * Execute a "/refresh/reveal".  The client is revealing to us the
 * transfer keys for @a #TALER_CNC_KAPPA-1 sets of coins.  Verify that the
 * revealed transfer keys would allow linkage to the blinded coins,
 * and if so, return the signed coins for corresponding to the set of
 * coins that was not chosen.
 *
 * @param connection the MHD connection to handle
 * @param session_hash hash identifying the refresh session
 * @param transfer_privs array with the revealed transfer keys,
 *                      length must be #TALER_CNC_KAPPA - 1
 * @return MHD result code
 */
static int
execute_refresh_reveal (struct MHD_Connection *connection,
			const struct GNUNET_HashCode *session_hash,
			struct TALER_TransferPrivateKeyP *transfer_privs)
{
  int res;
  struct TALER_EXCHANGEDB_Session *session;
  struct TALER_EXCHANGEDB_RefreshSession refresh_session;
  struct TALER_DenominationPublicKey *denom_pubs;
  struct TALER_DenominationSignature *ev_sigs;
  struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coins;
  unsigned int i;
  unsigned int j;
  unsigned int off;
  struct GNUNET_HashContext *hash_context;
  struct GNUNET_HashCode sh_check;
  int ret;
  struct TALER_TransferPublicKeyP gamma_tp;

  if (NULL == (session = TEH_plugin->get_session (TEH_plugin->cls)))
  {
    GNUNET_break (0);
    return TEH_RESPONSE_reply_internal_db_error (connection,
						 TALER_EC_DB_SETUP_FAILED);
  }

  res = TEH_plugin->get_refresh_session (TEH_plugin->cls,
                                         session,
                                         session_hash,
                                         &refresh_session);
  if (GNUNET_NO == res)
    return TEH_RESPONSE_reply_arg_invalid (connection,
					   TALER_EC_REFRESH_REVEAL_SESSION_UNKNOWN,
                                           "session_hash");
  if ( (GNUNET_SYSERR == res) ||
       (refresh_session.noreveal_index >= TALER_CNC_KAPPA) )
    return TEH_RESPONSE_reply_internal_db_error (connection,
						 TALER_EC_REFRESH_REVEAL_DB_FETCH_SESSION_ERROR);
  denom_pubs = GNUNET_new_array (refresh_session.num_newcoins,
                                 struct TALER_DenominationPublicKey);
  if (GNUNET_OK !=
      TEH_plugin->get_refresh_order (TEH_plugin->cls,
                                     session,
                                     session_hash,
                                     refresh_session.num_newcoins,
                                     denom_pubs))
  {
    GNUNET_break (0);
    GNUNET_free (denom_pubs);
    GNUNET_CRYPTO_rsa_signature_free (refresh_session.melt.coin.denom_sig.rsa_signature);
    GNUNET_CRYPTO_rsa_public_key_free (refresh_session.melt.coin.denom_pub.rsa_public_key);
    return (MHD_YES == TEH_RESPONSE_reply_internal_db_error (connection,
							     TALER_EC_REFRESH_REVEAL_DB_FETCH_ORDER_ERROR))
        ? GNUNET_NO : GNUNET_SYSERR;
  }

  hash_context = GNUNET_CRYPTO_hash_context_start ();
  /* first, iterate over transfer public keys for hash_context */
  off = 0;
  for (i=0;i<TALER_CNC_KAPPA;i++)
  {
    if (i == refresh_session.noreveal_index)
    {
      off = 1;
      /* obtain gamma_tp from db */
      if (GNUNET_OK !=
          TEH_plugin->get_refresh_transfer_public_key (TEH_plugin->cls,
                                                       session,
                                                       session_hash,
                                                       &gamma_tp))
      {
        GNUNET_break (0);
        GNUNET_free (denom_pubs);
        GNUNET_CRYPTO_rsa_signature_free (refresh_session.melt.coin.denom_sig.rsa_signature);
        GNUNET_CRYPTO_rsa_public_key_free (refresh_session.melt.coin.denom_pub.rsa_public_key);
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        return (MHD_YES == TEH_RESPONSE_reply_internal_db_error (connection,
								 TALER_EC_REFRESH_REVEAL_DB_FETCH_TRANSFER_ERROR))
          ? GNUNET_NO : GNUNET_SYSERR;
      }
      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       &gamma_tp,
                                       sizeof (struct TALER_TransferPublicKeyP));
    }
    else
    {
      /* compute tp from private key */
      struct TALER_TransferPublicKeyP tp;

      GNUNET_CRYPTO_ecdhe_key_get_public (&transfer_privs[i - off].ecdhe_priv,
                                          &tp.ecdhe_pub);
      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       &tp,
                                       sizeof (struct TALER_TransferPublicKeyP));
    }
  }

  /* next, add all of the hashes from the denomination keys to the
     hash_context */
  {
    struct TALER_DenominationPublicKey denom_pubs[refresh_session.num_newcoins];

    if (GNUNET_OK !=
        TEH_plugin->get_refresh_order (TEH_plugin->cls,
                                       session,
                                       session_hash,
                                       refresh_session.num_newcoins,
                                       denom_pubs))
    {
      GNUNET_break (0);
      GNUNET_free (denom_pubs);
      GNUNET_CRYPTO_rsa_signature_free (refresh_session.melt.coin.denom_sig.rsa_signature);
      GNUNET_CRYPTO_rsa_public_key_free (refresh_session.melt.coin.denom_pub.rsa_public_key);
      GNUNET_CRYPTO_hash_context_abort (hash_context);
      return (MHD_YES == TEH_RESPONSE_reply_internal_db_error (connection,
							       TALER_EC_REFRESH_REVEAL_DB_FETCH_ORDER_ERROR))
        ? GNUNET_NO : GNUNET_SYSERR;
    }
    for (i=0;i<refresh_session.num_newcoins;i++)
    {
      char *buf;
      size_t buf_size;

      buf_size = GNUNET_CRYPTO_rsa_public_key_encode (denom_pubs[i].rsa_public_key,
                                                      &buf);
      GNUNET_CRYPTO_hash_context_read (hash_context,
                                       buf,
                                       buf_size);
      GNUNET_free (buf);
      GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[i].rsa_public_key);
    }
  }

  /* next, add public key of coin and amount being refreshed */
  {
    struct TALER_AmountNBO melt_amountn;

    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &refresh_session.melt.coin.coin_pub,
                                     sizeof (struct TALER_CoinSpendPublicKeyP));
    TALER_amount_hton (&melt_amountn,
                       &refresh_session.melt.amount_with_fee);
    GNUNET_CRYPTO_hash_context_read (hash_context,
                                     &melt_amountn,
                                     sizeof (struct TALER_AmountNBO));
  }

  commit_coins = GNUNET_new_array (refresh_session.num_newcoins,
                                   struct TALER_EXCHANGEDB_RefreshCommitCoin);
  off = 0;
  for (i=0;i<TALER_CNC_KAPPA;i++)
  {
    if (i == refresh_session.noreveal_index)
    {
      off = 1;
      /* obtain commit_coins for the selected gamma value from DB */
      if (GNUNET_OK !=
          TEH_plugin->get_refresh_commit_coins (TEH_plugin->cls,
                                                session,
                                                session_hash,
                                                refresh_session.num_newcoins,
                                                commit_coins))
      {
        GNUNET_break (0);
        GNUNET_free (denom_pubs);
        GNUNET_CRYPTO_rsa_signature_free (refresh_session.melt.coin.denom_sig.rsa_signature);
        GNUNET_CRYPTO_rsa_public_key_free (refresh_session.melt.coin.denom_pub.rsa_public_key);
        GNUNET_CRYPTO_hash_context_abort (hash_context);
        return TEH_RESPONSE_reply_internal_db_error (connection,
						     TALER_EC_REFRESH_REVEAL_DB_FETCH_COMMIT_ERROR);
      }
      /* add envelopes to hash_context */
      for (j=0;j<refresh_session.num_newcoins;j++)
      {
        GNUNET_CRYPTO_hash_context_read (hash_context,
                                         commit_coins[j].coin_ev,
                                         commit_coins[j].coin_ev_size);
      }
      continue;
    }
    if (GNUNET_OK !=
        (res = check_commitment (connection,
                                 session,
                                 session_hash,
                                 i,
                                 &transfer_privs[i - off],
                                 &refresh_session.melt,
                                 refresh_session.num_newcoins,
                                 denom_pubs,
                                 hash_context)))
    {
      GNUNET_break_op (0);
      for (j=0;j<refresh_session.num_newcoins;j++)
      {
        GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j].rsa_public_key);
        GNUNET_free (commit_coins[j].coin_ev);
      }
      GNUNET_free (commit_coins);
      GNUNET_free (denom_pubs);
      GNUNET_CRYPTO_rsa_signature_free (refresh_session.melt.coin.denom_sig.rsa_signature);
      GNUNET_CRYPTO_rsa_public_key_free (refresh_session.melt.coin.denom_pub.rsa_public_key);
      GNUNET_CRYPTO_hash_context_abort (hash_context);
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }
  }

  /* Check session hash matches */
  GNUNET_CRYPTO_hash_context_finish (hash_context,
                                     &sh_check);
  if (0 != memcmp (&sh_check,
                   session_hash,
                   sizeof (struct GNUNET_HashCode)))
  {
    GNUNET_break_op (0);
    ret = reply_refresh_reveal_missmatch (connection,
					  &refresh_session,
					  commit_coins,
					  denom_pubs,
					  &gamma_tp);
    for (j=0;j<refresh_session.num_newcoins;j++)
    {
      GNUNET_free (commit_coins[j].coin_ev);
      GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j].rsa_public_key);
    }
    GNUNET_free (commit_coins);
    GNUNET_free (denom_pubs);
    GNUNET_CRYPTO_rsa_signature_free (refresh_session.melt.coin.denom_sig.rsa_signature);
    GNUNET_CRYPTO_rsa_public_key_free (refresh_session.melt.coin.denom_pub.rsa_public_key);

    return ret;
  }

  /* Client request OK, start transaction */
  ev_sigs = GNUNET_new_array (refresh_session.num_newcoins,
                              struct TALER_DenominationSignature);

  /* FIXME: might need to store revealed transfer private keys for
     the auditor for later; should pass them as arguments here! #4792*/
  res = execute_refresh_reveal_transaction (connection,
                                            session,
                                            session_hash,
                                            &refresh_session,
                                            denom_pubs,
                                            ev_sigs,
                                            commit_coins);
  for (i=0;i<refresh_session.num_newcoins;i++)
  {
    if (NULL != ev_sigs[i].rsa_signature)
      GNUNET_CRYPTO_rsa_signature_free (ev_sigs[i].rsa_signature);
    GNUNET_free (commit_coins[i].coin_ev);
  }
  for (j=0;j<refresh_session.num_newcoins;j++)
    if (NULL != denom_pubs[j].rsa_public_key)
      GNUNET_CRYPTO_rsa_public_key_free (denom_pubs[j].rsa_public_key);
  GNUNET_CRYPTO_rsa_signature_free (refresh_session.melt.coin.denom_sig.rsa_signature);
  GNUNET_CRYPTO_rsa_public_key_free (refresh_session.melt.coin.denom_pub.rsa_public_key);
  GNUNET_free (ev_sigs);
  GNUNET_free (denom_pubs);
  GNUNET_free (commit_coins);
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
    res = execute_refresh_reveal (connection,
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
					   TALER_EC_REFRESH_REVEAL_CNC_TRANSFER_ARRAY_SIZE_INVALID,
                                           "transfer_privs");
  }
  res = handle_refresh_reveal_json (connection,
                                    &session_hash,
                                    transfer_privs);
  GNUNET_JSON_parse_free (spec);
  return res;
}


/* end of taler-exchange-httpd_refresh_reveal.c */
