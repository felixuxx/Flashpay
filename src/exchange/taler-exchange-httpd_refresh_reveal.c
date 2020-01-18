/*
  This file is part of TALER
  Copyright (C) 2014-2019 Taler Systems SA

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
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_mhd.h"
#include "taler-exchange-httpd_refresh_reveal.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keystate.h"


/**
 * Maximum number of fresh coins we allow per refresh operation.
 */
#define MAX_FRESH_COINS 256

/**
 * How often do we at most retry the reveal transaction sequence?
 * Twice should really suffice in all cases (as the possible conflict
 * cannot happen more than once).
 */
#define MAX_REVEAL_RETRIES 2


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
  json_t *list;
  int ret;

  list = json_array ();
  for (unsigned int newcoin_index = 0;
       newcoin_index < num_newcoins;
       newcoin_index++)
  {
    json_t *obj;

    obj = json_object ();
    json_object_set_new (obj,
                         "ev_sig",
                         GNUNET_JSON_from_rsa_signature (
                           sigs[newcoin_index].rsa_signature));
    GNUNET_assert (0 ==
                   json_array_append_new (list,
                                          obj));
  }

  {
    json_t *root;

    root = json_object ();
    json_object_set_new (root,
                         "ev_sigs",
                         list);
    ret = TALER_MHD_reply_json (connection,
                                root,
                                MHD_HTTP_OK);
    json_decref (root);
  }
  return ret;
}


/**
 * Send a response for a failed "/refresh/reveal", where the
 * revealed value(s) do not match the original commitment.
 *
 * @param connection the connection to send the response to
 * @param rc commitment computed by the exchange
 * @return a MHD result code
 */
static int
reply_refresh_reveal_missmatch (struct MHD_Connection *connection,
                                const struct TALER_RefreshCommitmentP *rc)
{
  return TALER_MHD_reply_json_pack (connection,
                                    MHD_HTTP_CONFLICT,
                                    "{s:s, s:I, s:o}",
                                    "error", "commitment violation",
                                    "code",
                                    (json_int_t)
                                    TALER_EC_REFRESH_REVEAL_COMMITMENT_VIOLATION,
                                    "rc_expected",
                                    GNUNET_JSON_from_data_auto (rc));
}


/**
 * State for a /refresh/reveal operation.
 */
struct RevealContext
{

  /**
   * Commitment of the refresh operaton.
   */
  struct TALER_RefreshCommitmentP rc;

  /**
   * Transfer public key at gamma.
   */
  struct TALER_TransferPublicKeyP gamma_tp;

  /**
   * Transfer private keys revealed to us.
   */
  struct TALER_TransferPrivateKeyP transfer_privs[TALER_CNC_KAPPA - 1];

  /**
   * Denominations being requested.
   */
  const struct TALER_EXCHANGEDB_DenominationKeyIssueInformation **dkis;

  /**
   * Envelopes to be signed.
   */
  const struct TALER_RefreshCoinData *rcds;

  /**
   * Signatures over the link data (of type
   * #TALER_SIGNATURE_WALLET_COIN_LINK)
   */
  const struct TALER_CoinSpendSignatureP *link_sigs;

  /**
   * Envelopes with the signatures to be returned.  Initially NULL.
   */
  struct TALER_DenominationSignature *ev_sigs;

  /**
   * Size of the @e dkis, @e rcds and @e ev_sigs arrays (if non-NULL).
   */
  unsigned int num_fresh_coins;

  /**
   * Result from preflight checks. #GNUNET_NO for no result,
   * #GNUNET_YES if preflight found previous successful operation,
   * #GNUNET_SYSERR if prefight check failed hard (and generated
   * an MHD response already).
   */
  int preflight_ok;

};


/**
 * Function called with information about a refresh order we already
 * persisted.  Stores the result in @a cls so we don't do the calculation
 * again.
 *
 * @param cls closure with a `struct RevealContext`
 * @param num_newcoins size of the @a rrcs array
 * @param rrcs array of @a num_newcoins information about coins to be created
 * @param num_tprivs number of entries in @a tprivs, should be #TALER_CNC_KAPPA - 1
 * @param tprivs array of @e num_tprivs transfer private keys
 * @param tp transfer public key information
 */
