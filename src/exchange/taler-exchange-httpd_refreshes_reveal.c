/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * Send a response for "/refreshes/$RCH/reveal".
 *
 * @param connection the connection to send the response to
 * @param num_freshcoins number of new coins for which we reveal data
 * @param rrcs array of @a num_freshcoins signatures revealed
 * @return a MHD result code
 */
static MHD_RESULT
reply_refreshes_reveal_success (
  struct MHD_Connection *connection,
  unsigned int num_freshcoins,
  const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs)
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
                                         &rrcs[freshcoin_index].coin_sig));
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
   * Melt data for our session we got from the database for @e rc.
   */
  struct TALER_EXCHANGEDB_Melt melt;

  /**
   * Denominations being requested.
   */
  const struct TEH_DenominationKey **dks;

  /**
   * Age commitment that was used for the original coin.  If not NULL, its hash
   * should be the same as melt.session.h_age_commitment.
   */
  struct TALER_AgeCommitment *old_age_commitment;

  /**
   * Array of information about fresh coins being revealed.
   */
  struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs;

  /**
   * Envelopes to be signed.
   */
  struct TALER_RefreshCoinData *rcds;

  /**
   * Refresh master secret.
   */
  struct TALER_RefreshMasterSecretP rms;

  /**
   * Size of the @e dks, @e rcds and @e ev_sigs arrays (if non-NULL).
   */
  unsigned int num_fresh_coins;

  /**
   * True if @e rms was not provided.
   */
  bool no_rms;
};


/**
 * Check client's revelation against the original commitment.
 * The client is revealing to us the
 * transfer keys for @a #TALER_CNC_KAPPA-1 sets of coins.  Verify that the
 * revealed transfer keys would allow linkage to the blinded coins.
 *
 * IF it returns #GNUNET_OK, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.
 *
 * @param rctx our operation context
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return #GNUNET_OK if commitment was OK
 */
