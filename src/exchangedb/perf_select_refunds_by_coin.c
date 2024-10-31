/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
 * @file exchangedb/perf_select_refunds_by_coin.c
 * @brief benchmark for select_refunds_by_coin
 * @author Joseph Xu
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
#include "math.h"

/**
 * Global result from the testcase.
 */
static int result;

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
        GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, ptr, \
                                    sizeof (*ptr))

/**
 * Initializes @a ptr with zeros.
 */
#define ZR_BLK(ptr) \
        memset (ptr, 0, sizeof (*ptr))

/**
 * Currency we use.  Must match test-exchange-db-*.conf.
 */
#define CURRENCY "EUR"
#define RSA_KEY_SIZE 1024
#define ROUNDS 100
#define NUM_ROWS 1000
#define MELT_NEW_COINS 5
#define MELT_NOREVEAL_INDEX 1

/**
 * Database plugin under test.
 */
static struct TALER_EXCHANGEDB_Plugin *plugin;


static struct TALER_MerchantWireHashP h_wire_wt;

static struct DenomKeyPair **new_dkp;

static struct TALER_EXCHANGEDB_RefreshRevealedCoin *revealed_coins;

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
                                          GNUNET_CRYPTO_BSA_RSA,
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
 * Callback invoked with information about refunds applicable
 * to a particular coin.
 *
 * @param cls closure with the `struct TALER_EXCHANGEDB_Refund *` we expect to get
 * @param amount_with_fee amount being refunded
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
check_refund_cb (void *cls,
                 const struct TALER_Amount *amount_with_fee)
{
  const struct TALER_EXCHANGEDB_Refund *refund = cls;

  if (0 != TALER_amount_cmp (amount_with_fee,
                             &refund->details.refund_amount))
  {
    GNUNET_break (0);
    result = 66;
  }
  return GNUNET_OK;
}


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure with config
 */

