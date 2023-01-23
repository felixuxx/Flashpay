/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file exchangedb/test_exchangedb_populate_link_data.c
 * @brief test cases for DB interaction functions
 * @author Joseph Xu
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
#include "math.h"

/**
 * Report line of error if @a cond is true, and jump to label "drop".
 */
#define FAILIF(cond)                            \
  do {                                          \
      if (! (cond)) {break;}                    \
    GNUNET_break (0);                           \
    goto drop;                                  \
  } while (0)


/**
 * Initializes @a ptr with random data.
 */
#define RND_BLK(ptr)                                                    \
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, ptr, sizeof (*ptr))

/**
 * Initializes @a ptr with zeros.
 */
#define ZR_BLK(ptr) \
  memset (ptr, 0, sizeof (*ptr))

#define CURRENCY "EUR"
#define RSA_KEY_SIZE 1024
#define ROUNDS 10
#define NUM_ROWS 1000
#define MELT_NEW_COINS 5
#define MELT_NOREVEAL_INDEX 1
/**
 * Database plugin under test.
 */
static struct TALER_EXCHANGEDB_Plugin *plugin;
static struct TALER_DenomFeeSet fees;
/**
 * Denomination keys used for fresh coins in melt test.
 */
static struct DenomKeyPair **new_dkp;
static int result;
static struct TALER_EXCHANGEDB_RefreshRevealedCoin *revealed_coins;
static struct TALER_TransferPrivateKeyP tprivs[TALER_CNC_KAPPA];
static struct TALER_TransferPublicKeyP tpub;
struct DenomKeyPair
{
  struct TALER_DenominationPrivateKey priv;
  struct TALER_DenominationPublicKey pub;
};


/**
 * Destroy a denomination key pair.  The key is not necessarily removed from the DB.
 *
 * @param dkp the key pair to destroy
 */
static void
destroy_denom_key_pair (struct DenomKeyPair *dkp)
{
  TALER_denom_pub_free (&dkp->pub);
  TALER_denom_priv_free (&dkp->priv);
  GNUNET_free (dkp);
}


/**
 * Create a denomination key pair by registering the denomination in the DB.
 *
 * @param size the size of the denomination key
 * @param now time to use for key generation, legal expiration will be 3h later.
 * @param fees fees to use
 * @return the denominaiton key pair; NULL upon error
 */
static struct DenomKeyPair *
create_denom_key_pair (unsigned int size,
                       struct GNUNET_TIME_Timestamp now,
                       const struct TALER_Amount *value,
                       const struct TALER_DenomFeeSet *fees)
{
  struct DenomKeyPair *dkp;
  struct TALER_EXCHANGEDB_DenominationKey dki;
  struct TALER_EXCHANGEDB_DenominationKeyInformation issue2;

  dkp = GNUNET_new (struct DenomKeyPair);
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_priv_create (&dkp->priv,
                                          &dkp->pub,
                                          TALER_DENOMINATION_RSA,
                                          size));
  memset (&dki,
          0,
          sizeof (struct TALER_EXCHANGEDB_DenominationKey));
  dki.denom_pub = dkp->pub;
  dki.issue.start = now;
  dki.issue.expire_withdraw
    = GNUNET_TIME_absolute_to_timestamp (
        GNUNET_TIME_absolute_add (
          now.abs_time,
          GNUNET_TIME_UNIT_HOURS));
  dki.issue.expire_deposit
    = GNUNET_TIME_absolute_to_timestamp (
        GNUNET_TIME_absolute_add (
          now.abs_time,
          GNUNET_TIME_relative_multiply (
            GNUNET_TIME_UNIT_HOURS, 2)));
  dki.issue.expire_legal
    = GNUNET_TIME_absolute_to_timestamp (
        GNUNET_TIME_absolute_add (
          now.abs_time,
          GNUNET_TIME_relative_multiply (
            GNUNET_TIME_UNIT_HOURS, 3)));
  dki.issue.value = *value;
  dki.issue.fees = *fees;
  TALER_denom_pub_hash (&dkp->pub,
                        &dki.issue.denom_hash);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      plugin->insert_denomination_info (plugin->cls,
                                        &dki.denom_pub,
                                        &dki.issue))
  {
    GNUNET_break (0);
    destroy_denom_key_pair (dkp);
    return NULL;
  }
  memset (&issue2, 0, sizeof (issue2));
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      plugin->get_denomination_info (plugin->cls,
                                     &dki.issue.denom_hash,
                                     &issue2))
  {
    GNUNET_break (0);
    destroy_denom_key_pair (dkp);
    return NULL;
  }
  if (0 != GNUNET_memcmp (&dki.issue,
                          &issue2))
  {
    GNUNET_break (0);
    destroy_denom_key_pair (dkp);
    return NULL;
  }
  return dkp;
}