static void
check_exists_cb (void *cls,
                 uint32_t num_newcoins,
                 const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs,
                 unsigned int num_tprivs,
                 const struct TALER_TransferPrivateKeyP *tprivs,
                 const struct TALER_TransferPublicKeyP *tp)
{
  struct RevealContext *rctx = cls;

  if (0 == num_newcoins)
  {
    GNUNET_break (0);
    return;
  }
  GNUNET_break (TALER_CNC_KAPPA - 1 == num_tprivs);
  GNUNET_break_op (0 == memcmp (tp,
                                &rctx->gamma_tp,
                                sizeof (struct TALER_TransferPublicKeyP)));
  GNUNET_break_op (0 == memcmp (tprivs,
                                &rctx->transfer_privs,
                                sizeof (struct TALER_TransferPrivateKeyP)
                                * num_tprivs));
  /* We usually sign early (optimistic!), but in case we change that *and*
     we do find the operation in the database, we could use this: */
  if (NULL == rctx->ev_sigs)
  {
    rctx->ev_sigs = GNUNET_new_array (num_newcoins,
                                      struct TALER_DenominationSignature);
    for (unsigned int i = 0; i<num_newcoins; i++)
      rctx->ev_sigs[i].rsa_signature
        = GNUNET_CRYPTO_rsa_signature_dup (rrcs[i].coin_sig.rsa_signature);
  }
}


/**
 * Check if the "/refresh/reveal" was already successful before.
 * If so, just return the old result.
 *
 * @param cls closure of type `struct RevealContext`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
refresh_reveal_preflight (void *cls,
                          struct MHD_Connection *connection,
                          struct TALER_EXCHANGEDB_Session *session,
                          int *mhd_ret)
{
  struct RevealContext *rctx = cls;
  enum GNUNET_DB_QueryStatus qs;

  /* Try to see if we already have given an answer before. */
  qs = TEH_plugin->get_refresh_reveal (TEH_plugin->cls,
                                       session,
                                       &rctx->rc,
                                       &check_exists_cb,
                                       rctx);
  switch (qs)
  {
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    return qs; /* continue normal execution */
  case GNUNET_DB_STATUS_SOFT_ERROR:
    return qs;
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (qs);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_REFRESH_REVEAL_DB_FETCH_REVEAL_ERROR,
                                           "failed to fetch reveal data");
    rctx->preflight_ok = GNUNET_SYSERR;
    return GNUNET_DB_STATUS_HARD_ERROR;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
  default:
    /* Hossa, already found our reply! */
    GNUNET_assert (NULL != rctx->ev_sigs);
    rctx->preflight_ok = GNUNET_YES;
    return qs;
  }
}


