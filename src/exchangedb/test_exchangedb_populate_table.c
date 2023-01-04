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
#define i 0
#define NUMBER_DEPOSIT 10
/**
 * How big do we make the RSA keys?
 */
#define RSA_KEY_SIZE 1024


/**
 * Database plugin under test.
 */
static struct TALER_EXCHANGEDB_Plugin *plugin;
static struct TALER_DenomFeeSet fees;
static struct TALER_MerchantWireHashP h_wire_wt;

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
 * Here we store the hash of the payto URI.
 */
static struct TALER_PaytoHashP wire_target_h_payto;
/**
 * Counter used in auditor-related db functions. Used to count
 * expected rows.
 */
static unsigned int auditor_row_cnt;
/**
 * Callback for #select_deposits_above_serial_id ()
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param exchange_timestamp when did the deposit happen
 * @param deposit deposit details
 * @param denom_pub denomination of the @a coin_pub
 * @param done flag set if the deposit was already executed (or not)
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
audit_deposit_cb (void *cls,
                  uint64_t rowid,
                  struct GNUNET_TIME_Timestamp exchange_timestamp,
                  const struct TALER_EXCHANGEDB_Deposit *deposit,
                  const struct TALER_DenominationPublicKey *denom_pub,
                  bool done)
{
  (void) cls;
  (void) rowid;
  (void) exchange_timestamp;
  (void) deposit;
  (void) denom_pub;
  (void) done;
  auditor_row_cnt++;
  return GNUNET_OK;
}
/**
 * Function called on deposits that are past their due date
 * and have not yet seen a wire transfer.
 *
 * @param cls closure a `struct TALER_EXCHANGEDB_Deposit *`
 * @param rowid deposit table row of the coin's deposit
 * @param coin_pub public key of the coin
 * @param amount value of the deposit, including fee
 * @param payto_uri where should the funds be wired
 * @param deadline what was the requested wire transfer deadline
 * @param done did the exchange claim that it made a transfer?
 */