/**
 * Function called with the session hashes and transfer secret
 * information for a given coin.
 *
 * @param cls closure
 * @param transfer_pub public transfer key for the session
 * @param ldl link data for @a transfer_pub
 */
static void
handle_link_data_cb (void *cls,
                     const struct TALER_TransferPublicKeyP *transfer_pub,
                     const struct TALER_EXCHANGEDB_LinkList *ldl)
{
  (void) cls;
  (void) transfer_pub;
  for (const struct TALER_EXCHANGEDB_LinkList *ldlp = ldl;
       NULL != ldlp;
       ldlp = ldlp->next)
  {
    bool found;

    found = false;
    for (unsigned int cnt = 0; cnt < MELT_NEW_COINS; cnt++)
    {
      if ( (0 ==
            TALER_denom_pub_cmp (&ldlp->denom_pub,
                                 &new_dkp[cnt]->pub)) &&
           (0 ==
            TALER_blinded_denom_sig_cmp (&ldlp->ev_sig,
                                         &revealed_coins[cnt].coin_sig)) )
      {
        found = true;
        break;
      }
    }
    GNUNET_assert (GNUNET_NO != found);
  }
}

/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure with config
 */

static void
run (void *cls)
{
  struct TALER_EXCHANGEDB_Refresh *refresh;
  uint64_t melt_serial_id;
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  const uint32_t num_partitions = 10;
  struct DenomKeyPair *dkp = NULL;
  struct TALER_EXCHANGEDB_Deposit *depos=NULL;
  struct TALER_Amount value;
  struct TALER_DenominationPublicKey *new_denom_pubs = NULL;
  struct GNUNET_TIME_Relative times = GNUNET_TIME_UNIT_ZERO;
  unsigned long long sqrs=0;
  struct TALER_EXCHANGEDB_Refund *ref=NULL;
  unsigned int *perm;
  unsigned long long duration_sq;
  struct TALER_EXCHANGEDB_RefreshRevealedCoin *ccoin;
  struct TALER_ExchangeWithdrawValues alg_values = {
    .cipher = TALER_DENOMINATION_RSA
    };

  ref = GNUNET_new_array (ROUNDS +1,
                          struct TALER_EXCHANGEDB_Refund);
  depos = GNUNET_new_array (ROUNDS +1,
                            struct TALER_EXCHANGEDB_Deposit);
  refresh = GNUNET_new_array (ROUNDS +1,
                            struct TALER_EXCHANGEDB_Refresh);

  if (NULL ==
      (plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    GNUNET_break (0);
    result = 77;
    return;
  }
  (void) plugin->drop_tables (plugin->cls);
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls,
                             true,
                             num_partitions))
  {
    GNUNET_break (0);
    result = 77;
    goto cleanup;
  }
  if (GNUNET_OK !=
      plugin->preflight (plugin->cls))
  {
    GNUNET_break (0);
    goto cleanup;
  }

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.000010",
                                         &value));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fees.withdraw));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fees.deposit));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fees.refresh));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fees.refund));
  //DENOMINATION
  {
    //PAIR KEY LIST
    new_dkp = GNUNET_new_array (MELT_NEW_COINS,
                              struct DenomKeyPair *);
    //PUBLIC KEY LIST
    new_denom_pubs = GNUNET_new_array (MELT_NEW_COINS,
                                       struct TALER_DenominationPublicKey);
    //REFRESH REVEAL COIN LIST
    revealed_coins
      = GNUNET_new_array (MELT_NEW_COINS,
                          struct TALER_EXCHANGEDB_RefreshRevealedCoin);
    for (unsigned int cnt = 0; cnt < MELT_NEW_COINS; cnt++)
      {
        struct GNUNET_TIME_Timestamp now;
        struct TALER_BlindedRsaPlanchet *rp;
        struct TALER_BlindedPlanchet *bp;

        now = GNUNET_TIME_timestamp_get ();
        //5 KEY PAIR
        new_dkp[cnt] = create_denom_key_pair (RSA_KEY_SIZE,
                                              now,
                                              &value,
                                              &fees);
        GNUNET_assert (NULL != new_dkp[cnt]);
        new_denom_pubs[cnt] = new_dkp[cnt]->pub;
        ccoin = &revealed_coins[cnt];
        bp = &ccoin->blinded_planchet;
        bp->cipher = TALER_DENOMINATION_RSA;
        rp = &bp->details.rsa_blinded_planchet;
        rp->blinded_msg_size = 1 + (size_t) GNUNET_CRYPTO_random_u64 (
                                                                      GNUNET_CRYPTO_QUALITY_WEAK,
                                                                      (RSA_KEY_SIZE / 8) - 1);
        rp->blinded_msg = GNUNET_malloc (rp->blinded_msg_size);
        GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                    rp->blinded_msg,
                                    rp->blinded_msg_size);
        TALER_denom_pub_hash (&new_dkp[cnt]->pub,
                              &ccoin->h_denom_pub);
        ccoin->exchange_vals = alg_values;
        TALER_coin_ev_hash (bp,
                            &ccoin->h_denom_pub,
                            &ccoin->coin_envelope_hash);
        GNUNET_assert (GNUNET_OK ==
                     TALER_denom_sign_blinded (&ccoin->coin_sig,
                                               &new_dkp[cnt]->priv,
                                               true,
                                               bp));
      }
  }
  perm = GNUNET_CRYPTO_random_permute (GNUNET_CRYPTO_QUALITY_NONCE,
                                       NUM_ROWS);
  //BEGIN
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         "Transaction"));
  for (unsigned int j = 0; j < NUM_ROWS; j++)
    {
      union TALER_DenominationBlindingKeyP bks;
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct TALER_CoinPubHashP c_hash;
      unsigned int k = (unsigned int)rand()%5;
      unsigned int i = perm[j];
      if (i >= ROUNDS)
        i = ROUNDS; /* throw-away slot, do not keep around */
      RND_BLK (&coin_pub);
      RND_BLK (&c_hash);

      RND_BLK (&depos[i].coin.coin_pub);
      TALER_denom_pub_hash (&new_dkp[k]->pub,
                            &depos[i].coin.denom_pub_hash);
      GNUNET_assert (GNUNET_OK ==
                     TALER_denom_sig_unblind (&depos[i].coin.denom_sig,
                                              &ccoin->coin_sig,
                                              &bks,
                                              &c_hash,
                                              &alg_values,
                                              &new_dkp[k]->pub));
      {
        /* ENSURE_COIN_KNOWN */
        uint64_t known_coin_id;
        struct TALER_DenominationHashP dph;
        struct TALER_AgeCommitmentHash agh;
        bool zombie_required = false;
        bool balance_ok;
        FAILIF (TALER_EXCHANGEDB_CKS_ADDED !=
                plugin->ensure_coin_known (plugin->cls,
                                           &depos[i].coin,
                                           &known_coin_id,
                                           &dph,
                                           &agh));
        /**** INSERT REFRESH COMMITMENTS ****/
        refresh[i].coin = depos[i].coin;
        RND_BLK (&refresh[i].coin_sig);
        RND_BLK (&refresh[i].rc);
        refresh[i].amount_with_fee = value;
        refresh[i].noreveal_index = MELT_NOREVEAL_INDEX;
        FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
                plugin->do_melt (plugin->cls,
                                 NULL,
                                 &refresh[i],
                                 known_coin_id,
                                 &zombie_required,
                                 &balance_ok));
        FAILIF (! balance_ok);
        FAILIF (zombie_required);
      }
      /**** INSERT REFRESH_REVEAL + TRANSFER_KEYS *****/
        RND_BLK (&tprivs);
        RND_BLK (&tpub);
        RND_BLK(&melt_serial_id);
        FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
                plugin->insert_refresh_reveal (plugin->cls,
                                               melt_serial_id,
                                               MELT_NEW_COINS,
                                               revealed_coins,
                                               TALER_CNC_KAPPA - 1,
                                               tprivs,
                                               &tpub));
        if (ROUNDS == i)
          TALER_denom_sig_free (&depos[i].coin.denom_sig);
    }
  /* End of benchmark setup */
  GNUNET_free(perm);
  // commit
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls));
  /**** CALL GET LINK DATA ****/
  for (unsigned int r=0; r< ROUNDS; r++)
  {
    struct GNUNET_TIME_Absolute time;
    struct GNUNET_TIME_Relative duration;
    enum GNUNET_DB_QueryStatus qs;
    time = GNUNET_TIME_absolute_get();
    qs = plugin->get_link_data (plugin->cls,
                                &refresh[r].coin.coin_pub,
                                &handle_link_data_cb,
                                NULL);
    FAILIF (qs < 0);

    duration = GNUNET_TIME_absolute_get_duration (time);
    times = GNUNET_TIME_relative_add (times,
                                      duration);
    duration_sq = duration.rel_value_us * duration.rel_value_us;
    GNUNET_assert (duration_sq / duration.rel_value_us == duration.rel_value_us);
    GNUNET_assert (sqrs + duration_sq >= sqrs);
    sqrs += duration_sq;
  }

  /* evaluation of performance */
  {
    struct GNUNET_TIME_Relative avg;
    double avg_dbl;
    double variance;

    avg = GNUNET_TIME_relative_divide (times,
                                       ROUNDS);
    avg_dbl = avg.rel_value_us;
    variance = sqrs - (avg_dbl * avg_dbl * ROUNDS);
    fprintf(stdout,
            "%8llu ± %6.0f\n",
            (unsigned long long) avg.rel_value_us,
            sqrt (variance / (ROUNDS-1)));
  }
  result = 0;
