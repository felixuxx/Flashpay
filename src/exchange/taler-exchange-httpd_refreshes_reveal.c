/*
  This file is part of TALER
  Copyright (C) 2014-2019, 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_refreshes_reveal.c
 * @brief Handle /refreshes/$RCH/reveal requests
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
#include "taler-exchange-httpd_refreshes_reveal.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"


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
 * Send a response for "/refreshes/$RCH/reveal".
 *
 * @param connection the connection to send the response to
 * @param num_freshcoins number of new coins for which we reveal data
 * @param sigs array of @a num_freshcoins signatures revealed
 * @return a MHD result code
 */
static MHD_RESULT
reply_refreshes_reveal_success (struct MHD_Connection *connection,
                                unsigned int num_freshcoins,
                                const struct
                                TALER_BlindedDenominationSignature *sigs)
{
  json_t *list;

  list = json_array ();
  GNUNET_assert (NULL != list);
  for (unsigned int freshcoin_index = 0;
       freshcoin_index < num_freshcoins;
       freshcoin_index++)
  {
    json_t *obj;

    obj = GNUNET_JSON_PACK (
      TALER_JSON_pack_blinded_denom_sig ("ev_sig",
                                         &sigs[freshcoin_index]));
    GNUNET_assert (0 ==
                   json_array_append_new (list,
                                          obj));
  }

  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_array_steal ("ev_sigs",
                                  list));
}


/**
 * State for a /refreshes/$RCH/reveal operation.
 */
struct RevealContext
{