static enum GNUNET_GenericReturnValue
check_commitment (struct RevealContext *rctx,
                  struct MHD_Connection *connection,
                  MHD_RESULT *mhd_ret)
{
  const union GNUNET_CRYPTO_BlindSessionNonce *nonces[rctx->num_fresh_coins];

  memset (nonces,
          0,
          sizeof (nonces));
  for (unsigned int j = 0; j<rctx->num_fresh_coins; j++)
  {
    const struct TALER_DenominationPublicKey *dk = &rctx->dks[j]->denom_pub;

    if (dk->bsign_pub_key->cipher !=
        rctx->rcds[j].blinded_planchet.blinded_message->cipher)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH,
        NULL);
      return GNUNET_SYSERR;
    }
    switch (dk->bsign_pub_key->cipher)
    {
    case GNUNET_CRYPTO_BSA_INVALID:
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_INTERNAL_SERVER_ERROR,
        TALER_EC_GENERIC_INTERNAL_INVARIANT_FAILURE,
        NULL);
      return GNUNET_SYSERR;
    case GNUNET_CRYPTO_BSA_RSA:
      continue;
    case GNUNET_CRYPTO_BSA_CS:
      nonces[j]
        = (const union GNUNET_CRYPTO_BlindSessionNonce *)
          &rctx->rcds[j].blinded_planchet.blinded_message->details.
          cs_blinded_message.nonce;
      break;
    }
  }

  // OPTIMIZE: do this in batch later!
  for (unsigned int j = 0; j<rctx->num_fresh_coins; j++)
  {
    const struct TALER_DenominationPublicKey *dk = &rctx->dks[j]->denom_pub;
    struct TALER_ExchangeWithdrawValues *alg_values
      = &rctx->rrcs[j].exchange_vals;
    struct GNUNET_CRYPTO_BlindingInputValues *bi;

    bi = GNUNET_new (struct GNUNET_CRYPTO_BlindingInputValues);
    alg_values->blinding_inputs = bi;
    bi->rc = 1;
    bi->cipher = dk->bsign_pub_key->cipher;
    switch (dk->bsign_pub_key->cipher)
    {
    case GNUNET_CRYPTO_BSA_INVALID:
      GNUNET_assert (0);
      return GNUNET_SYSERR;
    case GNUNET_CRYPTO_BSA_RSA:
      continue;
    case GNUNET_CRYPTO_BSA_CS:
      {
        enum TALER_ErrorCode ec;
        const struct TEH_CsDeriveData cdd = {
          .h_denom_pub = &rctx->rrcs[j].h_denom_pub,
          .nonce = &nonces[j]->cs_nonce
        };

        ec = TEH_keys_denomination_cs_r_pub (
          &cdd,
          true,
          &bi->details.cs_values);
        if (TALER_EC_NONE != ec)
        {
          *mhd_ret = TALER_MHD_reply_with_error (connection,
                                                 MHD_HTTP_INTERNAL_SERVER_ERROR,
                                                 ec,
                                                 NULL);
          return GNUNET_SYSERR;
        }
      }
    }
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

      if (i == rctx->melt.session.noreveal_index)
      {
        /* Take these coin envelopes from the client */
        rce->transfer_pub = rctx->gamma_tp;
        rce->new_coins = rctx->rcds;
        off = 1;
      }
      else
      {
        /* Reconstruct coin envelopes from transfer private key */
        const struct TALER_TransferPrivateKeyP *tpriv
          = &rctx->transfer_privs[i - off];
        struct TALER_TransferSecretP ts;
        struct TALER_AgeCommitmentHash h = {0};
        struct TALER_AgeCommitmentHash *hac = NULL;

        GNUNET_CRYPTO_ecdhe_key_get_public (&tpriv->ecdhe_priv,
                                            &rce->transfer_pub.ecdhe_pub);
        TEH_METRICS_num_keyexchanges[TEH_MT_KEYX_ECDH]++;
        TALER_link_reveal_transfer_secret (tpriv,
                                           &rctx->melt.session.coin.coin_pub,
                                           &ts);
        rce->new_coins = GNUNET_new_array (rctx->num_fresh_coins,
                                           struct TALER_RefreshCoinData);
        for (unsigned int j = 0; j<rctx->num_fresh_coins; j++)
        {
          struct TALER_RefreshCoinData *rcd = &rce->new_coins[j];
          struct TALER_CoinSpendPrivateKeyP coin_priv;
          union GNUNET_CRYPTO_BlindingSecretP bks;
          const struct TALER_ExchangeWithdrawValues *alg_value
            = &rctx->rrcs[j].exchange_vals;
          struct TALER_PlanchetDetail pd = {0};
          struct TALER_CoinPubHashP c_hash;
          struct TALER_PlanchetMasterSecretP ps;

          rcd->dk = &rctx->dks[j]->denom_pub;
          TALER_transfer_secret_to_planchet_secret (&ts,
                                                    j,
                                                    &ps);
          TALER_planchet_setup_coin_priv (&ps,
                                          alg_value,
                                          &coin_priv);
          TALER_planchet_blinding_secret_create (&ps,
                                                 alg_value,
                                                 &bks);
          /* Calculate, if applicable, the age commitment and its hash, from
           * the transfer_secret and the old age commitment. */
          if (NULL != rctx->old_age_commitment)
          {
            struct TALER_AgeCommitmentProof acp = {
              /* we only need the commitment, not the proof, for the call to
               * TALER_age_commitment_derive. */
              .commitment = *(rctx->old_age_commitment)
            };
            struct TALER_AgeCommitmentProof nacp = {0};

            GNUNET_assert (GNUNET_OK ==
                           TALER_age_commitment_derive (
                             &acp,
                             &ts.key,
                             &nacp));
            TALER_age_commitment_hash (&nacp.commitment,
                                       &h);
            TALER_age_commitment_proof_free (&nacp);
            hac = &h;
          }

          GNUNET_assert (GNUNET_OK ==
                         TALER_planchet_prepare (rcd->dk,
                                                 alg_value,
                                                 &bks,
                                                 nonces[j],
                                                 &coin_priv,
                                                 hac,
                                                 &c_hash,
                                                 &pd));
          rcd->blinded_planchet = pd.blinded_planchet;
        }
      }
    }
    TALER_refresh_get_commitment (&rc_expected,
                                  TALER_CNC_KAPPA,
                                  rctx->no_rms
                                  ? NULL
                                  : &rctx->rms,
                                  rctx->num_fresh_coins,
                                  rcs,
                                  &rctx->melt.session.coin.coin_pub,
                                  &rctx->melt.session.amount_with_fee);

    /* Free resources allocated above */
    for (unsigned int i = 0; i<TALER_CNC_KAPPA; i++)
    {
      struct TALER_RefreshCommitmentEntry *rce = &rcs[i];

      if (i == rctx->melt.session.noreveal_index)
        continue; /* This offset is special: not allocated! */
      for (unsigned int j = 0; j<rctx->num_fresh_coins; j++)
      {
        struct TALER_RefreshCoinData *rcd = &rce->new_coins[j];

        TALER_blinded_planchet_free (&rcd->blinded_planchet);
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
      return GNUNET_SYSERR;
    }
  } /* end of checking "rc_expected" */

  /* check amounts add up! */
  {
    struct TALER_Amount refresh_cost;

    refresh_cost = rctx->melt.melt_fee;
    for (unsigned int i = 0; i<rctx->num_fresh_coins; i++)
    {
      struct TALER_Amount total;

      if ( (0 >
            TALER_amount_add (&total,
                              &rctx->dks[i]->meta.fees.withdraw,
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
        return GNUNET_SYSERR;
      }
    }
    if (0 < TALER_amount_cmp (&refresh_cost,
                              &rctx->melt.session.amount_with_fee))
    {
      GNUNET_break_op (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_BAD_REQUEST,
                                             TALER_EC_EXCHANGE_REFRESHES_REVEAL_AMOUNT_INSUFFICIENT,
                                             NULL);
      return GNUNET_SYSERR;
    }
  }
  return GNUNET_OK;
}


/**
 * Resolve denomination hashes.
 *
 * @param connection the MHD connection to handle
 * @param rctx context for the operation, partially built at this time
 * @param link_sigs_json link signatures in JSON format
 * @param new_denoms_h_json requests for fresh coins to be created
 * @param old_age_commitment_json age commitment that went into the withdrawal, maybe NULL
 * @param coin_evs envelopes of gamma-selected coins to be signed
 * @return MHD result code
 */
static MHD_RESULT
resolve_refreshes_reveal_denominations (
  struct MHD_Connection *connection,
  struct RevealContext *rctx,
  const json_t *link_sigs_json,
  const json_t *new_denoms_h_json,
  const json_t *old_age_commitment_json,
  const json_t *coin_evs)
{
  unsigned int num_fresh_coins = json_array_size (new_denoms_h_json);
  /* We know num_fresh_coins is bounded by #TALER_MAX_FRESH_COINS, so this is safe */
  const struct TEH_DenominationKey *dks[num_fresh_coins];
  const struct TEH_DenominationKey *old_dk;
  struct TALER_RefreshCoinData rcds[num_fresh_coins];
  struct TALER_EXCHANGEDB_RefreshRevealedCoin rrcs[num_fresh_coins];
  MHD_RESULT ret;
  struct TEH_KeyStateHandle *ksh;
  uint64_t melt_serial_id;

  memset (dks, 0, sizeof (dks));
  memset (rrcs, 0, sizeof (rrcs));
  memset (rcds, 0, sizeof (rcds));
  rctx->num_fresh_coins = num_fresh_coins;

  ksh = TEH_keys_get_state ();
  if (NULL == ksh)
  {
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                       NULL);
  }

  /* lookup old_coin_pub in database */
  {
    enum GNUNET_DB_QueryStatus qs;

    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
        (qs = TEH_plugin->get_melt (TEH_plugin->cls,
                                    &rctx->rc,
                                    &rctx->melt,
                                    &melt_serial_id)))
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
    if (rctx->melt.session.noreveal_index >= TALER_CNC_KAPPA)
    {
      GNUNET_break (0);
      ret = TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_INTERNAL_SERVER_ERROR,
                                        TALER_EC_GENERIC_DB_FETCH_FAILED,
                                        "melt");
      goto cleanup;
    }
  }

  old_dk = TEH_keys_denomination_by_hash_from_state (
    ksh,
    &rctx->melt.session.coin.denom_pub_hash,
    connection,
    &ret);
  if (NULL == old_dk)
    return ret;

  /* Parse denomination key hashes */
  for (unsigned int i = 0; i<num_fresh_coins; i++)
  {
    struct GNUNET_JSON_Specification spec[] = {
      GNUNET_JSON_spec_fixed_auto (NULL,
                                   &rrcs[i].h_denom_pub),
      GNUNET_JSON_spec_end ()
    };
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_array (connection,
                                      new_denoms_h_json,
                                      spec,
                                      i,
                                      -1);
    if (GNUNET_OK != res)
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    dks[i] = TEH_keys_denomination_by_hash_from_state (ksh,
                                                       &rrcs[i].h_denom_pub,
                                                       connection,
                                                       &ret);
    if (NULL == dks[i])
      return ret;
    if ( (GNUNET_CRYPTO_BSA_CS ==
          dks[i]->denom_pub.bsign_pub_key->cipher) &&
         (rctx->no_rms) )
    {
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MISSING,
        "rms");
    }
    if (GNUNET_TIME_absolute_is_past (dks[i]->meta.expire_withdraw.abs_time))
    {
      /* This denomination is past the expiration time for withdraws */
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        connection,
        &rrcs[i].h_denom_pub,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
        "REVEAL");
    }
    if (GNUNET_TIME_absolute_is_future (dks[i]->meta.start.abs_time))
    {
      /* This denomination is not yet valid */
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        connection,
        &rrcs[i].h_denom_pub,
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
    struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &rrcs[i];
    struct GNUNET_JSON_Specification spec[] = {
      TALER_JSON_spec_blinded_planchet (NULL,
                                        &rrc->blinded_planchet),
      GNUNET_JSON_spec_end ()
    };
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_array (connection,
                                      coin_evs,
                                      spec,
                                      i,
                                      -1);
    if (GNUNET_OK != res)
    {
      for (unsigned int j = 0; j<i; j++)
        TALER_blinded_planchet_free (&rrcs[j].blinded_planchet);
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }
    TALER_coin_ev_hash (&rrc->blinded_planchet,
                        &rrcs[i].h_denom_pub,
                        &rrc->coin_envelope_hash);
  }

  if (TEH_age_restriction_enabled &&
      ((NULL == old_age_commitment_json) !=
       TALER_AgeCommitmentHash_isNullOrZero (
         &rctx->melt.session.coin.h_age_commitment)))
  {
    GNUNET_break (0);
    return MHD_NO;
  }

  /* Reconstruct the old age commitment and verify its hash matches the one
   * from the melt request */
  if (TEH_age_restriction_enabled &&
      (NULL != old_age_commitment_json))
  {
    enum GNUNET_GenericReturnValue res;
    struct TALER_AgeCommitment *oac;
    size_t ng = json_array_size (old_age_commitment_json);
    bool failed = true;

    /* Has been checked in handle_refreshes_reveal_json() */
    GNUNET_assert (ng == TEH_age_restriction_config.num_groups);

    rctx->old_age_commitment = GNUNET_new (struct TALER_AgeCommitment);
    oac = rctx->old_age_commitment;
    oac->mask = old_dk->meta.age_mask;
    oac->num = ng;
    oac->keys = GNUNET_new_array (ng, struct TALER_AgeCommitmentPublicKeyP);

    /* Extract old age commitment */
    for (unsigned int i = 0; i< ng; i++)
    {
      struct GNUNET_JSON_Specification ac_spec[] = {
        GNUNET_JSON_spec_fixed_auto (NULL,
                                     &oac->keys[i]),
        GNUNET_JSON_spec_end ()
      };

      res = TALER_MHD_parse_json_array (connection,
                                        old_age_commitment_json,
                                        ac_spec,
                                        i,
                                        -1);

      GNUNET_break_op (GNUNET_OK == res);
      if (GNUNET_OK != res)
        goto clean_age;
    }

    /* Sanity check: Compare hash from melting with hash of this age commitment */
    {
      struct TALER_AgeCommitmentHash hac = {0};
      TALER_age_commitment_hash (oac, &hac);
      if (0 != memcmp (&hac,
                       &rctx->melt.session.coin.h_age_commitment,
                       sizeof(struct TALER_AgeCommitmentHash)))
        goto clean_age;
    }

    failed = false;

clean_age:
    if (failed)
    {
      TALER_age_commitment_free (oac);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_REFRESHES_REVEAL_AGE_RESTRICTION_COMMITMENT_INVALID,
                                         "old_age_commitment");
    }
  }

  /* Parse link signatures array */
  for (unsigned int i = 0; i<num_fresh_coins; i++)
  {
    struct GNUNET_JSON_Specification link_spec[] = {
      GNUNET_JSON_spec_fixed_auto (NULL,
                                   &rrcs[i].orig_coin_link_sig),
      GNUNET_JSON_spec_end ()
    };
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_array (connection,
                                      link_sigs_json,
                                      link_spec,
                                      i,
                                      -1);
    if (GNUNET_OK != res)
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;

    /* Check signature */
    TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
    if (GNUNET_OK !=
        TALER_wallet_link_verify (
          &rrcs[i].h_denom_pub,
          &rctx->gamma_tp,
          &rrcs[i].coin_envelope_hash,
          &rctx->melt.session.coin.coin_pub,
          &rrcs[i].orig_coin_link_sig))
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

  /* prepare for check_commitment */
  for (unsigned int i = 0; i<rctx->num_fresh_coins; i++)
  {
    const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &rrcs[i];
    struct TALER_RefreshCoinData *rcd = &rcds[i];

    rcd->blinded_planchet = rrc->blinded_planchet;
    rcd->dk = &dks[i]->denom_pub;
    if (rcd->blinded_planchet.blinded_message->cipher !=
        rcd->dk->bsign_pub_key->cipher)
    {
      GNUNET_break_op (0);
      ret = TALER_MHD_REPLY_JSON_PACK (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_JSON_pack_ec (
          TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH));
      goto cleanup;
    }
  }

  rctx->dks = dks;
  rctx->rcds = rcds;
  rctx->rrcs = rrcs;
  if (GNUNET_OK !=
      check_commitment (rctx,
                        connection,
                        &ret))
    goto cleanup;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Creating %u signatures\n",
              (unsigned int) rctx->num_fresh_coins);

  /* create fresh coin signatures */
  {
    struct TEH_CoinSignData csds[rctx->num_fresh_coins];
    struct TALER_BlindedDenominationSignature bss[rctx->num_fresh_coins];
    enum TALER_ErrorCode ec;

    for (unsigned int i = 0; i<rctx->num_fresh_coins; i++)
    {
      csds[i].h_denom_pub = &rrcs[i].h_denom_pub;
      csds[i].bp = &rcds[i].blinded_planchet;
    }
    ec = TEH_keys_denomination_batch_sign (
      rctx->num_fresh_coins,
      csds,
      true,
      bss);
    if (TALER_EC_NONE != ec)
    {
      GNUNET_break (0);
      ret = TALER_MHD_reply_with_ec (connection,
                                     ec,
                                     NULL);
      goto cleanup;
    }

    for (unsigned int i = 0; i<rctx->num_fresh_coins; i++)
    {
      rrcs[i].coin_sig = bss[i];
      rrcs[i].blinded_planchet = rcds[i].blinded_planchet;
    }
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Signatures ready, starting DB interaction\n");

  {
    enum GNUNET_DB_QueryStatus qs;

    for (unsigned int r = 0; r<MAX_TRANSACTION_COMMIT_RETRIES; r++)
    {
      bool changed;

      /* Persist operation result in DB */
      if (GNUNET_OK !=
          TEH_plugin->start (TEH_plugin->cls,
                             "insert_refresh_reveal batch"))
      {
        GNUNET_break (0);
        ret = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_GENERIC_DB_START_FAILED,
                                          NULL);
        goto cleanup;
      }

      qs = TEH_plugin->insert_refresh_reveal (
        TEH_plugin->cls,
        melt_serial_id,
        num_fresh_coins,
        rrcs,
        TALER_CNC_KAPPA - 1,
        rctx->transfer_privs,
        &rctx->gamma_tp);
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      {
        TEH_plugin->rollback (TEH_plugin->cls);
        continue;
      }
      /* 0 == qs is ok, as we did not check for repeated requests */
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      {
        GNUNET_break (0);
        TEH_plugin->rollback (TEH_plugin->cls);
        ret = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_GENERIC_DB_STORE_FAILED,
                                          "insert_refresh_reveal");
        goto cleanup;
      }
      changed = (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs);
      qs = TEH_plugin->commit (TEH_plugin->cls);
      if (qs >= 0)
      {
        if (changed)
          TEH_METRICS_num_success[TEH_MT_SUCCESS_REFRESH_REVEAL]++;
        break; /* success */
      }
      if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      {
        GNUNET_break (0);
        TEH_plugin->rollback (TEH_plugin->cls);
        ret = TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_INTERNAL_SERVER_ERROR,
                                          TALER_EC_GENERIC_DB_COMMIT_FAILED,
                                          NULL);
        goto cleanup;
      }
      TEH_plugin->rollback (TEH_plugin->cls);
    }
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
    {
      GNUNET_break (0);
      TEH_plugin->rollback (TEH_plugin->cls);
      ret = TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_INTERNAL_SERVER_ERROR,
                                        TALER_EC_GENERIC_DB_SOFT_FAILURE,
                                        NULL);
      goto cleanup;
    }
  }
  /* Generate final (positive) response */
  ret = reply_refreshes_reveal_success (connection,
                                        num_fresh_coins,
                                        rrcs);