/**
 * Execute a "/refresh/reveal".  The client is revealing to us the
 * transfer keys for @a #TALER_CNC_KAPPA-1 sets of coins.  Verify that the
 * revealed transfer keys would allow linkage to the blinded coins.
 *
 * IF it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls closure of type `struct RevealContext`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
refresh_reveal_transaction (void *cls,
                            struct MHD_Connection *connection,
                            struct TALER_EXCHANGEDB_Session *session,
                            int *mhd_ret)
{
  struct RevealContext *rctx = cls;
  struct TALER_EXCHANGEDB_RefreshMelt refresh_melt;
  enum GNUNET_DB_QueryStatus qs;

  /* Obtain basic information about the refresh operation and what
     gamma we committed to. */
  qs = TEH_plugin->get_melt (TEH_plugin->cls,
                             session,
                             &rctx->rc,
                             &refresh_melt);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_REFRESH_REVEAL_SESSION_UNKNOWN,
                                           "rc");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    return qs;
  if ( (GNUNET_DB_STATUS_HARD_ERROR == qs) ||
       (refresh_melt.session.noreveal_index >= TALER_CNC_KAPPA) )
  {
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_REFRESH_REVEAL_DB_FETCH_SESSION_ERROR,
                                           "failed to fetch valid challenge from database");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* Verify commitment */
  {
    /* Note that the contents of rcs[refresh_melt.session.noreveal_index]
       will be aliased and are *not* allocated (or deallocated) in
       this function -- in contrast to the other offsets! */
    struct TALER_RefreshCommitmentEntry rcs[TALER_CNC_KAPPA];
    struct TALER_RefreshCommitmentP rc_expected;
    unsigned int off;

    off = 0; /* did we pass session.noreveal_index yet? */
    for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
    {
      struct TALER_RefreshCommitmentEntry *rce = &rcs[i];

      if (i == refresh_melt.session.noreveal_index)
      {
        /* Take these coin envelopes from the client */
        rce->transfer_pub = rctx->gamma_tp;
        rce->new_coins = (struct TALER_RefreshCoinData *) rctx->rcds;
        off = 1;
      }
      else
      {
        /* Reconstruct coin envelopes from transfer private key */
        struct TALER_TransferPrivateKeyP *tpriv = &rctx->transfer_privs[i
                                                                        - off];
        struct TALER_TransferSecretP ts;

        GNUNET_CRYPTO_ecdhe_key_get_public (&tpriv->ecdhe_priv,
                                            &rce->transfer_pub.ecdhe_pub);
        TALER_link_reveal_transfer_secret (tpriv,
                                           &refresh_melt.session.coin.coin_pub,
                                           &ts);
        rce->new_coins = GNUNET_new_array (rctx->num_fresh_coins,
                                           struct TALER_RefreshCoinData);
        for (unsigned int j = 0; j<rctx->num_fresh_coins; j++)
        {
          struct TALER_RefreshCoinData *rcd = &rce->new_coins[j];
          struct TALER_PlanchetSecretsP ps;
          struct TALER_PlanchetDetail pd;

          rcd->dk = &rctx->dkis[j]->denom_pub;
          TALER_planchet_setup_refresh (&ts,
                                        j,
                                        &ps);
          GNUNET_assert (GNUNET_OK ==
                         TALER_planchet_prepare (rcd->dk,
                                                 &ps,
                                                 &pd));
          rcd->coin_ev = pd.coin_ev;
          rcd->coin_ev_size = pd.coin_ev_size;
        }
      }
    }
    TALER_refresh_get_commitment (&rc_expected,
                                  TALER_CNC_KAPPA,
                                  rctx->num_fresh_coins,
                                  rcs,
                                  &refresh_melt.session.coin.coin_pub,
                                  &refresh_melt.session.amount_with_fee);

    /* Free resources allocated above */
    for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
    {
      struct TALER_RefreshCommitmentEntry *rce = &rcs[i];

      if (i == refresh_melt.session.noreveal_index)
        continue; /* This offset is special... */
      for (unsigned int j = 0; j<rctx->num_fresh_coins; j++)
      {
        struct TALER_RefreshCoinData *rcd = &rce->new_coins[j];

        GNUNET_free (rcd->coin_ev);
      }
      GNUNET_free (rce->new_coins);
    }

    /* Verify rc_expected matches rc */
    if (0 != GNUNET_memcmp (&rctx->rc,
                            &rc_expected))
    {
      GNUNET_break_op (0);
      *mhd_ret = reply_refresh_reveal_missmatch (connection,
                                                 &rc_expected);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  } /* end of checking "rc_expected" */

  /* check amounts add up! */
  {
    struct TALER_Amount refresh_cost;

    refresh_cost = refresh_melt.melt_fee;
    for (unsigned int i = 0; i<rctx->num_fresh_coins; i++)
    {
      struct TALER_Amount fee_withdraw;
      struct TALER_Amount value;
      struct TALER_Amount total;

      TALER_amount_ntoh (&fee_withdraw,
                         &rctx->dkis[i]->issue.properties.fee_withdraw);
      TALER_amount_ntoh (&value,
                         &rctx->dkis[i]->issue.properties.value);
      if ( (GNUNET_OK !=
            TALER_amount_add (&total,
                              &fee_withdraw,
                              &value)) ||
           (GNUNET_OK !=
            TALER_amount_add (&refresh_cost,
                              &refresh_cost,
                              &total)) )
      {
        GNUNET_break_op (0);
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_REFRESH_REVEAL_COST_CALCULATION_OVERFLOW,
                                               "failed to add up refresh costs");
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
    }
    if (0 < TALER_amount_cmp (&refresh_cost,
                              &refresh_melt.session.amount_with_fee))
    {
      GNUNET_break_op (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_REFRESH_REVEAL_AMOUNT_INSUFFICIENT,
                                             "melted coin value is insufficient to cover cost of operation");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
}


/**
 * Persist result of a "/refresh/reveal".
 *
 * @param cls closure of type `struct RevealContext`
 * @param connection MHD request which triggered the transaction
 * @param session database session to use
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
refresh_reveal_persist (void *cls,
                        struct MHD_Connection *connection,
                        struct TALER_EXCHANGEDB_Session *session,
                        int *mhd_ret)
{
  struct RevealContext *rctx = cls;
  enum GNUNET_DB_QueryStatus qs;

  /* Persist operation result in DB */
  {
    struct TALER_EXCHANGEDB_RefreshRevealedCoin rrcs[rctx->num_fresh_coins];

    for (unsigned int i = 0; i<rctx->num_fresh_coins; i++)
    {
      struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &rrcs[i];

      rrc->denom_pub = rctx->dkis[i]->denom_pub;
      rrc->orig_coin_link_sig = rctx->link_sigs[i];
      rrc->coin_ev = rctx->rcds[i].coin_ev;
      rrc->coin_ev_size = rctx->rcds[i].coin_ev_size;
      rrc->coin_sig = rctx->ev_sigs[i];
    }
    qs = TEH_plugin->insert_refresh_reveal (TEH_plugin->cls,
                                            session,
                                            &rctx->rc,
                                            rctx->num_fresh_coins,
                                            rrcs,
                                            TALER_CNC_KAPPA - 1,
                                            rctx->transfer_privs,
                                            &rctx->gamma_tp);
  }
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_REFRESH_REVEAL_DB_COMMIT_ERROR,
                                           "failed to persist reveal data");
  }
  return qs;
}