drop:
  GNUNET_break (GNUNET_OK ==
  plugin->drop_tables (plugin->cls));
cleanup:
  if (NULL != dkp)
    destroy_denom_key_pair (dkp);
  if (NULL != revealed_coins)
  {
    for (unsigned int cnt = 0; cnt < MELT_NEW_COINS; cnt++)
    {
      TALER_blinded_denom_sig_free (&revealed_coins[cnt].coin_sig);
      TALER_blinded_planchet_free (&revealed_coins[cnt].blinded_planchet);
    }
    GNUNET_free (revealed_coins);
    revealed_coins = NULL;
  }
  GNUNET_free (new_denom_pubs);
  for (unsigned int cnt = 0;
       (NULL != new_dkp) && (cnt < MELT_NEW_COINS) && (NULL != new_dkp[cnt]);
       cnt++)
    destroy_denom_key_pair (new_dkp[cnt]);
  GNUNET_free (new_dkp);
  for (unsigned int i=0; i< ROUNDS; i++)
    {
      TALER_denom_sig_free (&depos[i].coin.denom_sig);
    }
  GNUNET_free(depos);
  GNUNET_free(ref);
  GNUNET_free(refresh);
  dkp = NULL;
  TALER_EXCHANGEDB_plugin_unload (plugin);
  plugin = NULL;
}


int
main (int argc,
      char *const argv[])
{
  const char *plugin_name;
  char *config_filename;
  char *testname;
  struct GNUNET_CONFIGURATION_Handle *cfg;

  (void) argc;
  result = -1;
  if (NULL == (plugin_name = strrchr (argv[0], (int) '-')))
  {
    GNUNET_break (0);
    return -1;
  }
  GNUNET_log_setup (argv[0],
                    "WARNING",
                    NULL);
  plugin_name++;
  (void) GNUNET_asprintf (&testname,
                          "test-exchange-db-%s",
                          plugin_name);
  (void) GNUNET_asprintf (&config_filename,
                          "%s.conf",
                          testname);
  fprintf (stdout,
           "Using config: %s\n",
           config_filename);
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_parse (cfg,
                                  config_filename))
  {
    GNUNET_break (0);
    GNUNET_free (config_filename);
    GNUNET_free (testname);
    return 2;
  }
  GNUNET_SCHEDULER_run (&run,
                        cfg);
  GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free (config_filename);
  GNUNET_free (testname);
  return result;
}


/* end of test_exchangedb_by_j.c */