cleanup:
  GNUNET_break (MHD_NO != ret);
  /* free resources */
  for (unsigned int i = 0; i<num_fresh_coins; i++)
  {
    struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrc = &rrcs[i];
    struct TALER_ExchangeWithdrawValues *alg_values
      = &rrcs[i].exchange_vals;

    GNUNET_free (alg_values->blinding_inputs);
    TALER_blinded_denom_sig_free (&rrc->coin_sig);
    TALER_blinded_planchet_free (&rrc->blinded_planchet);
  }
  return ret;
}


/**
 * Handle a "/refreshes/$RCH/reveal" request.   Parses the given JSON
 * transfer private keys and if successful, passes everything to
 * #resolve_refreshes_reveal_denominations() which will verify that the
 * revealed information is valid then returns the signed refreshed
 * coins.
 *
 * If the denomination has age restriction support, the array of EDDSA public
 * keys, one for each age group that was activated during the withdrawal
 * by the parent/ward, must be provided in old_age_commitment.  The hash of
 * this array must be the same as the h_age_commitment of the persisted reveal
 * request.
 *
 * @param connection the MHD connection to handle
 * @param rctx context for the operation, partially built at this time
 * @param tp_json private transfer keys in JSON format
 * @param link_sigs_json link signatures in JSON format
 * @param new_denoms_h_json requests for fresh coins to be created
 * @param old_age_commitment_json array of EDDSA public keys in JSON, used for age restriction, maybe NULL
 * @param coin_evs envelopes of gamma-selected coins to be signed
 * @return MHD result code
 */