  /**
   * Commitment of the refresh operation.
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
  const struct TEH_DenominationKey **dks;

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
  struct TALER_BlindedDenominationSignature *ev_sigs;

  /**
   * Size of the @e dks, @e rcds and @e ev_sigs arrays (if non-NULL).
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
 * @param num_freshcoins size of the @a rrcs array
 * @param rrcs array of @a num_freshcoins information about coins to be created
 * @param num_tprivs number of entries in @a tprivs, should be #TALER_CNC_KAPPA - 1
 * @param tprivs array of @e num_tprivs transfer private keys
 * @param tp transfer public key information
 */
static void
check_exists_cb (void *cls,
                 uint32_t num_freshcoins,
                 const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs,
                 unsigned int num_tprivs,
                 const struct TALER_TransferPrivateKeyP *tprivs,
                 const struct TALER_TransferPublicKeyP *tp)
{
  struct RevealContext *rctx = cls;

  if (0 == num_freshcoins)
  {
    GNUNET_break (0);
    return;
  }
  /* This should be a database invariant for us */
  GNUNET_break (TALER_CNC_KAPPA - 1 == num_tprivs);
  /* Given that the $RCH value matched, we don't actually need to check these
     values (we checked before). However, if a client repeats a request with
     invalid values the 2nd time, that's a protocol violation we should at least
     log (but it's safe to ignore it). */
  GNUNET_break_op (0 ==
                   GNUNET_memcmp (tp,
                                  &rctx->gamma_tp));
  GNUNET_break_op (0 ==
                   memcmp (tprivs,
                           &rctx->transfer_privs,
                           sizeof (struct TALER_TransferPrivateKeyP)
                           * num_tprivs));
  /* We usually sign early (optimistic!), but in case we change that *and*
     we do find the operation in the database, we could use this: */
  if (NULL == rctx->ev_sigs)
  {
    rctx->ev_sigs = GNUNET_new_array (num_freshcoins,
                                      struct TALER_BlindedDenominationSignature);
    for (unsigned int i = 0; i<num_freshcoins; i++)
      TALER_blinded_denom_sig_deep_copy (&rctx->ev_sigs[i],
                                         &rrcs[i].coin_sig);
  }
}


/**
 * Check if the "/refreshes/$RCH/reveal" request was already successful
 * before.  If so, just return the old result.
 *
 * @param cls closure of type `struct RevealContext`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
refreshes_reveal_preflight (void *cls,
                            struct MHD_Connection *connection,
                            MHD_RESULT *mhd_ret)
{
  struct RevealContext *rctx = cls;
  enum GNUNET_DB_QueryStatus qs;

  /* Try to see if we already have given an answer before. */
  qs = TEH_plugin->get_refresh_reveal (TEH_plugin->cls,
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
                                           TALER_EC_GENERIC_DB_FETCH_FAILED,
                                           "refresh reveal");
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
 * Execute a "/refreshes/$RCH/reveal".  The client is revealing to us the
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
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
refreshes_reveal_transaction (void *cls,
                              struct MHD_Connection *connection,
                              MHD_RESULT *mhd_ret)
{
  struct RevealContext *rctx = cls;
  struct TALER_EXCHANGEDB_Melt melt;
  enum GNUNET_DB_QueryStatus qs;

  /* Obtain basic information about the refresh operation and what
     gamma we committed to. */
  qs = TEH_plugin->get_melt (TEH_plugin->cls,
                             &rctx->rc,
                             &melt);
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_EXCHANGE_REFRESHES_REVEAL_SESSION_UNKNOWN,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    return qs;
  if ( (GNUNET_DB_STATUS_HARD_ERROR == qs) ||
       (melt.session.noreveal_index >= TALER_CNC_KAPPA) )
  {
    GNUNET_break (0);
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_FETCH_FAILED,
                                           "melt");
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  /* Verify commitment */
  {
    /* Note that the contents of rcs[melt.session.noreveal_index]
       will be aliased and are *not* allocated (or deallocated) in
       this function -- in contrast to the other offsets! */
    struct TALER_RefreshCommitmentEntry rcs[TALER_CNC_KAPPA];
    struct TALER_RefreshCommitmentP rc_expected;
    unsigned int off;

    off = 0; /* did we pass session.noreveal_index yet? */
    for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
    {
      struct TALER_RefreshCommitmentEntry *rce = &rcs[i];

      if (i == melt.session.noreveal_index)
      {
        /* Take these coin envelopes from the client */
        rce->transfer_pub = rctx->gamma_tp;
        rce->new_coins = (struct TALER_RefreshCoinData *) rctx->rcds;
        off = 1;
      }
      else
      {
        /* Reconstruct coin envelopes from transfer private key */
        const struct TALER_TransferPrivateKeyP *tpriv
          = &rctx->transfer_privs[i - off];
        struct TALER_TransferSecretP ts;

        GNUNET_CRYPTO_ecdhe_key_get_public (&tpriv->ecdhe_priv,
                                            &rce->transfer_pub.ecdhe_pub);
        TALER_link_reveal_transfer_secret (tpriv,
                                           &melt.session.coin.coin_pub,
                                           &ts);
        rce->new_coins = GNUNET_new_array (rctx->num_fresh_coins,
                                           struct TALER_RefreshCoinData);
        for (unsigned int j = 0; j<rctx->num_fresh_coins; j++)
        {
          struct TALER_RefreshCoinData *rcd = &rce->new_coins[j];
          struct TALER_PlanchetSecretsP ps;
          struct TALER_PlanchetDetail pd;
          struct TALER_CoinPubHash c_hash;

          rcd->dk = &rctx->dks[j]->denom_pub;
          TALER_planchet_setup_refresh (&ts,
                                        j,
                                        &ps);
          GNUNET_assert (GNUNET_OK ==
                         TALER_planchet_prepare (rcd->dk,
                                                 &ps,
                                                 &c_hash,
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
                                  &melt.session.coin.coin_pub,
                                  &melt.session.amount_with_fee);

    /* Free resources allocated above */
    for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
    {
      struct TALER_RefreshCommitmentEntry *rce = &rcs[i];

      if (i == melt.session.noreveal_index)
        continue; /* This offset is special: not allocated! */
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
      *mhd_ret = TALER_MHD_REPLY_JSON_PACK (
        connection,
        MHD_HTTP_CONFLICT,
        TALER_JSON_pack_ec (
          TALER_EC_EXCHANGE_REFRESHES_REVEAL_COMMITMENT_VIOLATION),
        GNUNET_JSON_pack_data_auto ("rc_expected",
                                    &rc_expected));
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  } /* end of checking "rc_expected" */

  /* check amounts add up! */
  {
    struct TALER_Amount refresh_cost;

    refresh_cost = melt.melt_fee;
    for (unsigned int i = 0; i<rctx->num_fresh_coins; i++)
    {
      struct TALER_Amount total;

      if ( (0 >
            TALER_amount_add (&total,
                              &rctx->dks[i]->meta.fee_withdraw,
                              &rctx->dks[i]->meta.value)) ||
           (0 >
            TALER_amount_add (&refresh_cost,
                              &refresh_cost,
                              &total)) )
      {
        GNUNET_break_op (0);
        *mhd_ret = TALER_MHD_reply_with_error (connection,
                                               MHD_HTTP_INTERNAL_SERVER_ERROR,
                                               TALER_EC_EXCHANGE_REFRESHES_REVEAL_COST_CALCULATION_OVERFLOW,
                                               NULL);
        return GNUNET_DB_STATUS_HARD_ERROR;
      }
    }
    if (0 < TALER_amount_cmp (&refresh_cost,
                              &melt.session.amount_with_fee))
    {
      GNUNET_break_op (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_BAD_REQUEST,
                                             TALER_EC_EXCHANGE_REFRESHES_REVEAL_AMOUNT_INSUFFICIENT,
                                             NULL);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
}


/**
 * Persist result of a "/refreshes/$RCH/reveal" operation.
 *
 * @param cls closure of type `struct RevealContext`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
refreshes_reveal_persist (void *cls,
                          struct MHD_Connection *connection,
                          MHD_RESULT *mhd_ret)
{
  struct RevealContext *rctx = cls;
  enum GNUNET_DB_QueryStatus qs;

  /* Persist operation result in DB */
  {
    struct TALER_EXCHANGEDB_RefreshRevealedCoin rrcs[rctx->num_fresh_coins];

    for (unsigned int i = 0; i<rctx->num_fresh_coins; i++)
    {
      struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &rrcs[i];

      rrc->denom_pub = rctx->dks[i]->denom_pub;
      rrc->orig_coin_link_sig = rctx->link_sigs[i];
      rrc->coin_ev = rctx->rcds[i].coin_ev;
      rrc->coin_ev_size = rctx->rcds[i].coin_ev_size;
      rrc->coin_sig = rctx->ev_sigs[i];
    }
    qs = TEH_plugin->insert_refresh_reveal (TEH_plugin->cls,
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
                                           TALER_EC_GENERIC_DB_STORE_FAILED,
                                           "refresh_reveal");
  }
  return qs;
}


/**
 * Resolve denomination hashes.
 *
 * @param connection the MHD connection to handle
 * @param rctx context for the operation, partially built at this time
 * @param link_sigs_json link signatures in JSON format
 * @param new_denoms_h_json requests for fresh coins to be created
 * @param coin_evs envelopes of gamma-selected coins to be signed
 * @return MHD result code
 */
static MHD_RESULT
resolve_refreshes_reveal_denominations (struct MHD_Connection *connection,
                                        struct RevealContext *rctx,
                                        const json_t *link_sigs_json,
                                        const json_t *new_denoms_h_json,
                                        const json_t *coin_evs)
{
  unsigned int num_fresh_coins = json_array_size (new_denoms_h_json);
  /* We know num_fresh_coins is bounded by #MAX_FRESH_COINS, so this is safe */
  const struct TEH_DenominationKey *dks[num_fresh_coins];
  struct TALER_DenominationHash dk_h[num_fresh_coins];
  struct TALER_RefreshCoinData rcds[num_fresh_coins];
  struct TALER_CoinSpendSignatureP link_sigs[num_fresh_coins];
  struct TALER_EXCHANGEDB_Melt melt;
  enum GNUNET_GenericReturnValue res;
  MHD_RESULT ret;
  struct TEH_KeyStateHandle *ksh;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                       NULL);
  }
  /* Parse denomination key hashes */
  for (unsigned int i = 0; i<num_fresh_coins; i++)
  {
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto (NULL,
                                   &dk_h[i]),
      GNUNET_JSON_spec_end ()
    };
    MHD_RESULT mret;

    res = TALER_MHD_parse_json_array (connection,
                                      new_denoms_h_json,
                                      spec,
                                      i,
                                      -1);
    if (GNUNET_OK != res)
    {
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }
    dks[i] = TEH_keys_denomination_by_hash2 (ksh,
                                             &dk_h[i],
                                             connection,
                                             &mret);
    if (NULL == dks[i])
      return mret;

    if (GNUNET_TIME_absolute_is_past (dks[i]->meta.expire_withdraw))
    {
      struct GNUNET_TIME_Absolute now;

      now = GNUNET_TIME_absolute_get ();
      (void) GNUNET_TIME_round_abs (&now);
      /* This denomination is past the expiration time for withdraws */
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        connection,
        &dk_h[i],
        now,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
        "REVEAL");
    }
    if (GNUNET_TIME_absolute_is_future (dks[i]->meta.start))
    {
      struct GNUNET_TIME_Absolute now;

      now = GNUNET_TIME_absolute_get ();
      (void) GNUNET_TIME_round_abs (&now);
      /* This denomination is not yet valid */
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        connection,
        &dk_h[i],
        now,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
        "REVEAL");
    }
    if (dks[i]->recoup_possible)
    {
      /* This denomination has been revoked */
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_GONE,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
        NULL);
    }
  }

  /* Parse coin envelopes */
  for (unsigned int i = 0; i<num_fresh_coins; i++)
  {
    struct TALER_RefreshCoinData *rcd = &rcds[i];
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_varsize (NULL,
                                &rcd->coin_ev,
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
        GNUNET_free (rcds[j].coin_ev);
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }
    rcd->dk = &dks[i]->denom_pub;
  }

  /* lookup old_coin_pub in database */
  {
    enum GNUNET_DB_QueryStatus qs;

    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
        (qs = TEH_plugin->get_melt (TEH_plugin->cls,
                                    &rctx->rc,
                                    &melt)))
    {
      switch (qs)
      {
      case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
        ret = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_NOT_FOUND,
                                          TALER_EC_EXCHANGE_REFRESHES_REVEAL_SESSION_UNKNOWN,
                                          NULL);
        break;
      case GNUNET_DB_STATUS_HARD_ERROR:
        ret = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_GENERIC_DB_FETCH_FAILED,
                                          "melt");
        break;
      case GNUNET_DB_STATUS_SOFT_ERROR:
      default:
        GNUNET_break (0);   /* should be impossible */
        ret = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
                                          NULL);
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