static void
run (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  const uint32_t num_partitions = 10;
  struct GNUNET_TIME_Timestamp ts;
  struct TALER_EXCHANGEDB_CoinDepositInformation *depos = NULL;
  struct GNUNET_TIME_Timestamp deadline;
  struct TALER_Amount value;
  union GNUNET_CRYPTO_BlindingSecretP bks;
  struct TALER_EXCHANGEDB_CollectableBlindcoin cbc;
  struct GNUNET_CRYPTO_BlindingInputValues bi = {
    .cipher = GNUNET_CRYPTO_BSA_RSA,
    .rc = 0
  };
  struct TALER_ExchangeWithdrawValues alg_values = {
    .blinding_inputs = &bi
  };
  struct GNUNET_TIME_Relative times = GNUNET_TIME_UNIT_ZERO;
  unsigned long long sqrs = 0;
  struct TALER_EXCHANGEDB_Refund *ref = NULL;
  unsigned int *perm;
  unsigned long long duration_sq;
  struct TALER_EXCHANGEDB_RefreshRevealedCoin *ccoin;
  struct TALER_DenominationPublicKey *new_denom_pubs = NULL;
  struct TALER_DenomFeeSet fees;
  unsigned int count = 0;

  ref = GNUNET_new_array (ROUNDS + 1,
                          struct TALER_EXCHANGEDB_Refund);
  depos = GNUNET_new_array (ROUNDS + 1,
                            struct TALER_EXCHANGEDB_CoinDepositInformation);
  ZR_BLK (&cbc);

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
  GNUNET_assert (NUM_ROWS >= ROUNDS);

  ts = GNUNET_TIME_timestamp_get ();
  deadline = GNUNET_TIME_timestamp_get ();
  {
    new_dkp = GNUNET_new_array (MELT_NEW_COINS,
                                struct DenomKeyPair *);
    new_denom_pubs = GNUNET_new_array (MELT_NEW_COINS,
                                       struct TALER_DenominationPublicKey);
    revealed_coins
      = GNUNET_new_array (MELT_NEW_COINS,
                          struct TALER_EXCHANGEDB_RefreshRevealedCoin);
    for (unsigned int cnt = 0; cnt < MELT_NEW_COINS; cnt++)
    {
      struct GNUNET_TIME_Timestamp now;
      struct GNUNET_CRYPTO_RsaBlindedMessage *rp;
      struct TALER_BlindedPlanchet *bp;

      now = GNUNET_TIME_timestamp_get ();
      new_dkp[cnt] = create_denom_key_pair (RSA_KEY_SIZE,
                                            now,
                                            &value,
                                            &fees);
      GNUNET_assert (NULL != new_dkp[cnt]);
      new_denom_pubs[cnt] = new_dkp[cnt]->pub;
      ccoin = &revealed_coins[cnt];
      bp = &ccoin->blinded_planchet;
      bp->blinded_message = GNUNET_new (struct GNUNET_CRYPTO_BlindedMessage);
      bp->blinded_message->rc = 1;
      bp->blinded_message->cipher = GNUNET_CRYPTO_BSA_RSA;
      rp = &bp->blinded_message->details.rsa_blinded_message;
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
      TALER_coin_ev_hash (bp,
                          &cbc.denom_pub_hash,
                          &cbc.h_coin_envelope);
      GNUNET_assert (
        GNUNET_OK ==
        TALER_denom_sign_blinded (
          &cbc.sig,
          &new_dkp[cnt]->priv,
          false,
          bp));
    }
  }

  perm = GNUNET_CRYPTO_random_permute (GNUNET_CRYPTO_QUALITY_NONCE,
                                       NUM_ROWS);
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         "Transaction"));
  for (unsigned int j = 0; j< NUM_ROWS; j++)
  {
    unsigned int i = perm[j];
    unsigned int k = (unsigned int) rand () % 5;
    struct TALER_CoinPubHashP c_hash;
    uint64_t known_coin_id;
    struct TALER_EXCHANGEDB_CoinDepositInformation *cdi
      = &depos[i];
    struct TALER_EXCHANGEDB_BatchDeposit bd = {
      .cdis = cdi,
      .num_cdis = 1,
      .wallet_timestamp = ts,
      .refund_deadline = deadline,
      .wire_deadline = deadline,
      .receiver_wire_account.full_payto
        = (char *) "payto://iban/DE67830654080004822650?receiver-name=Test"
    };

    if (i >= ROUNDS)
      i = ROUNDS; /* throw-away slot, do not keep around */
    RND_BLK (&bd.merchant_pub);
    RND_BLK (&bd.h_contract_terms);
    RND_BLK (&bd.wire_salt);
    TALER_merchant_wire_signature_hash (
      bd.receiver_wire_account,
      &bd.wire_salt,
      &h_wire_wt);
    RND_BLK (&cdi->coin.coin_pub);
    RND_BLK (&cdi->csig);
    RND_BLK (&c_hash);
    TALER_denom_pub_hash (&new_dkp[k]->pub,
                          &cdi->coin.denom_pub_hash);
    GNUNET_assert (GNUNET_OK ==
                   TALER_denom_sig_unblind (&cdi->coin.denom_sig,
                                            &cbc.sig,
                                            &bks,
                                            &c_hash,
                                            &alg_values,
                                            &new_dkp[k]->pub));
    cdi->amount_with_fee = value;

    {
      struct TALER_DenominationHashP dph;
      struct TALER_AgeCommitmentHash agh;

      FAILIF (TALER_EXCHANGEDB_CKS_ADDED !=
              plugin->ensure_coin_known (plugin->cls,
                                         &cdi->coin,
                                         &known_coin_id,
                                         &dph,
                                         &agh));
    }
    {
      struct GNUNET_TIME_Timestamp now;
      bool balance_ok;
      uint32_t bad_idx;
      bool in_conflict;

      now = GNUNET_TIME_timestamp_get ();
      FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
              plugin->do_deposit (plugin->cls,
                                  &bd,
                                  &now,
                                  &balance_ok,
                                  &bad_idx,
                                  &in_conflict));
    }
    {
      bool not_found;
      bool refund_ok;
      bool gone;
      bool conflict;
      unsigned int refund_percent = 0;
      switch (refund_percent)
      {
      case 2: // 100% refund
        ref[i].coin = depos[i].coin;
        ref[i].details.merchant_pub = bd.merchant_pub;
        RND_BLK (&ref[i].details.merchant_sig);
        ref[i].details.h_contract_terms = bd.h_contract_terms;
        ref[i].coin.coin_pub = depos[i].coin.coin_pub;
        ref[i].details.rtransaction_id = i;
        ref[i].details.refund_amount = value;
        ref[i].details.refund_fee = fees.refund;
        FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
                plugin->do_refund (plugin->cls,
                                   &ref[i],
                                   &fees.deposit,
                                   known_coin_id,
                                   &not_found,
                                   &refund_ok,
                                   &gone,
                                   &conflict));
        break;
      case 1:// 10% refund
        if (count < (NUM_ROWS / 10))
        {
          ref[i].coin = depos[i].coin;
          ref[i].details.merchant_pub = bd.merchant_pub;
          RND_BLK (&ref[i].details.merchant_sig);
          ref[i].details.h_contract_terms = bd.h_contract_terms;
          ref[i].coin.coin_pub = depos[i].coin.coin_pub;
          ref[i].details.rtransaction_id = i;
          ref[i].details.refund_amount = value;
          ref[i].details.refund_fee = fees.refund;
        }
        else
        {
          ref[i].coin = depos[i].coin;
          RND_BLK (&ref[i].details.merchant_pub);
          RND_BLK (&ref[i].details.merchant_sig);
          RND_BLK (&ref[i].details.h_contract_terms);
          RND_BLK (&ref[i].coin.coin_pub);
          ref[i].details.rtransaction_id = i;
          ref[i].details.refund_amount = value;
          ref[i].details.refund_fee = fees.refund;
        }
        FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
                plugin->do_refund (plugin->cls,
                                   &ref[i],
                                   &fees.deposit,
                                   known_coin_id,
                                   &not_found,
                                   &refund_ok,
                                   &gone,
                                   &conflict));
        count++;
        break;
      case 0:// no refund
        ref[i].coin = depos[i].coin;
        RND_BLK (&ref[i].details.merchant_pub);
        RND_BLK (&ref[i].details.merchant_sig);
        RND_BLK (&ref[i].details.h_contract_terms);
        RND_BLK (&ref[i].coin.coin_pub);
        ref[i].details.rtransaction_id = i;
        ref[i].details.refund_amount = value;
        ref[i].details.refund_fee = fees.refund;
        FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
                plugin->do_refund (plugin->cls,
                                   &ref[i],
                                   &fees.deposit,
                                   known_coin_id,
                                   &not_found,
                                   &refund_ok,
                                   &gone,
                                   &conflict));
        break;
      }/* END OF SWITCH CASE */
    }
    if (ROUNDS == i)
      TALER_denom_sig_free (&depos[i].coin.denom_sig);
  }
  /* End of benchmark setup */
  GNUNET_free (perm);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls));
  for (unsigned int r = 0; r < ROUNDS; r++)
  {
    struct GNUNET_TIME_Absolute time;
    struct GNUNET_TIME_Relative duration;

    time = GNUNET_TIME_absolute_get ();
    FAILIF (0 >
            plugin->select_refunds_by_coin (plugin->cls,
                                            &ref[r].coin.coin_pub,
                                            &ref[r].details.merchant_pub,
                                            &ref[r].details.h_contract_terms,
                                            &check_refund_cb,
                                            &ref[r]));
    duration = GNUNET_TIME_absolute_get_duration (time);
    times = GNUNET_TIME_relative_add (times,
                                      duration);
    duration_sq = duration.rel_value_us * duration.rel_value_us;
    GNUNET_assert (duration_sq / duration.rel_value_us ==
                   duration.rel_value_us);
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
    fprintf (stdout,
             "%8llu ± %6.0f\n",
             (unsigned long long) avg.rel_value_us,
             sqrt (variance / (ROUNDS - 1)));
  }
  result = 0;
drop:
  GNUNET_break (GNUNET_OK ==
                plugin->drop_tables (plugin->cls));
cleanup:
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
  for (unsigned int i = 0; i< ROUNDS + 1; i++)
  {
    TALER_denom_sig_free (&depos[i].coin.denom_sig);
  }
  GNUNET_free (depos);
  GNUNET_free (ref);
  TALER_EXCHANGEDB_plugin_unload (plugin);
  plugin = NULL;
}


int
main (int argc,
      char *const argv[])
{
  const char *plugin_name;
  char *config_filename;
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
  {
    char *testname;

    GNUNET_asprintf (&testname,
                     "test-exchange-db-%s",
                     plugin_name);
    GNUNET_asprintf (&config_filename,
                     "%s.conf",
                     testname);
    GNUNET_free (testname);
  }
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_parse (cfg,
                                  config_filename))
  {
    GNUNET_break (0);
    GNUNET_free (config_filename);
    return 2;
  }
  GNUNET_SCHEDULER_run (&run,
                        cfg);
  GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free (config_filename);
  return result;
}


/* end of perf_select_refunds_by_coin.c */