/**
 * Resolve denomination hashes using the @a key_state
 *
 * @param key_state the key state
 * @param connection the MHD connection to handle
 * @param rctx context for the operation, partially built at this time
 * @param link_sigs_json link signatures in JSON format
 * @param new_denoms_h_json requests for fresh coins to be created
 * @param coin_evs envelopes of gamma-selected coins to be signed
 * @return MHD result code
 */
static int
resolve_refresh_reveal_denominations (struct TEH_KS_StateHandle *key_state,
                                      struct MHD_Connection *connection,
                                      struct RevealContext *rctx,
                                      const json_t *link_sigs_json,
                                      const json_t *new_denoms_h_json,
                                      const json_t *coin_evs)
{
  unsigned int num_fresh_coins = json_array_size (new_denoms_h_json);
  const struct
  TALER_EXCHANGEDB_DenominationKeyIssueInformation *dkis[num_fresh_coins];
  struct GNUNET_HashCode dki_h[num_fresh_coins];
  struct TALER_RefreshCoinData rcds[num_fresh_coins];
  struct TALER_CoinSpendSignatureP link_sigs[num_fresh_coins];
  struct TALER_EXCHANGEDB_RefreshMelt refresh_melt;
  int res;

  /* Parse denomination key hashes */
  for (unsigned int i = 0; i<num_fresh_coins; i++)
  {
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto (NULL,
                                   &dki_h[i]),
      GNUNET_JSON_spec_end ()
    };
    unsigned int hc;
    enum TALER_ErrorCode ec;

    res = TALER_MHD_parse_json_array (connection,
                                      new_denoms_h_json,
                                      spec,
                                      i,
                                      -1);
    if (GNUNET_OK != res)
    {
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }
    dkis[i] = TEH_KS_denomination_key_lookup_by_hash (key_state,
                                                      &dki_h[i],
                                                      TEH_KS_DKU_WITHDRAW,
                                                      &ec,
                                                      &hc);
    if (NULL == dkis[i])
    {
      return TALER_MHD_reply_with_error (connection,
                                         hc,
                                         ec,
                                         "failed to find denomination key");
    }
    GNUNET_assert (NULL != dkis[i]->denom_priv.rsa_private_key);
  }

  /* Parse coin envelopes */
  for (unsigned int i = 0; i<num_fresh_coins; i++)
  {
    struct TALER_RefreshCoinData *rcd = &rcds[i];
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_varsize (NULL,
                                (void **) &rcd->coin_ev,
                                &rcd->coin_ev_size),
      GNUNET_JSON_spec_end ()
    };

    res = TALER_MHD_parse_json_array (connection,
                                      coin_evs,
                                      spec,
                                      i,
                                      -1);
    if (GNUNET_OK != res)
    {
      for (unsigned int j = 0; j<i; j++)
        GNUNET_free_non_null (rcds[j].coin_ev);
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }
    rcd->dk = &dkis[i]->denom_pub;
  }

  /* lookup old_coin_pub in database */
  {
    enum GNUNET_DB_QueryStatus qs;

    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
        (qs = TEH_plugin->get_melt (TEH_plugin->cls,
                                    NULL,
                                    &rctx->rc,
                                    &refresh_melt)))
    {
      switch (qs)
      {
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        res = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_NOT_FOUND,
                                          TALER_EC_REFRESH_REVEAL_SESSION_UNKNOWN,
                                          "rc");
        break;
      case GNUNET_DB_STATUS_HARD_ERROR:
        res = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_REFRESH_REVEAL_DB_FETCH_SESSION_ERROR,
                                          "failed to fetch session data");
        break;
      case GNUNET_DB_STATUS_SOFT_ERROR:
      default:
        GNUNET_break (0);   /* should be impossible */
        res = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_INTERNAL_INVARIANT_FAILURE,
                                          "assertion failed");
        break;
      }
      goto cleanup;
    }
  }
  /* Parse link signatures array */
  for (unsigned int i = 0; i<num_fresh_coins; i++)
  {
    struct GNUNET_JSON_Specification link_spec[] = {
      GNUNET_JSON_spec_fixed_auto (NULL, &link_sigs[i]),
      GNUNET_JSON_spec_end ()
    };
    int res;

    res = TALER_MHD_parse_json_array (connection,
                                      link_sigs_json,
                                      link_spec,
                                      i,
                                      -1);
    if (GNUNET_OK != res)
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    /* Check link_sigs[i] signature */
    {
      struct TALER_LinkDataPS ldp;

      ldp.purpose.size = htonl (sizeof (ldp));
      ldp.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_LINK);
      ldp.h_denom_pub = dki_h[i];
      ldp.old_coin_pub = refresh_melt.session.coin.coin_pub;
      ldp.transfer_pub = rctx->gamma_tp;
      GNUNET_CRYPTO_hash (rcds[i].coin_ev,
                          rcds[i].coin_ev_size,
                          &ldp.coin_envelope_hash);
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_LINK,
                                      &ldp.purpose,
                                      &link_sigs[i].eddsa_signature,
                                      &refresh_melt.session.coin.coin_pub.
                                      eddsa_pub))
      {
        GNUNET_break_op (0);
        res = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_FORBIDDEN,
                                          TALER_EC_REFRESH_REVEAL_LINK_SIGNATURE_INVALID,
                                          "link_sig");
        goto cleanup;
      }
    }
  }

  rctx->num_fresh_coins = num_fresh_coins;
  rctx->rcds = rcds;
  rctx->dkis = dkis;
  rctx->link_sigs = link_sigs;

  /* sign _early_ (optimistic!) to keep out of transaction scope! */
  rctx->ev_sigs = GNUNET_new_array (rctx->num_fresh_coins,
                                    struct TALER_DenominationSignature);
  for (unsigned int i = 0; i<rctx->num_fresh_coins; i++)
  {
    rctx->ev_sigs[i].rsa_signature
      = GNUNET_CRYPTO_rsa_sign_blinded (
          rctx->dkis[i]->denom_priv.rsa_private_key,
          rctx->rcds[i].coin_ev,
          rctx->rcds[i].coin_ev_size);
    if (NULL == rctx->ev_sigs[i].rsa_signature)
    {
      GNUNET_break (0);
      res = TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_INTERNAL_SERVER_ERROR,
                                        TALER_EC_REFRESH_REVEAL_SIGNING_ERROR,
                                        "internal signing error");
      goto cleanup;
    }
  }

  /* We try the three transactions a few times, as theoretically
     the pre-check might be satisfied by a concurrent transaction
     voiding our final commit due to uniqueness violation; naturally,
     on hard errors we exit immediately */
  for (unsigned int retries = 0; retries < MAX_REVEAL_RETRIES; retries++)
  {
    /* do transactional work */
    rctx->preflight_ok = GNUNET_NO;
    if ( (GNUNET_OK ==
          TEH_DB_run_transaction (connection,
                                  "reveal pre-check",
                                  &res,
                                  &refresh_reveal_preflight,
                                  rctx)) &&
         (GNUNET_YES == rctx->preflight_ok) )
    {
      /* Generate final (positive) response */
      GNUNET_assert (NULL != rctx->ev_sigs);
      res = reply_refresh_reveal_success (connection,
                                          num_fresh_coins,
                                          rctx->ev_sigs);
      GNUNET_break (MHD_NO != res);
      goto cleanup;   /* aka 'break' */
    }
    if (GNUNET_SYSERR == rctx->preflight_ok)
    {
      GNUNET_break (0);
      goto cleanup;   /* aka 'break' */
    }
    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "run reveal",
                                &res,
                                &refresh_reveal_transaction,
                                rctx))
    {
      /* reveal failed, too bad */
      GNUNET_break_op (0);
      goto cleanup;   /* aka 'break' */
    }
    if (GNUNET_OK ==
        TEH_DB_run_transaction (connection,
                                "persist reveal",
                                &res,
                                &refresh_reveal_persist,
                                rctx))
    {
      /* Generate final (positive) response */
      GNUNET_assert (NULL != rctx->ev_sigs);
      res = reply_refresh_reveal_success (connection,
                                          num_fresh_coins,
                                          rctx->ev_sigs);
      break;
    }
  }   /* end for (retries...) */

