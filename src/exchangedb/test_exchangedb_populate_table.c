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
 * @file exchangedb/test_exchangedb_populate_table.c
 * @brief test cases for DB interaction functions
 * @author Joseph Xu
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**o
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
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, ptr, sizeof (*ptr))

/**
 * Initializes @a ptr with zeros.
 */
#define ZR_BLK(ptr) \
  memset (ptr, 0, sizeof (*ptr))


/**
 * Currency we use.  Must match test-exchange-db-*.conf.
 */
#define CURRENCY "EUR"


/**
 * Number of newly minted coins to use in the test.
 */
#define MELT_NEW_COINS 5


/**
 * How big do we make the RSA keys?
 */
#define RSA_KEY_SIZE 1024


/**
 * Database plugin under test.
 */
static struct TALER_EXCHANGEDB_Plugin *plugin;
static struct TALER_DenomFeeSet fees;


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
 * Main function that will be run by the scheduler.
 *
 * @param cls closure with config
 */

static void
run (void *cls)
{
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  const uint32_t num_partitions = 10;
  struct DenomKeyPair *dkp = NULL;
  struct GNUNET_TIME_Timestamp ts;
  struct TALER_EXCHANGEDB_Deposit depos;
  struct GNUNET_TIME_Timestamp ts_deadline;
  struct TALER_Amount value;
  union TALER_DenominationBlindingKeyP bks;
  struct TALER_CoinPubHashP c_hash;
  struct TALER_EXCHANGEDB_CollectableBlindcoin cbc;
  struct TALER_ExchangeWithdrawValues alg_values = {
    .cipher = TALER_DENOMINATION_RSA
    };
  struct TALER_PlanchetMasterSecretP ps;
  struct TALER_ReservePublicKeyP reserve_pub;

  ZR_BLK (&cbc);
  RND_BLK (&reserve_pub);

  memset (&depos,
          0,
          sizeof (depos));

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

  ts = GNUNET_TIME_timestamp_get ();

  dkp = create_denom_key_pair (RSA_KEY_SIZE,
                               ts,
                               &value,
                               &fees);
  GNUNET_assert (NULL != dkp);
  TALER_denom_pub_hash (&dkp->pub,
                        &cbc.denom_pub_hash);
  RND_BLK (&cbc.reserve_sig);
  RND_BLK (&ps);
  TALER_planchet_blinding_secret_create (&ps,
                                         &alg_values,
                                         &bks);

  {
    struct TALER_PlanchetDetail pd;
    struct TALER_CoinSpendPublicKeyP coin_pub;
    struct TALER_AgeCommitmentHash age_hash;
    struct TALER_AgeCommitmentHash *p_ah[2] = {
      NULL,
      &age_hash
    };


    RND_BLK (&age_hash);
    for (size_t i = 0; i < sizeof(p_ah) / sizeof(p_ah[0]); i++)
    {
      fprintf(stdout, "OPEN\n");
      RND_BLK (&coin_pub);
      GNUNET_assert (GNUNET_OK ==
                     TALER_denom_blind (&dkp->pub,
                                        &bks,
                                        p_ah[i],
                                        &coin_pub,
                                        &alg_values,
                                        &c_hash,
                                        &pd.blinded_planchet));
      GNUNET_assert (GNUNET_OK ==
                     TALER_coin_ev_hash (&pd.blinded_planchet,
                                         &cbc.denom_pub_hash,
                                         &cbc.h_coin_envelope));
      if (i != 0)
        TALER_blinded_denom_sig_free (&cbc.sig);
      GNUNET_assert (
        GNUNET_OK ==
        TALER_denom_sign_blinded (
          &cbc.sig,
          &dkp->priv,
          false,
          &pd.blinded_planchet));
      TALER_blinded_planchet_free (&pd.blinded_planchet);
    }
  }

  cbc.reserve_pub = reserve_pub;
  cbc.amount_with_fee = value;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (CURRENCY,
                                        &cbc.withdraw_fee));




  ts_deadline = GNUNET_TIME_timestamp_get ();

  depos.deposit_fee = fees.deposit;

  RND_BLK (&depos.coin.coin_pub);
  TALER_denom_pub_hash (&dkp->pub,
                        &depos.coin.denom_pub_hash);
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_sig_unblind (&depos.coin.denom_sig,
                                          &cbc.sig,
                                          &bks,
                                          &c_hash,
                                          &alg_values,
                                          &dkp->pub));
  {
    uint64_t known_coin_id;
    struct TALER_DenominationHashP dph;
    struct TALER_AgeCommitmentHash agh;

    FAILIF (TALER_EXCHANGEDB_CKS_ADDED !=
            plugin->ensure_coin_known (plugin->cls,
                                       &depos.coin,
                                       &known_coin_id,
                                       &dph,
                                       &agh));
  }
  {
    TALER_denom_sig_free (&depos.coin.denom_sig);
    struct GNUNET_TIME_Timestamp now;
    RND_BLK (&depos.merchant_pub);
    RND_BLK (&depos.csig);
    RND_BLK (&depos.h_contract_terms);
    RND_BLK (&depos.wire_salt);
    depos.amount_with_fee = value;
    depos.refund_deadline = ts_deadline;
    depos.wire_deadline = ts_deadline;
    depos.receiver_wire_account =
      "payto://iban/DE67830654080004822650?receiver-name=Test";
    depos.timestamp = ts;

    now = GNUNET_TIME_timestamp_get ();
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->insert_deposit (plugin->cls,
                                    now,
                                    &depos));
  }

  result = 0;
  drop:
  GNUNET_break (GNUNET_OK ==
  plugin->drop_tables (plugin->cls));
cleanup:
  if (NULL != dkp)
    destroy_denom_key_pair (dkp);
  TALER_denom_sig_free (&depos.coin.denom_sig);
  TALER_blinded_denom_sig_free (&cbc.sig);
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