    res = TALER_MHD_parse_json_array (connection,
                                      link_sigs_json,
                                      link_spec,
                                      i,
                                      -1);
    if (GNUNET_OK != res)
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    /* Check link_sigs[i] signature */
    if (GNUNET_OK !=
        TALER_wallet_link_verify (
          &dk_h[i],
          &rctx->gamma_tp,
          rcds[i].coin_ev,
          rcds[i].coin_ev_size,
          &melt.session.coin.coin_pub,
          &link_sigs[i]))
    {
      GNUNET_break_op (0);
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_FORBIDDEN,
        TALER_EC_EXCHANGE_REFRESHES_REVEAL_LINK_SIGNATURE_INVALID,
        NULL);
      goto cleanup;
    }
  }

  rctx->num_fresh_coins = num_fresh_coins;
  rctx->rcds = rcds;
  rctx->dks = dks;
  rctx->link_sigs = link_sigs;

  /* sign _early_ (optimistic!) to keep out of transaction scope! */
  rctx->ev_sigs = GNUNET_new_array (rctx->num_fresh_coins,
                                    struct TALER_BlindedDenominationSignature);
  for (unsigned int i = 0; i<rctx->num_fresh_coins; i++)
  {
    enum TALER_ErrorCode ec = TALER_EC_NONE;

    rctx->ev_sigs[i]
      = TEH_keys_denomination_sign (
          &dk_h[i],
          rctx->rcds[i].coin_ev,
          rctx->rcds[i].coin_ev_size,
          &ec);
    if (TALER_EC_NONE != ec)
    {
      GNUNET_break (0);
      ret = TALER_MHD_reply_with_ec (connection,
                                     ec,
                                     NULL);
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
                                  &ret,
                                  &refreshes_reveal_preflight,
                                  rctx)) &&
         (GNUNET_YES == rctx->preflight_ok) )
    {
      /* Generate final (positive) response */
      GNUNET_assert (NULL != rctx->ev_sigs);
      ret = reply_refreshes_reveal_success (connection,
                                            num_fresh_coins,
                                            rctx->ev_sigs);
      GNUNET_break (MHD_NO != ret);
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
                                &ret,
                                &refreshes_reveal_transaction,
                                rctx))
    {
      /* reveal failed, too bad */
      GNUNET_break_op (0);
      goto cleanup;   /* aka 'break' */
    }
    if (GNUNET_OK ==
        TEH_DB_run_transaction (connection,
                                "persist reveal",
                                &ret,
                                &refreshes_reveal_persist,
                                rctx))
    {
      /* Generate final (positive) response */
      GNUNET_assert (NULL != rctx->ev_sigs);
      ret = reply_refreshes_reveal_success (connection,
                                            num_fresh_coins,
                                            rctx->ev_sigs);
      break;
    }
    /* If we get here, the final transaction failed, possibly
       due to a conflict between the pre-flight and us persisting
       the result, so we go again. */
  }   /* end for (retries...) */