static void
wire_missing_cb (void *cls,
                 uint64_t rowid,
                 const struct TALER_CoinSpendPublicKeyP *coin_pub,
                 const struct TALER_Amount *amount,
                 const char *payto_uri,
                 struct GNUNET_TIME_Timestamp deadline,
                 bool done)
{
  const struct TALER_EXCHANGEDB_Deposit *deposit = cls;

  (void) payto_uri;
  (void) deadline;
  (void) rowid;
  if (done)
  {
    GNUNET_break (0);
    result = 66;
  }
  if (0 != TALER_amount_cmp (amount,
                             &deposit->amount_with_fee))
  {
    GNUNET_break (0);
    result = 66;
  }
  if (0 != GNUNET_memcmp (coin_pub,
                          &deposit->coin.coin_pub))
  {
    GNUNET_break (0);
    result = 66;
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
  struct GNUNET_CONFIGURATION_Handle *cfg = cls;
  const uint32_t num_partitions = 10;
  struct DenomKeyPair *dkp = NULL;
  struct GNUNET_TIME_Timestamp ts;
  struct TALER_EXCHANGEDB_Deposit depos[NUMBER_DEPOSIT];
  struct GNUNET_TIME_Timestamp deadline;
  struct TALER_Amount value;
  union TALER_DenominationBlindingKeyP bks;
  struct TALER_CoinPubHashP c_hash;
  struct TALER_EXCHANGEDB_CollectableBlindcoin cbc;
  struct TALER_EXCHANGEDB_CollectableBlindcoin cbc2;
  struct TALER_ExchangeWithdrawValues alg_values = {
    .cipher = TALER_DENOMINATION_RSA
    };
  struct TALER_PlanchetMasterSecretP ps;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct TALER_EXCHANGEDB_Refund ref;

  ZR_BLK (&cbc);
  ZR_BLK (&cbc2);
  RND_BLK (&reserve_pub);

  memset (&ref,
          0,
          sizeof (ref));

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
  deadline = GNUNET_TIME_timestamp_get ();
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


  cbc.reserve_pub = reserve_pub;
  cbc.amount_with_fee = value;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (CURRENCY,
                                        &cbc.withdraw_fee));
  /* for (unsigned int i=0; i< NUMBER_DEPOSIT; i++)
     {*/
            fprintf(stdout, "%d\n", i);
      struct TALER_CoinSpendPublicKeyP coin_pub;
      RND_BLK (&coin_pub);
      {
        struct TALER_PlanchetDetail pd;

        struct TALER_AgeCommitmentHash age_hash;
        struct TALER_AgeCommitmentHash *p_ah[2] = {
          NULL,
          &age_hash
        };

        RND_BLK (&age_hash);

        for (size_t k = 0; k < sizeof(p_ah) / sizeof(p_ah[0]); k++)
          {
            fprintf(stdout, "OPEN\n");

            GNUNET_assert (GNUNET_OK ==
                           TALER_denom_blind (&dkp->pub,
                                              &bks,
                                              p_ah[k],
                                              &coin_pub,
                                              &alg_values,
                                              &c_hash,
                                              &pd.blinded_planchet));
            GNUNET_assert (GNUNET_OK ==
                           TALER_coin_ev_hash (&pd.blinded_planchet,
                                               &cbc.denom_pub_hash,
                                               &cbc.h_coin_envelope));
            if (k != 0)
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


      depos[i].deposit_fee = fees.deposit;

      RND_BLK (&depos[i].coin.coin_pub);

      TALER_denom_pub_hash (&dkp->pub,
                            &depos[i].coin.denom_pub_hash);
      // TALER_denom_pub_hash (&dkp->pub,
      //                    &ref.coin.denom_pub_hash);
      GNUNET_assert (GNUNET_OK ==
                     TALER_denom_sig_unblind (&depos[i].coin.denom_sig,
                                              &cbc.sig,
                                              &bks,
                                              &c_hash,
                                              &alg_values,
                                              &dkp->pub));

      RND_BLK (&depos[i].merchant_pub);
      RND_BLK (&depos[i].csig);
      RND_BLK (&depos[i].h_contract_terms);
      RND_BLK (&depos[i].wire_salt);
      depos[i].amount_with_fee = value;
      depos[i].refund_deadline = deadline;
      depos[i].wire_deadline = deadline;
      depos[i].receiver_wire_account =
        "payto://iban/DE67830654080004822650?receiver-name=Test";
      TALER_merchant_wire_signature_hash (
                                          "payto://iban/DE67830654080004822650?receiver-name=Test",
                                          &depos[i].wire_salt,
                                          &h_wire_wt);
      depos[i].timestamp = ts;
      result = 8;
      {
        uint64_t known_coin_id;
        struct TALER_DenominationHashP dph;
        struct TALER_AgeCommitmentHash agh;
        FAILIF (TALER_EXCHANGEDB_CKS_ADDED !=
                plugin->ensure_coin_known (plugin->cls,
                                           &depos[i].coin,
                                           &known_coin_id,
                                           &dph,
                                           &agh));
      }

      /*wire + deposit for get_ready_deposit*/

      /*STORE INTO DEPOSIT*/
      {
        struct GNUNET_TIME_Timestamp now;
        struct GNUNET_TIME_Timestamp r;
        struct TALER_Amount deposit_fee;
        struct TALER_MerchantWireHashP h_wire;

        now = GNUNET_TIME_timestamp_get ();
        FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
                plugin->insert_deposit (plugin->cls,
                                        now,
                                        &depos[i]));
        TALER_merchant_wire_signature_hash (depos[i].receiver_wire_account,
                                            &depos[i].wire_salt,
                                            &h_wire);
        FAILIF (1 !=
                plugin->have_deposit2 (plugin->cls,
                                       &depos[i].h_contract_terms,
                                       &h_wire,
                                       &depos[i].coin.coin_pub,
                                       &depos[i].merchant_pub,
                                       depos[i].refund_deadline,
                                       &deposit_fee,
                                       &r));
        FAILIF (GNUNET_TIME_timestamp_cmp (now,
                                           !=,
                                           r));
      }
      {
        struct GNUNET_TIME_Timestamp start_range;
        struct GNUNET_TIME_Timestamp end_range;

        start_range = GNUNET_TIME_absolute_to_timestamp (
                                                         GNUNET_TIME_absolute_subtract (deadline.abs_time,
                                                                                        GNUNET_TIME_UNIT_SECONDS));
        end_range = GNUNET_TIME_absolute_to_timestamp (
                                                       GNUNET_TIME_absolute_add (deadline.abs_time,
                                                                                 GNUNET_TIME_UNIT_SECONDS));
        /*Aborted*/
        FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
                plugin->select_deposits_missing_wire (plugin->cls,
                                                      start_range,
                                                      end_range,
                                                      &wire_missing_cb,
                                                      &depos[i]));

          FAILIF (8 != result);
      }
      auditor_row_cnt = 0;
      FAILIF (0 >=
              plugin->select_deposits_above_serial_id (plugin->cls,
                                                       0,
                                                       &audit_deposit_cb,
                                                       NULL));
      FAILIF (0 == auditor_row_cnt);
      result = 8;
      sleep (2);
      /*CREATE DEPOSIT*/
      {
        struct TALER_MerchantPublicKeyP merchant_pub2;
        char *payto_uri2;

        FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
                plugin->get_ready_deposit (plugin->cls,
                                           0,
                                           INT32_MAX,
                                           &merchant_pub2,
                                           &payto_uri2));
        FAILIF (0 != GNUNET_memcmp (&merchant_pub2,
                                    &depos[i].merchant_pub));
        FAILIF (0 != strcmp (payto_uri2,
                             depos[i].receiver_wire_account));
        TALER_payto_hash (payto_uri2,
                          &wire_target_h_payto);
        GNUNET_free (payto_uri2);
        //  }
      /* {
    RND_BLK (&ref.details.merchant_pub);
    RND_BLK(&ref.details.merchant_sig);
    ref.details.h_contract_terms = depos.h_contract_terms;
    ref.coin.coin_pub = depos.coin.coin_pub;
    ref.details.rtransaction_id = 1;
    ref.details.refund_amount = value;
    ref.details.refund_fee = fees.refund;
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->insert_refund (plugin->cls,
                                   &ref));
                                   }*/
    }

  result = 0;
drop:
  GNUNET_break (GNUNET_OK ==
  plugin->drop_tables (plugin->cls));
cleanup:
  if (NULL != dkp)
    destroy_denom_key_pair (dkp);
  //  for (unsigned int i=0; i<NUMBER_DEPOSIT; i++){
  TALER_denom_sig_free (&depos[i].coin.denom_sig);//}

  TALER_denom_sig_free (&ref.coin.denom_sig);
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