static MHD_RESULT
handle_refreshes_reveal_json (struct MHD_Connection *connection,
                              struct RevealContext *rctx,
                              const json_t *tp_json,
                              const json_t *link_sigs_json,
                              const json_t *new_denoms_h_json,
                              const json_t *old_age_commitment_json,
                              const json_t *coin_evs)
{
  unsigned int num_fresh_coins = json_array_size (new_denoms_h_json);
  unsigned int num_tprivs = json_array_size (tp_json);

  GNUNET_assert (num_tprivs == TALER_CNC_KAPPA - 1); /* checked just earlier */
  if ( (num_fresh_coins >= TALER_MAX_FRESH_COINS) ||
       (0 == num_fresh_coins) )
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_GENERIC_NEW_DENOMS_ARRAY_SIZE_EXCESSIVE,
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

  /* Sanity check of age commitment: If it was provided, it _must_ be an array
   * of the size the # of age groups */
  if (NULL != old_age_commitment_json
      && TEH_age_restriction_config.num_groups !=
      json_array_size (old_age_commitment_json))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_REFRESHES_REVEAL_AGE_RESTRICTION_COMMITMENT_INVALID,
                                       "old_age_commitment");
  }

  /* Parse transfer private keys array */
  for (unsigned int i = 0; i<num_tprivs; i++)
  {
    struct GNUNET_JSON_Specification trans_spec[] = {
      GNUNET_JSON_spec_fixed_auto (NULL,
                                   &rctx->transfer_privs[i]),
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
                                                 old_age_commitment_json,
                                                 coin_evs);
}