cleanup:
  GNUNET_break (MHD_NO != res);
  /* free resources */
  if (NULL != rctx->ev_sigs)
  {
    for (unsigned int i = 0; i<num_fresh_coins; i++)
      if (NULL != rctx->ev_sigs[i].rsa_signature)
        GNUNET_CRYPTO_rsa_signature_free (rctx->ev_sigs[i].rsa_signature);
    GNUNET_free (rctx->ev_sigs);
    rctx->ev_sigs = NULL; /* just to be safe... */
  }
  for (unsigned int i = 0; i<num_fresh_coins; i++)
    GNUNET_free_non_null (rcds[i].coin_ev);
  return res;
}


/**
 * Handle a "/refresh/reveal" request.   Parses the given JSON
 * transfer private keys and if successful, passes everything to
 * #resolve_refresh_reveal_denominations() which will verify that the
 * revealed information is valid then returns the signed refreshed
 * coins.
 *
 * @param connection the MHD connection to handle
 * @param rctx context for the operation, partially built at this time
 * @param tp_json private transfer keys in JSON format
 * @param link_sigs_json link signatures in JSON format
 * @param new_denoms_h_json requests for fresh coins to be created
 * @param coin_evs envelopes of gamma-selected coins to be signed
 * @return MHD result code
 */