cleanup:
  GNUNET_break (MHD_NO != ret);
  /* free resources */
  if (NULL != rctx->ev_sigs)
  {
    for (unsigned int i = 0; i<num_fresh_coins; i++)
      TALER_blinded_denom_sig_free (&rctx->ev_sigs[i]);
    GNUNET_free (rctx->ev_sigs);
    rctx->ev_sigs = NULL; /* just to be safe... */
  }
  for (unsigned int i = 0; i<num_fresh_coins; i++)
    GNUNET_free (rcds[i].coin_ev);
  return ret;
}


/**
 * Handle a "/refreshes/$RCH/reveal" request.   Parses the given JSON
 * transfer private keys and if successful, passes everything to
 * #resolve_refreshes_reveal_denominations() which will verify that the
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
static MHD_RESULT
handle_refreshes_reveal_json (struct MHD_Connection *connection,
                              struct RevealContext *rctx,
                              const json_t *tp_json,
                              const json_t *link_sigs_json,
                              const json_t *new_denoms_h_json,
                              const json_t *coin_evs)
{
  unsigned int num_fresh_coins = json_array_size (new_denoms_h_json);
  unsigned int num_tprivs = json_array_size (tp_json);

  GNUNET_assert (num_tprivs == TALER_CNC_KAPPA - 1); /* checked just earlier */
  if ( (num_fresh_coins >= MAX_FRESH_COINS) ||
       (0 == num_fresh_coins) )
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_REFRESHES_REVEAL_NEW_DENOMS_ARRAY_SIZE_EXCESSIVE,
                                       NULL);

  }
  if (json_array_size (new_denoms_h_json) !=
      json_array_size (coin_evs))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_REFRESHES_REVEAL_NEW_DENOMS_ARRAY_SIZE_MISMATCH,
                                       "new_denoms/coin_evs");
  }
  if (json_array_size (new_denoms_h_json) !=
      json_array_size (link_sigs_json))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_REFRESHES_REVEAL_NEW_DENOMS_ARRAY_SIZE_MISMATCH,
                                       "new_denoms/link_sigs");
  }

  /* Parse transfer private keys array */
  for (unsigned int i = 0; i<num_tprivs; i++)
  {
    struct GNUNET_JSON_Specification trans_spec[] = {
      GNUNET_JSON_spec_fixed_auto (NULL, &rctx->transfer_privs[i]),
      GNUNET_JSON_spec_end ()
    };
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_array (connection,
                                      tp_json,
                                      trans_spec,
                                      i,
                                      -1);
    if (GNUNET_OK != res)
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
  }

  return resolve_refreshes_reveal_denominations (connection,
                                                 rctx,
                                                 link_sigs_json,
                                                 new_denoms_h_json,
                                                 coin_evs);
}