MHD_RESULT
TEH_handler_reveal (struct TEH_RequestContext *rc,
                    const json_t *root,
                    const char *const args[2])
{
  const json_t *coin_evs;
  const json_t *transfer_privs;
  const json_t *link_sigs;
  const json_t *new_denoms_h;
  const json_t *old_age_commitment;
  struct RevealContext rctx;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_fixed_auto ("transfer_pub",
                                 &rctx.gamma_tp),
    GNUNET_JSON_spec_array_const ("transfer_privs",
                                  &transfer_privs),
    GNUNET_JSON_spec_array_const ("link_sigs",
                                  &link_sigs),
    GNUNET_JSON_spec_array_const ("coin_evs",
                                  &coin_evs),
    GNUNET_JSON_spec_array_const ("new_denoms_h",
                                  &new_denoms_h),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_array_const ("old_age_commitment",
                                    &old_age_commitment),
      NULL),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("rms",
                                   &rctx.rms),
      &rctx.no_rms),
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
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_REFRESHES_REVEAL_CNC_TRANSFER_ARRAY_SIZE_INVALID,
                                       NULL);
  }

  return handle_refreshes_reveal_json (rc->connection,
                                       &rctx,
                                       transfer_privs,
                                       link_sigs,
                                       new_denoms_h,
                                       old_age_commitment,
                                       coin_evs);
}


/* end of taler-exchange-httpd_refreshes_reveal.c */