static int
handle_refresh_reveal_json (struct MHD_Connection *connection,
                            struct RevealContext *rctx,
                            const json_t *tp_json,
                            const json_t *link_sigs_json,
                            const json_t *new_denoms_h_json,
                            const json_t *coin_evs)
{
  unsigned int num_fresh_coins = json_array_size (new_denoms_h_json);
  unsigned int num_tprivs = json_array_size (tp_json);

  GNUNET_assert (num_tprivs == TALER_CNC_KAPPA - 1);
  if ( (num_fresh_coins >= MAX_FRESH_COINS) ||
       (0 == num_fresh_coins) )
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_REFRESH_REVEAL_NEW_DENOMS_ARRAY_SIZE_EXCESSIVE,
                                       "new_denoms_h");

  }
  if (json_array_size (new_denoms_h_json) !=
      json_array_size (coin_evs))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_REFRESH_REVEAL_NEW_DENOMS_ARRAY_SIZE_MISSMATCH,
                                       "new_denoms/coin_evs");
  }
  if (json_array_size (new_denoms_h_json) !=
      json_array_size (link_sigs_json))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_REFRESH_REVEAL_NEW_DENOMS_ARRAY_SIZE_MISSMATCH,
                                       "new_denoms/link_sigs");
  }

  /* Parse transfer private keys array */
  for (unsigned int i = 0; i<num_tprivs; i++)
  {
    struct GNUNET_JSON_Specification trans_spec[] = {
      GNUNET_JSON_spec_fixed_auto (NULL, &rctx->transfer_privs[i]),
      GNUNET_JSON_spec_end ()
    };
    int res;

    res = TALER_MHD_parse_json_array (connection,
                                      tp_json,
                                      trans_spec,
                                      i,
                                      -1);
    if (GNUNET_OK != res)
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
  }

  {
    struct TEH_KS_StateHandle *key_state;
    int ret;

    key_state = TEH_KS_acquire (GNUNET_TIME_absolute_get ());
    if (NULL == key_state)
    {
      TALER_LOG_ERROR ("Lacking keys to operate\n");
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_REFRESH_REVEAL_KEYS_MISSING,
                                         "exchange lacks keys");
    }
    ret = resolve_refresh_reveal_denominations (key_state,
                                                connection,
                                                rctx,
                                                link_sigs_json,
                                                new_denoms_h_json,
                                                coin_evs);
    TEH_KS_release (key_state);
    return ret;
  }
}