MHD_RESULT
TEH_handler_reveal (struct TEH_RequestContext *rc,
                    const json_t *root,
                    const char *const args[2])
{
  json_t *coin_evs;
  json_t *transfer_privs;
  json_t *link_sigs;
  json_t *new_denoms_h;
  struct RevealContext rctx;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("transfer_pub", &rctx.gamma_tp),
    GNUNET_JSON_spec_json ("transfer_privs", &transfer_privs),
    GNUNET_JSON_spec_json ("link_sigs", &link_sigs),
    GNUNET_JSON_spec_json ("coin_evs", &coin_evs),
    GNUNET_JSON_spec_json ("new_denoms_h", &new_denoms_h),
    GNUNET_JSON_spec_end ()
  };

  memset (&rctx,
          0,
          sizeof (rctx));
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &rctx.rc,
                                     sizeof (rctx.rc)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_REFRESHES_REVEAL_INVALID_RCH,
                                       args[0]);
  }
  if (0 != strcmp (args[1],
                   "reveal"))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_REFRESHES_REVEAL_OPERATION_INVALID,
                                       args[1]);
  }

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

  /* Check we got enough transfer private keys */
  /* Note we do +1 as 1 row (cut-and-choose!) is missing! */
  if (TALER_CNC_KAPPA != json_array_size (transfer_privs) + 1)
  {
    GNUNET_JSON_parse_free (spec);
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_REFRESHES_REVEAL_CNC_TRANSFER_ARRAY_SIZE_INVALID,
                                       NULL);
  }

  {
    MHD_RESULT res;

    res = handle_refreshes_reveal_json (rc->connection,
                                        &rctx,
                                        transfer_privs,
                                        link_sigs,
                                        new_denoms_h,
                                        coin_evs);
    GNUNET_JSON_parse_free (spec);
    return res;
  }
}


/* end of taler-exchange-httpd_refreshes_reveal.c */