/**
 * Handle a "/refresh/reveal" request. This time, the client reveals the
 * private transfer keys except for the cut-and-choose value returned from
 * "/refresh/melt".  This function parses the revealed keys and secrets and
 * ultimately passes everything to #resolve_refresh_reveal_denominations()
 * which will verify that the revealed information is valid then runs the
 * transaction in #refresh_reveal_transaction() and finally returns the signed
 * refreshed coins.
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
  int res;
  json_t *root;
  json_t *coin_evs;
  json_t *transfer_privs;
  json_t *link_sigs;
  json_t *new_denoms_h;
  struct RevealContext rctx;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("rc", &rctx.rc),
    GNUNET_JSON_spec_fixed_auto ("transfer_pub", &rctx.gamma_tp),
    GNUNET_JSON_spec_json ("transfer_privs", &transfer_privs),
    GNUNET_JSON_spec_json ("link_sigs", &link_sigs),
    GNUNET_JSON_spec_json ("coin_evs", &coin_evs),
    GNUNET_JSON_spec_json ("new_denoms_h", &new_denoms_h),
    GNUNET_JSON_spec_end ()
  };

  (void) rh;
  res = TALER_MHD_parse_post_json (connection,
                                   connection_cls,
                                   upload_data,
                                   upload_data_size,
                                   &root);
  if (GNUNET_SYSERR == res)
    return MHD_NO;
  if ( (GNUNET_NO == res) ||
       (NULL == root) )
    return MHD_YES;

  memset (&rctx,
          0,
          sizeof (rctx));
  res = TALER_MHD_parse_json_data (connection,
                                   root,
                                   spec);
  json_decref (root);
  if (GNUNET_OK != res)
  {
    GNUNET_break_op (0);
    return (GNUNET_SYSERR == res) ? MHD_NO : MHD_YES;
  }

  /* Check we got enough transfer private keys */
  /* Note we do +1 as 1 row (cut-and-choose!) is missing! */
  if (TALER_CNC_KAPPA != json_array_size (transfer_privs) + 1)
  {
    GNUNET_JSON_parse_free (spec);
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_REFRESH_REVEAL_CNC_TRANSFER_ARRAY_SIZE_INVALID,
                                       "transfer_privs");
  }
  res = handle_refresh_reveal_json (connection,
                                    &rctx,
                                    transfer_privs,
                                    link_sigs,
                                    new_denoms_h,
                                    coin_evs);
  GNUNET_JSON_parse_free (spec);
  return res;
}


/* end of taler-exchange-httpd_refresh_reveal.c */
