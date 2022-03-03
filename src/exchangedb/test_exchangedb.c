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
 * @file exchangedb/test_exchangedb.c
 * @brief test cases for DB interaction functions
 * @author Sree Harsha Totakura
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Global result from the testcase.
 */
static int result;

/**
 * Report line of error if @a cond is true, and jump to label "drop".
 */
#define FAILIF(cond)                              \
  do {                                          \
    if (! (cond)) { break;}                      \
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
 * Database plugin under test.
 */
static struct TALER_EXCHANGEDB_Plugin *plugin;


/**
 * Callback that should never be called.
 */
static void
dead_prepare_cb (void *cls,
                 uint64_t rowid,
                 const char *wire_method,
                 const char *buf,
                 size_t buf_size)
{
  (void) cls;
  (void) rowid;
  (void) wire_method;
  (void) buf;
  (void) buf_size;
  GNUNET_assert (0);
}


/**
 * Callback that is called with wire prepare data
 * and then marks it as finished.
 */
static void
mark_prepare_cb (void *cls,
                 uint64_t rowid,
                 const char *wire_method,
                 const char *buf,
                 size_t buf_size)
{
  (void) cls;
  GNUNET_assert (11 == buf_size);
  GNUNET_assert (0 == strcasecmp (wire_method,
                                  "testcase"));
  GNUNET_assert (0 == memcmp (buf,
                              "hello world",
                              buf_size));
  GNUNET_break (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
                plugin->wire_prepare_data_mark_finished (plugin->cls,
                                                         rowid));
}


/**
 * Simple check that config retrieval and setting for extensions work
 */
static enum GNUNET_GenericReturnValue
test_extension_config (void)
{
  char *config;

  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->get_extension_config (plugin->cls,
                                        "fnord",
                                        &config));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->set_extension_config (plugin->cls,
                                        "fnord",
                                        "bar"));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_extension_config (plugin->cls,
                                        "fnord",
                                        &config));

  FAILIF (0 != strcmp ("bar", config));

  /* let's do this again! */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->set_extension_config (plugin->cls,
                                        "fnord",
                                        "buzz"));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_extension_config (plugin->cls,
                                        "fnord",
                                        &config));

  FAILIF (0 != strcmp ("buzz", config));

  /* let's do this again, with NULL */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->set_extension_config (plugin->cls,
                                        "fnord",
                                        NULL));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_extension_config (plugin->cls,
                                        "fnord",
                                        &config));

  FAILIF (NULL != config);

  return GNUNET_OK;
drop:
  return GNUNET_SYSERR;
}


/**
 * Test API relating to persisting the wire plugins preparation data.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
test_wire_prepare (void)
{
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->wire_prepare_data_get (plugin->cls,
                                         0,
                                         1,
                                         &dead_prepare_cb,
                                         NULL));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->wire_prepare_data_insert (plugin->cls,
                                            "testcase",
                                            "hello world",
                                            11));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->wire_prepare_data_get (plugin->cls,
                                         0,
                                         1,
                                         &mark_prepare_cb,
                                         NULL));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->wire_prepare_data_get (plugin->cls,
                                         0,
                                         1,
                                         &dead_prepare_cb,
                                         NULL));
  return GNUNET_OK;
drop:
  return GNUNET_SYSERR;
}


/**
 * Checks if the given reserve has the given amount of balance and expiry
 *
 * @param pub the public key of the reserve
 * @param value balance value
 * @param fraction balance fraction
 * @param currency currency of the reserve
 * @return #GNUNET_OK if the given reserve has the same balance and expiration
 *           as the given parameters; #GNUNET_SYSERR if not
 */
static enum GNUNET_GenericReturnValue
check_reserve (const struct TALER_ReservePublicKeyP *pub,
               uint64_t value,
               uint32_t fraction,
               const char *currency)
{
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct TALER_EXCHANGEDB_KycStatus kyc;

  reserve.pub = *pub;
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->reserves_get (plugin->cls,
                                &reserve,
                                &kyc));
  FAILIF (value != reserve.balance.value);
  FAILIF (fraction != reserve.balance.fraction);
  FAILIF (0 != strcmp (currency,
                       reserve.balance.currency));
  FAILIF (kyc.ok);
  return GNUNET_OK;
drop:
  return GNUNET_SYSERR;
}


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
  struct TALER_EXCHANGEDB_DenominationKeyInformationP issue2;

  dkp = GNUNET_new (struct DenomKeyPair);
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_priv_create (&dkp->priv,
                                          &dkp->pub,
                                          TALER_DENOMINATION_RSA,
                                          size));
  /* Using memset() as fields like master key and signature
     are not properly initialized for this test. */
  memset (&dki,
          0,
          sizeof (struct TALER_EXCHANGEDB_DenominationKey));
  dki.denom_pub = dkp->pub;
  dki.issue.properties.start = GNUNET_TIME_timestamp_hton (now);
  dki.issue.properties.expire_withdraw
    = GNUNET_TIME_timestamp_hton
        (GNUNET_TIME_absolute_to_timestamp
          (GNUNET_TIME_absolute_add (
            now.abs_time,
            GNUNET_TIME_UNIT_HOURS)));
  dki.issue.properties.expire_deposit
    = GNUNET_TIME_timestamp_hton (
        GNUNET_TIME_absolute_to_timestamp
          (GNUNET_TIME_absolute_add
            (now.abs_time,
            GNUNET_TIME_relative_multiply (
              GNUNET_TIME_UNIT_HOURS, 2))));
  dki.issue.properties.expire_legal
    = GNUNET_TIME_timestamp_hton (
        GNUNET_TIME_absolute_to_timestamp
          (GNUNET_TIME_absolute_add
            (now.abs_time,
            GNUNET_TIME_relative_multiply (
              GNUNET_TIME_UNIT_HOURS, 3))));
  TALER_amount_hton (&dki.issue.properties.value,
                     value);
  TALER_denom_fee_set_hton (&dki.issue.properties.fees,
                            fees);
  TALER_denom_pub_hash (&dkp->pub,
                        &dki.issue.properties.denom_hash);

  dki.issue.properties.purpose.size
    = htonl (sizeof (struct TALER_DenominationKeyValidityPS));
  dki.issue.properties.purpose.purpose = htonl (
    TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
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
  plugin->commit (plugin->cls);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      plugin->get_denomination_info (plugin->cls,
                                     &dki.issue.properties.denom_hash,
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


static struct TALER_Amount value;
static struct TALER_DenomFeeSet fees;
static struct TALER_Amount fee_closing;
static struct TALER_Amount amount_with_fee;


/**
 * Number of newly minted coins to use in the test.
 */
#define MELT_NEW_COINS 5

/**
 * Which index was 'randomly' chosen for the reveal for the test?
 */
#define MELT_NOREVEAL_INDEX 1

/**
 * How big do we make the RSA keys?
 */
#define RSA_KEY_SIZE 1024

static struct TALER_EXCHANGEDB_RefreshRevealedCoin *revealed_coins;

static struct TALER_TransferPrivateKeyP tprivs[TALER_CNC_KAPPA];

static struct TALER_TransferPublicKeyP tpub;


/**
 * Function called with information about a refresh order.  This
 * one should not be called in a successful test.
 *
 * @param cls closure
 * @param rowid unique serial ID for the row in our database
 * @param num_freshcoins size of the @a rrcs array
 * @param rrcs array of @a num_freshcoins information about coins to be created
 */
static void
never_called_cb (void *cls,
                 uint32_t num_freshcoins,
                 const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs)
{
  (void) cls;
  (void) num_freshcoins;
  (void) rrcs;
  GNUNET_assert (0); /* should never be called! */
}


/**
 * Function called with information about a refresh order.
 * Checks that the response matches what we expect to see.
 *
 * @param cls closure
 * @param rowid unique serial ID for the row in our database
 * @param num_freshcoins size of the @a rrcs array
 * @param rrcs array of @a num_freshcoins information about coins to be created
 */
static void
check_refresh_reveal_cb (
  void *cls,
  uint32_t num_freshcoins,
  const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs)
{
  (void) cls;
  /* compare the refresh commit coin arrays */
  for (unsigned int cnt = 0; cnt < num_freshcoins; cnt++)
  {
    const struct TALER_EXCHANGEDB_RefreshRevealedCoin *acoin =
      &revealed_coins[cnt];
    const struct TALER_EXCHANGEDB_RefreshRevealedCoin *bcoin = &rrcs[cnt];

    GNUNET_assert (0 ==
                   TALER_blinded_planchet_cmp (&acoin->blinded_planchet,
                                               &bcoin->blinded_planchet));
    GNUNET_assert (0 ==
                   GNUNET_memcmp (&acoin->h_denom_pub,
                                  &bcoin->h_denom_pub));
  }
}


/**
 * Counter used in auditor-related db functions. Used to count
 * expected rows.
 */
static unsigned int auditor_row_cnt;


/**
 * Function called with details about coins that were melted,
 * with the goal of auditing the refresh's execution.
 *
 *
 * @param cls closure
 * @param rowid unique serial ID for the refresh session in our DB
 * @param denom_pub denomination of the @a coin_pub
 * @param h_age_commitment hash of age commitment that went into the minting, may be NULL
 * @param coin_pub public key of the coin
 * @param coin_sig signature from the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param num_freshcoins how many coins were issued
 * @param noreveal_index which index was picked by the exchange in cut-and-choose
 * @param rc what is the session hash
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
audit_refresh_session_cb (void *cls,
                          uint64_t rowid,
                          const struct TALER_DenominationPublicKey *denom_pub,
                          const struct
                          TALER_AgeCommitmentHash *h_age_commitment,
                          const struct TALER_CoinSpendPublicKeyP *coin_pub,
                          const struct TALER_CoinSpendSignatureP *coin_sig,
                          const struct TALER_Amount *amount_with_fee,
                          uint32_t noreveal_index,
                          const struct TALER_RefreshCommitmentP *rc)
{
  (void) cls;
  (void) rowid;
  (void) denom_pub;
  (void) coin_pub;
  (void) coin_sig;
  (void) amount_with_fee;
  (void) noreveal_index;
  (void) rc;
  auditor_row_cnt++;
  return GNUNET_OK;
}


/**
 * Denomination keys used for fresh coins in melt test.
 */
static struct DenomKeyPair **new_dkp;


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
 * Callback that should never be called.
 */
static void
cb_wt_never (void *cls,
             uint64_t serial_id,
             const struct TALER_MerchantPublicKeyP *merchant_pub,
             const char *account_payto_uri,
             const struct TALER_PaytoHashP *h_payto,
             struct GNUNET_TIME_Timestamp exec_time,
             const struct TALER_PrivateContractHashP *h_contract_terms,
             const struct TALER_DenominationPublicKey *denom_pub,
             const struct TALER_CoinSpendPublicKeyP *coin_pub,
             const struct TALER_Amount *coin_value,
             const struct TALER_Amount *coin_fee)
{
  (void) cls;
  (void) serial_id;
  (void) merchant_pub;
  (void) account_payto_uri;
  (void) exec_time;
  (void) h_contract_terms;
  (void) denom_pub;
  (void) coin_pub;
  (void) coin_value;
  (void) coin_fee;
  GNUNET_assert (0); /* this statement should be unreachable */
}


static struct TALER_MerchantPublicKeyP merchant_pub_wt;
static struct TALER_MerchantWireHashP h_wire_wt;
static struct TALER_PrivateContractHashP h_contract_terms_wt;
static struct TALER_CoinSpendPublicKeyP coin_pub_wt;
static struct TALER_Amount coin_value_wt;
static struct TALER_Amount coin_fee_wt;
static struct TALER_Amount transfer_value_wt;
static struct GNUNET_TIME_Timestamp wire_out_date;
static struct TALER_WireTransferIdentifierRawP wire_out_wtid;


/**
 * Callback that should be called with the WT data.
 */
static void
cb_wt_check (void *cls,
             uint64_t rowid,
             const struct TALER_MerchantPublicKeyP *merchant_pub,
             const char *account_payto_uri,
             const struct TALER_PaytoHashP *h_payto,
             struct GNUNET_TIME_Timestamp exec_time,
             const struct TALER_PrivateContractHashP *h_contract_terms,
             const struct TALER_DenominationPublicKey *denom_pub,
             const struct TALER_CoinSpendPublicKeyP *coin_pub,
             const struct TALER_Amount *coin_value,
             const struct TALER_Amount *coin_fee)
{
  (void) rowid;
  (void) denom_pub;
  GNUNET_assert (cls == &cb_wt_never);
  GNUNET_assert (0 == GNUNET_memcmp (merchant_pub,
                                     &merchant_pub_wt));
  GNUNET_assert (0 == strcmp (account_payto_uri,
                              "payto://iban/DE67830654080004822650?receiver-name=Test"));
  GNUNET_assert (GNUNET_TIME_timestamp_cmp (exec_time,
                                            ==,
                                            wire_out_date));
  GNUNET_assert (0 == GNUNET_memcmp (h_contract_terms,
                                     &h_contract_terms_wt));
  GNUNET_assert (0 == GNUNET_memcmp (coin_pub,
                                     &coin_pub_wt));
  GNUNET_assert (0 == TALER_amount_cmp (coin_value,
                                        &coin_value_wt));
  GNUNET_assert (0 == TALER_amount_cmp (coin_fee,
                                        &coin_fee_wt));
}


/**
 * Here #deposit_cb() will store the row ID of the deposit.
 */
static uint64_t deposit_rowid;

/**
 * Here #deposit_cb() will store the row ID of the account.
 */
static uint64_t wire_target_row;

/**
 * Here #deposit_cb() will store the hash of the payto URI.
 */
static struct TALER_PaytoHashP wire_target_h_payto;

/**
 * Function called with details about deposits that
 * have been made.  Called in the test on the
 * deposit given in @a cls.
 *
 * @param cls closure a `struct TALER_EXCHANGEDB_Deposit *`
 * @param rowid unique ID for the deposit in our DB, used for marking
 *              it as 'tiny' or 'done'
 * @param merchant_pub public key of the merchant
 * @param coin_pub public key of the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param deposit_fee amount the exchange gets to keep as transaction fees
 * @param h_contract_terms hash of the proposal data known to merchant and customer
 * @param wire_target unique ID of the receiver account
 * @param payto_uri how to pay the merchant, URI in payto://-format;
 * @return transaction status code, #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT to continue to iterate
 */
static enum GNUNET_DB_QueryStatus
deposit_cb (void *cls,
            uint64_t rowid,
            const struct TALER_MerchantPublicKeyP *merchant_pub,
            const struct TALER_CoinSpendPublicKeyP *coin_pub,
            const struct TALER_Amount *amount_with_fee,
            const struct TALER_Amount *deposit_fee,
            const struct TALER_PrivateContractHashP *h_contract_terms,
            uint64_t wire_target,
            const char *payto_uri)
{
  struct TALER_EXCHANGEDB_Deposit *deposit = cls;

  if ( (0 == GNUNET_memcmp (merchant_pub,
                            &deposit->merchant_pub)) &&
       (0 == TALER_amount_cmp (amount_with_fee,
                               &deposit->amount_with_fee)) &&
       (0 == TALER_amount_cmp (deposit_fee,
                               &deposit->deposit_fee)) &&
       (0 == GNUNET_memcmp (h_contract_terms,
                            &deposit->h_contract_terms)) &&
       (0 == GNUNET_memcmp (coin_pub,
                            &deposit->coin.coin_pub)) &&
       (0 == strcmp (payto_uri,
                     deposit->receiver_wire_account)) )
  {
    deposit_rowid = rowid;
    wire_target_row = wire_target;
    TALER_payto_hash (payto_uri,
                      &wire_target_h_payto);
    result = 9;
  }
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Function called with details about deposits that
 * have been made.  Called in the test on the
 * deposit given in @a cls.
 *
 * @param cls closure a `struct TALER_EXCHANGEDB_Deposit *`
 * @param rowid unique ID for the deposit in our DB, used for marking
 *              it as 'tiny' or 'done'
 * @param coin_pub public key of the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param deposit_fee amount the exchange gets to keep as transaction fees
 * @param h_contract_terms hash of the proposal data known to merchant and customer
 * @return transaction status code, #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT to continue to iterate
 */
static enum GNUNET_DB_QueryStatus
matching_deposit_cb (void *cls,
                     uint64_t rowid,
                     const struct TALER_CoinSpendPublicKeyP *coin_pub,
                     const struct TALER_Amount *amount_with_fee,
                     const struct TALER_Amount *deposit_fee,
                     const struct TALER_PrivateContractHashP *h_contract_terms)
{
  struct TALER_EXCHANGEDB_Deposit *deposit = cls;

  deposit_rowid = rowid;
  if ( (0 != TALER_amount_cmp (amount_with_fee,
                               &deposit->amount_with_fee)) ||
       (0 != TALER_amount_cmp (deposit_fee,
                               &deposit->deposit_fee)) ||
       (0 != GNUNET_memcmp (h_contract_terms,
                            &deposit->h_contract_terms)) ||
       (0 != GNUNET_memcmp (coin_pub,
                            &deposit->coin.coin_pub)) )
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


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
 * Function called with details about coins that were refunding,
 * with the goal of auditing the refund's execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refund in our DB
 * @param denom_pub denomination of the @a coin_pub
 * @param coin_pub public key of the coin
 * @param merchant_pub public key of the merchant
 * @param merchant_sig signature of the merchant
 * @param h_contract_terms hash of the proposal data in
 *                        the contract between merchant and customer
 * @param rtransaction_id refund transaction ID chosen by the merchant
 * @param amount_with_fee amount that was deposited including fee
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
audit_refund_cb (void *cls,
                 uint64_t rowid,
                 const struct TALER_DenominationPublicKey *denom_pub,
                 const struct TALER_CoinSpendPublicKeyP *coin_pub,
                 const struct TALER_MerchantPublicKeyP *merchant_pub,
                 const struct TALER_MerchantSignatureP *merchant_sig,
                 const struct TALER_PrivateContractHashP *h_contract_terms,
                 uint64_t rtransaction_id,
                 const struct TALER_Amount *amount_with_fee)
{
  (void) cls;
  (void) rowid;
  (void) denom_pub;
  (void) coin_pub;
  (void) merchant_pub;
  (void) merchant_sig;
  (void) h_contract_terms;
  (void) rtransaction_id;
  (void) amount_with_fee;
  auditor_row_cnt++;
  return GNUNET_OK;
}


/**
 * Function called with details about incoming wire transfers.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refresh session in our DB
 * @param reserve_pub public key of the reserve (also the WTID)
 * @param credit amount that was received
 * @param sender_account_details information about the sender's bank account
 * @param wire_reference unique reference identifying the wire transfer
 * @param execution_date when did we receive the funds
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
audit_reserve_in_cb (void *cls,
                     uint64_t rowid,
                     const struct TALER_ReservePublicKeyP *reserve_pub,
                     const struct TALER_Amount *credit,
                     const char *sender_account_details,
                     uint64_t wire_reference,
                     struct GNUNET_TIME_Timestamp execution_date)
{
  (void) cls;
  (void) rowid;
  (void) reserve_pub;
  (void) credit;
  (void) sender_account_details;
  (void) wire_reference;
  (void) execution_date;
  auditor_row_cnt++;
  return GNUNET_OK;
}


/**
 * Function called with details about withdraw operations.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refresh session in our DB
 * @param h_blind_ev blinded hash of the coin's public key
 * @param denom_pub public denomination key of the deposited coin
 * @param reserve_pub public key of the reserve
 * @param reserve_sig signature over the withdraw operation
 * @param execution_date when did the wallet withdraw the coin
 * @param amount_with_fee amount that was withdrawn
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
audit_reserve_out_cb (void *cls,
                      uint64_t rowid,
                      const struct TALER_BlindedCoinHashP *h_blind_ev,
                      const struct TALER_DenominationPublicKey *denom_pub,
                      const struct TALER_ReservePublicKeyP *reserve_pub,
                      const struct TALER_ReserveSignatureP *reserve_sig,
                      struct GNUNET_TIME_Timestamp execution_date,
                      const struct TALER_Amount *amount_with_fee)
{
  (void) cls;
  (void) rowid;
  (void) h_blind_ev;
  (void) denom_pub;
  (void) reserve_pub;
  (void) reserve_sig;
  (void) execution_date;
  (void) amount_with_fee;
  auditor_row_cnt++;
  return GNUNET_OK;
}


/**
 * Test garbage collection.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
test_gc (void)
{
  struct DenomKeyPair *dkp;
  struct GNUNET_TIME_Timestamp now;
  struct GNUNET_TIME_Timestamp past;
  struct TALER_EXCHANGEDB_DenominationKeyInformationP issue2;
  struct TALER_DenominationHashP denom_hash;

  now = GNUNET_TIME_timestamp_get ();
  past = GNUNET_TIME_absolute_to_timestamp (
    GNUNET_TIME_absolute_subtract (now.abs_time,
                                   GNUNET_TIME_relative_multiply (
                                     GNUNET_TIME_UNIT_HOURS,
                                     4)));
  dkp = create_denom_key_pair (RSA_KEY_SIZE,
                               past,
                               &value,
                               &fees);
  GNUNET_assert (NULL != dkp);
  if (GNUNET_OK !=
      plugin->gc (plugin->cls))
  {
    GNUNET_break (0);
    destroy_denom_key_pair (dkp);
    return GNUNET_SYSERR;
  }
  TALER_denom_pub_hash (&dkp->pub,
                        &denom_hash);

  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
      plugin->get_denomination_info (plugin->cls,
                                     &denom_hash,
                                     &issue2))
  {
    GNUNET_break (0);
    destroy_denom_key_pair (dkp);
    return GNUNET_SYSERR;
  }
  destroy_denom_key_pair (dkp);
  return GNUNET_OK;
}


/**
 * Test wire fee storage.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
test_wire_fees (void)
{
  struct GNUNET_TIME_Timestamp start_date;
  struct GNUNET_TIME_Timestamp end_date;
  struct TALER_Amount wire_fee;
  struct TALER_Amount closing_fee;
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_TIME_Timestamp sd;
  struct GNUNET_TIME_Timestamp ed;
  struct TALER_Amount fee;
  struct TALER_Amount fee2;
  struct TALER_MasterSignatureP ms;

  start_date = GNUNET_TIME_timestamp_get ();
  end_date = GNUNET_TIME_relative_to_timestamp (GNUNET_TIME_UNIT_MINUTES);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.424242",
                                         &wire_fee));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":2.424242",
                                         &closing_fee));
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                              &master_sig,
                              sizeof (master_sig));
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      plugin->insert_wire_fee (plugin->cls,
                               "wire-method",
                               start_date,
                               end_date,
                               &wire_fee,
                               &closing_fee,
                               &master_sig))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
      plugin->insert_wire_fee (plugin->cls,
                               "wire-method",
                               start_date,
                               end_date,
                               &wire_fee,
                               &closing_fee,
                               &master_sig))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* This must fail as 'end_date' is NOT in the
     half-open interval [start_date,end_date) */
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
      plugin->get_wire_fee (plugin->cls,
                            "wire-method",
                            end_date,
                            &sd,
                            &ed,
                            &fee,
                            &fee2,
                            &ms))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      plugin->get_wire_fee (plugin->cls,
                            "wire-method",
                            start_date,
                            &sd,
                            &ed,
                            &fee,
                            &fee2,
                            &ms))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if ( (GNUNET_TIME_timestamp_cmp (sd,
                                   !=,
                                   start_date)) ||
       (GNUNET_TIME_timestamp_cmp (ed,
                                   !=,
                                   end_date)) ||
       (0 != TALER_amount_cmp (&fee,
                               &wire_fee)) ||
       (0 != TALER_amount_cmp (&fee2,
                               &closing_fee)) ||
       (0 != GNUNET_memcmp (&ms,
                            &master_sig)) )
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


static struct TALER_Amount wire_out_amount;


/**
 * Callback with data about an executed wire transfer.
 *
 * @param cls closure
 * @param rowid identifier of the respective row in the database
 * @param date timestamp of the wire transfer (roughly)
 * @param wtid wire transfer subject
 * @param wire wire transfer details of the receiver
 * @param amount amount that was wired
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to stop iteration
 */
static enum GNUNET_GenericReturnValue
audit_wire_cb (void *cls,
               uint64_t rowid,
               struct GNUNET_TIME_Timestamp date,
               const struct TALER_WireTransferIdentifierRawP *wtid,
               const char *payto_uri,
               const struct TALER_Amount *amount)
{
  (void) cls;
  (void) rowid;
  (void) payto_uri;
  auditor_row_cnt++;
  GNUNET_assert (0 ==
                 TALER_amount_cmp (amount,
                                   &wire_out_amount));
  GNUNET_assert (0 ==
                 GNUNET_memcmp (wtid,
                                &wire_out_wtid));
  GNUNET_assert (GNUNET_TIME_timestamp_cmp (date,
                                            ==,
                                            wire_out_date));
  return GNUNET_OK;
}


/**
 * Test API relating to wire_out handling.
 *
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
test_wire_out (const struct TALER_EXCHANGEDB_Deposit *deposit)
{
  struct TALER_PaytoHashP h_payto;

  TALER_payto_hash (deposit->receiver_wire_account,
                    &h_payto);
  auditor_row_cnt = 0;
  memset (&wire_out_wtid,
          42,
          sizeof (wire_out_wtid));
  wire_out_date = GNUNET_TIME_timestamp_get ();
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1",
                                         &wire_out_amount));

  /* we will transiently violate the wtid constraint on
     the aggregation table, so we need to start the special
     transaction where this is allowed... */
  FAILIF (GNUNET_OK !=
          plugin->start_deferred_wire_out (plugin->cls));

  /* setup values for wire transfer aggregation data */
  merchant_pub_wt = deposit->merchant_pub;
  h_contract_terms_wt = deposit->h_contract_terms;
  coin_pub_wt = deposit->coin.coin_pub;

  coin_value_wt = deposit->amount_with_fee;
  coin_fee_wt = fees.deposit;
  GNUNET_assert (0 <
                 TALER_amount_subtract (&transfer_value_wt,
                                        &coin_value_wt,
                                        &coin_fee_wt));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->lookup_wire_transfer (plugin->cls,
                                        &wire_out_wtid,
                                        &cb_wt_never,
                                        NULL));

  {
    struct TALER_PrivateContractHashP h_contract_terms_wt2 =
      h_contract_terms_wt;
    bool pending;
    struct TALER_WireTransferIdentifierRawP wtid2;
    struct TALER_Amount coin_contribution2;
    struct TALER_Amount coin_fee2;
    struct GNUNET_TIME_Timestamp execution_time2;
    struct TALER_EXCHANGEDB_KycStatus kyc;

    h_contract_terms_wt2.hash.bits[0]++;
    FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
            plugin->lookup_transfer_by_deposit (plugin->cls,
                                                &h_contract_terms_wt2,
                                                &h_wire_wt,
                                                &coin_pub_wt,
                                                &merchant_pub_wt,
                                                &pending,
                                                &wtid2,
                                                &execution_time2,
                                                &coin_contribution2,
                                                &coin_fee2,
                                                &kyc));
  }
  /* insert WT data */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_aggregation_tracking (plugin->cls,
                                               &wire_out_wtid,
                                               deposit_rowid));

  /* Now let's fix the transient constraint violation by
     putting in the WTID into the wire_out table */
  {
    struct TALER_ReservePublicKeyP rpub;
    struct TALER_EXCHANGEDB_KycStatus kyc;

    memset (&rpub,
            44,
            sizeof (rpub));
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->inselect_wallet_kyc_status (plugin->cls,
                                                &rpub,
                                                &kyc));
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->store_wire_transfer_out (plugin->cls,
                                             wire_out_date,
                                             &wire_out_wtid,
                                             &h_payto,
                                             "my-config-section",
                                             &wire_out_amount));
  }
  /* And now the commit should still succeed! */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->lookup_wire_transfer (plugin->cls,
                                        &wire_out_wtid,
                                        &cb_wt_check,
                                        &cb_wt_never));
  {
    bool pending;
    struct TALER_WireTransferIdentifierRawP wtid2;
    struct TALER_Amount coin_contribution2;
    struct TALER_Amount coin_fee2;
    struct GNUNET_TIME_Timestamp execution_time2;
    struct TALER_EXCHANGEDB_KycStatus kyc;

    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->lookup_transfer_by_deposit (plugin->cls,
                                                &h_contract_terms_wt,
                                                &h_wire_wt,
                                                &coin_pub_wt,
                                                &merchant_pub_wt,
                                                &pending,
                                                &wtid2,
                                                &execution_time2,
                                                &coin_contribution2,
                                                &coin_fee2,
                                                &kyc));
    GNUNET_assert (0 == GNUNET_memcmp (&wtid2,
                                       &wire_out_wtid));
    GNUNET_assert (GNUNET_TIME_timestamp_cmp (execution_time2,
                                              ==,
                                              wire_out_date));
    GNUNET_assert (0 == TALER_amount_cmp (&coin_contribution2,
                                          &coin_value_wt));
    GNUNET_assert (0 == TALER_amount_cmp (&coin_fee2,
                                          &coin_fee_wt));
  }
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->select_wire_out_above_serial_id (plugin->cls,
                                                   0,
                                                   &audit_wire_cb,
                                                   NULL));
  FAILIF (1 != auditor_row_cnt);

  return GNUNET_OK;
drop:
  return GNUNET_SYSERR;
}


/**
 * Function called about recoups the exchange has to perform.
 *
 * @param cls closure with the expected value for @a coin_blind
 * @param rowid row identifier used to uniquely identify the recoup operation
 * @param timestamp when did we receive the recoup request
 * @param amount how much should be added back to the reserve
 * @param reserve_pub public key of the reserve
 * @param coin public information about the coin
 * @param denom_pub denomination key of @a coin
 * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_COIN_RECOUP
 * @param coin_blind blinding factor used to blind the coin
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static enum GNUNET_GenericReturnValue
recoup_cb (void *cls,
           uint64_t rowid,
           struct GNUNET_TIME_Timestamp timestamp,
           const struct TALER_Amount *amount,
           const struct TALER_ReservePublicKeyP *reserve_pub,
           const struct TALER_CoinPublicInfo *coin,
           const struct TALER_DenominationPublicKey *denom_pub,
           const struct TALER_CoinSpendSignatureP *coin_sig,
           const union TALER_DenominationBlindingKeyP *coin_blind)
{
  const union TALER_DenominationBlindingKeyP *cb = cls;

  (void) rowid;
  (void) timestamp;
  (void) amount;
  (void) reserve_pub;
  (void) coin_sig;
  (void) coin;
  (void) denom_pub;
  FAILIF (NULL == cb);
  FAILIF (0 != GNUNET_memcmp (cb,
                              coin_blind));
  return GNUNET_OK;
drop:
  return GNUNET_SYSERR;
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
 * @param tiny did the exchange defer this transfer because it is too small?
 * @param done did the exchange claim that it made a transfer?
 */
static void
wire_missing_cb (void *cls,
                 uint64_t rowid,
                 const struct TALER_CoinSpendPublicKeyP *coin_pub,
                 const struct TALER_Amount *amount,
                 const char *payto_uri,
                 struct GNUNET_TIME_Timestamp deadline,
                 bool tiny,
                 bool done)
{
  const struct TALER_EXCHANGEDB_Deposit *deposit = cls;

  (void) payto_uri;
  (void) deadline;
  (void) rowid;
  if (tiny)
  {
    GNUNET_break (0);
    result = 66;
  }
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
  struct TALER_CoinSpendSignatureP coin_sig;
  struct GNUNET_TIME_Timestamp deadline;
  union TALER_DenominationBlindingKeyP coin_blind;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct TALER_ReservePublicKeyP reserve_pub2;
  struct TALER_ReservePublicKeyP reserve_pub3;
  struct DenomKeyPair *dkp = NULL;
  struct TALER_MasterSignatureP master_sig;
  struct TALER_EXCHANGEDB_CollectableBlindcoin cbc;
  struct TALER_EXCHANGEDB_CollectableBlindcoin cbc2;
  struct TALER_EXCHANGEDB_ReserveHistory *rh = NULL;
  struct TALER_EXCHANGEDB_ReserveHistory *rh_head;
  struct TALER_EXCHANGEDB_BankTransfer *bt;
  struct TALER_EXCHANGEDB_CollectableBlindcoin *withdraw;
  struct TALER_EXCHANGEDB_Deposit deposit;
  struct TALER_EXCHANGEDB_Deposit deposit2;
  struct TALER_EXCHANGEDB_Refund refund;
  struct TALER_EXCHANGEDB_TransactionList *tl;
  struct TALER_EXCHANGEDB_TransactionList *tlp;
  const char *sndr = "payto://x-taler-bank/localhost:8080/1";
  const char *rcvr = "payto://x-taler-bank/localhost:8080/2";
  const uint32_t num_partitions = 10;
  unsigned int matched;
  unsigned int cnt;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Timestamp now;
  struct TALER_WireSaltP salt;
  struct TALER_CoinPubHashP c_hash;
  uint64_t known_coin_id;
  uint64_t rrc_serial;
  struct TALER_EXCHANGEDB_Refresh refresh;
  struct TALER_DenominationPublicKey *new_denom_pubs = NULL;
  uint64_t reserve_out_serial_id;
  uint64_t melt_serial_id;
  struct TALER_PlanchetMasterSecretP ps;
  union TALER_DenominationBlindingKeyP bks;
  struct TALER_ExchangeWithdrawValues alg_values = {
    /* RSA is simpler, and for the DB there is no real difference between
       CS and RSA, just one should be used, so we use RSA */
    .cipher = TALER_DENOMINATION_RSA
  };

  memset (&deposit,
          0,
          sizeof (deposit));
  deposit.receiver_wire_account = (char *) rcvr;
  memset (&salt,
          45,
          sizeof (salt));
  memset (&refresh,
          0,
          sizeof (refresh));
  ZR_BLK (&cbc);
  ZR_BLK (&cbc2);
  if (NULL ==
      (plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    result = 77;
    return;
  }
  (void) plugin->drop_tables (plugin->cls);
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls))
  {
    result = 77;
    goto cleanup;
  }
  if (GNUNET_OK !=
      plugin->setup_partitions (plugin->cls, num_partitions))
  {
    result = 77;
    goto cleanup;
  }
  plugin->preflight (plugin->cls);
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         "test-1"));

  /* test DB is empty */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->select_recoup_above_serial_id (plugin->cls,
                                                 0,
                                                 &recoup_cb,
                                                 NULL));
  /* simple extension check */
  FAILIF (GNUNET_OK !=
          test_extension_config ());

  RND_BLK (&reserve_pub);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.000010",
                                         &value));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fees.withdraw));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fees.deposit));
  deposit.deposit_fee = fees.deposit;
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fees.refresh));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fees.refund));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.000010",
                                         &amount_with_fee));
  result = 4;
  now = GNUNET_TIME_timestamp_get ();
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->reserves_in_insert (plugin->cls,
                                      &reserve_pub,
                                      &value,
                                      now,
                                      sndr,
                                      "exchange-account-1",
                                      4));
  FAILIF (GNUNET_OK !=
          check_reserve (&reserve_pub,
                         value.value,
                         value.fraction,
                         value.currency));
  now = GNUNET_TIME_timestamp_get ();
  RND_BLK (&reserve_pub2);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->reserves_in_insert (plugin->cls,
                                      &reserve_pub2,
                                      &value,
                                      now,
                                      sndr,
                                      "exchange-account-1",
                                      5));
  FAILIF (GNUNET_OK !=
          check_reserve (&reserve_pub,
                         value.value,
                         value.fraction,
                         value.currency));
  FAILIF (GNUNET_OK !=
          check_reserve (&reserve_pub2,
                         value.value,
                         value.fraction,
                         value.currency));
  result = 5;
  now = GNUNET_TIME_timestamp_get ();
  dkp = create_denom_key_pair (RSA_KEY_SIZE,
                               now,
                               &value,
                               &fees);
  GNUNET_assert (NULL != dkp);
  TALER_denom_pub_hash (&dkp->pub,
                        &cbc.denom_pub_hash);
  RND_BLK (&cbc.reserve_sig);
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

    /* Call TALER_denom_blind()/TALER_denom_sign_blinded() twice, once without
     * age_hash, once with age_hash */
    RND_BLK (&age_hash);
    for (size_t i = 0; i < sizeof(p_ah) / sizeof(p_ah[0]); i++)
    {
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

  {
    bool found;
    bool balance_ok;
    struct TALER_EXCHANGEDB_KycStatus kyc;
    uint64_t ruuid;

    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->do_withdraw (plugin->cls,
                                 NULL,
                                 &cbc,
                                 now,
                                 &found,
                                 &balance_ok,
                                 &kyc,
                                 &ruuid));
    GNUNET_assert (found);
    GNUNET_assert (balance_ok);
    GNUNET_assert (! kyc.ok);
  }
  FAILIF (GNUNET_OK !=
          check_reserve (&reserve_pub,
                         0,
                         0,
                         value.currency));
  FAILIF (GNUNET_OK !=
          check_reserve (&reserve_pub2,
                         value.value,
                         value.fraction,
                         value.currency));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_reserve_by_h_blind (plugin->cls,
                                          &cbc.h_coin_envelope,
                                          &reserve_pub3,
                                          &reserve_out_serial_id));
  FAILIF (0 != GNUNET_memcmp (&reserve_pub,
                              &reserve_pub3));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_withdraw_info (plugin->cls,
                                     &cbc.h_coin_envelope,
                                     &cbc2));
  FAILIF (0 != GNUNET_memcmp (&cbc2.reserve_sig,
                              &cbc.reserve_sig));
  FAILIF (0 != GNUNET_memcmp (&cbc2.reserve_pub,
                              &cbc.reserve_pub));
  result = 6;

  {
    struct TALER_DenominationSignature ds;

    GNUNET_assert (GNUNET_OK ==
                   TALER_denom_sig_unblind (&ds,
                                            &cbc2.sig,
                                            &bks,
                                            &c_hash,
                                            &alg_values,
                                            &dkp->pub));
    FAILIF (GNUNET_OK !=
            TALER_denom_pub_verify (&dkp->pub,
                                    &ds,
                                    &c_hash));
    TALER_denom_sig_free (&ds);
  }

  RND_BLK (&coin_sig);
  RND_BLK (&coin_blind);
  RND_BLK (&deposit.coin.coin_pub);
  TALER_denom_pub_hash (&dkp->pub,
                        &deposit.coin.denom_pub_hash);
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_sig_unblind (&deposit.coin.denom_sig,
                                          &cbc.sig,
                                          &bks,
                                          &c_hash,
                                          &alg_values,
                                          &dkp->pub));
  deadline = GNUNET_TIME_timestamp_get ();
  {
    struct TALER_DenominationHashP dph;
    struct TALER_AgeCommitmentHash agh;

    FAILIF (TALER_EXCHANGEDB_CKS_ADDED !=
            plugin->ensure_coin_known (plugin->cls,
                                       &deposit.coin,
                                       &known_coin_id,
                                       &dph,
                                       &agh));
  }
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls));
  {
    struct GNUNET_TIME_Timestamp deposit_timestamp
      = GNUNET_TIME_timestamp_get ();
    bool balance_ok;
    bool in_conflict;
    struct TALER_PaytoHashP h_payto;

    RND_BLK (&h_payto);
    deposit.refund_deadline
      = GNUNET_TIME_relative_to_timestamp (GNUNET_TIME_UNIT_MONTHS);
    deposit.wire_deadline
      = GNUNET_TIME_relative_to_timestamp (GNUNET_TIME_UNIT_MONTHS);
    deposit.amount_with_fee = value;
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->do_deposit (plugin->cls,
                                &deposit,
                                known_coin_id,
                                &h_payto,
                                false,
                                &deposit_timestamp,
                                &balance_ok,
                                &in_conflict));
    FAILIF (! balance_ok);
    FAILIF (in_conflict);
  }

  {
    bool not_found;
    bool refund_ok;
    bool gone;
    bool conflict;

    refund.coin = deposit.coin;
    refund.details.merchant_pub = deposit.merchant_pub;
    RND_BLK (&refund.details.merchant_sig);
    refund.details.h_contract_terms = deposit.h_contract_terms;
    refund.details.rtransaction_id = 1;
    refund.details.refund_amount = value;
    refund.details.refund_fee = fees.refund;
    RND_BLK (&refund.details.merchant_sig);
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->do_refund (plugin->cls,
                               &refund,
                               &fees.deposit,
                               known_coin_id,
                               &not_found,
                               &refund_ok,
                               &gone,
                               &conflict));
    FAILIF (not_found);
    FAILIF (! refund_ok);
    FAILIF (gone);
    FAILIF (conflict);

    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->select_refunds_by_coin (plugin->cls,
                                            &refund.coin.coin_pub,
                                            &refund.details.merchant_pub,
                                            &refund.details.h_contract_terms,
                                            &check_refund_cb,
                                            &refund));
  }

  /* test do_melt */
  {
    bool zombie_required = false;
    bool balance_ok;

    refresh.coin = deposit.coin;
    RND_BLK (&refresh.coin_sig);
    RND_BLK (&refresh.rc);
    refresh.amount_with_fee = value;
    refresh.noreveal_index = MELT_NOREVEAL_INDEX;
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->do_melt (plugin->cls,
                             NULL,
                             &refresh,
                             known_coin_id,
                             &zombie_required,
                             &balance_ok));
    FAILIF (! balance_ok);
    FAILIF (zombie_required);
  }

  /* test get_melt */
  {
    struct TALER_EXCHANGEDB_Melt ret_refresh_session;

    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->get_melt (plugin->cls,
                              &refresh.rc,
                              &ret_refresh_session,
                              &melt_serial_id));
    FAILIF (refresh.noreveal_index !=
            ret_refresh_session.session.noreveal_index);
    FAILIF (0 !=
            TALER_amount_cmp (&refresh.amount_with_fee,
                              &ret_refresh_session.session.amount_with_fee));
    FAILIF (0 !=
            TALER_amount_cmp (&fees.refresh,
                              &ret_refresh_session.melt_fee));
    FAILIF (0 !=
            GNUNET_memcmp (&refresh.rc,
                           &ret_refresh_session.session.rc));
    FAILIF (0 != GNUNET_memcmp (&refresh.coin_sig,
                                &ret_refresh_session.session.coin_sig));
    FAILIF (0 !=
            GNUNET_memcmp (&refresh.coin.coin_pub,
                           &ret_refresh_session.session.coin.coin_pub));
    FAILIF (0 !=
            GNUNET_memcmp (&refresh.coin.denom_pub_hash,
                           &ret_refresh_session.session.coin.denom_pub_hash));
  }

  {
    /* test 'select_refreshes_above_serial_id' */
    auditor_row_cnt = 0;
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->select_refreshes_above_serial_id (plugin->cls,
                                                      0,
                                                      &audit_refresh_session_cb,
                                                      NULL));
    FAILIF (1 != auditor_row_cnt);
  }

  /* do refresh-reveal */
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
      struct TALER_EXCHANGEDB_RefreshRevealedCoin *ccoin;
      struct GNUNET_TIME_Timestamp now;
      struct TALER_BlindedRsaPlanchet *rp;
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
    RND_BLK (&tprivs);
    RND_BLK (&tpub);
    FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
            plugin->get_refresh_reveal (plugin->cls,
                                        &refresh.rc,
                                        &never_called_cb,
                                        NULL));
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->insert_refresh_reveal (plugin->cls,
                                           melt_serial_id,
                                           MELT_NEW_COINS,
                                           revealed_coins,
                                           TALER_CNC_KAPPA - 1,
                                           tprivs,
                                           &tpub));
    {
      struct TALER_BlindedCoinHashP h_coin_ev;
      struct TALER_CoinSpendPublicKeyP ocp;
      struct TALER_DenominationHashP denom_hash;

      TALER_denom_pub_hash (&new_denom_pubs[0],
                            &denom_hash);
      TALER_coin_ev_hash (&revealed_coins[0].blinded_planchet,
                          &denom_hash,
                          &h_coin_ev);
      FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
              plugin->get_old_coin_by_h_blind (plugin->cls,
                                               &h_coin_ev,
                                               &ocp,
                                               &rrc_serial));
      FAILIF (0 !=
              GNUNET_memcmp (&ocp,
                             &refresh.coin.coin_pub));
    }
    FAILIF (0 >=
            plugin->get_refresh_reveal (plugin->cls,
                                        &refresh.rc,
                                        &check_refresh_reveal_cb,
                                        NULL));
    qs = plugin->get_link_data (plugin->cls,
                                &refresh.coin.coin_pub,
                                &handle_link_data_cb,
                                NULL);
    FAILIF (0 >= qs);
    {
      /* Just to test fetching a coin with melt history */
      struct TALER_EXCHANGEDB_TransactionList *tl;
      enum GNUNET_DB_QueryStatus qs;

      qs = plugin->get_coin_transactions (plugin->cls,
                                          &refresh.coin.coin_pub,
                                          GNUNET_YES,
                                          &tl);
      FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs);
      plugin->free_coin_transaction_list (plugin->cls,
                                          tl);
    }
  }

  /* do recoup-refresh */
  {
    struct GNUNET_TIME_Timestamp recoup_timestamp
      = GNUNET_TIME_timestamp_get ();
    union TALER_DenominationBlindingKeyP coin_bks;
    uint64_t new_known_coin_id;
    struct TALER_CoinPublicInfo new_coin;
    struct TALER_DenominationHashP dph;
    struct TALER_AgeCommitmentHash agh;
    bool recoup_ok;
    bool internal_failure;

    new_coin = deposit.coin; /* steal basic data */
    RND_BLK (&new_coin.coin_pub);
    FAILIF (TALER_EXCHANGEDB_CKS_ADDED !=
            plugin->ensure_coin_known (plugin->cls,
                                       &new_coin,
                                       &new_known_coin_id,
                                       &dph,
                                       &agh));
    RND_BLK (&coin_bks);
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->do_recoup_refresh (plugin->cls,
                                       &deposit.coin.coin_pub,
                                       rrc_serial,
                                       &coin_bks,
                                       &new_coin.coin_pub,
                                       new_known_coin_id,
                                       &coin_sig,
                                       &recoup_timestamp,
                                       &recoup_ok,
                                       &internal_failure));
    FAILIF (! recoup_ok);
    FAILIF (internal_failure);
  }

  /* do recoup */
  {
    struct TALER_EXCHANGEDB_Reserve pre_reserve;
    struct TALER_EXCHANGEDB_Reserve post_reserve;
    struct TALER_Amount delta;
    struct TALER_EXCHANGEDB_KycStatus kyc;
    bool recoup_ok;
    bool internal_failure;
    struct GNUNET_TIME_Timestamp recoup_timestamp
      = GNUNET_TIME_timestamp_get ();

    pre_reserve.pub = reserve_pub;
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->reserves_get (plugin->cls,
                                  &pre_reserve,
                                  &kyc));
    FAILIF (! TALER_amount_is_zero (&pre_reserve.balance));
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->do_recoup (plugin->cls,
                               &reserve_pub,
                               reserve_out_serial_id,
                               &coin_blind,
                               &deposit.coin.coin_pub,
                               known_coin_id,
                               &coin_sig,
                               &recoup_timestamp,
                               &recoup_ok,
                               &internal_failure));
    FAILIF (internal_failure);
    FAILIF (! recoup_ok);
    post_reserve.pub = reserve_pub;
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->reserves_get (plugin->cls,
                                  &post_reserve,
                                  &kyc));
    FAILIF (0 >=
            TALER_amount_subtract (&delta,
                                   &post_reserve.balance,
                                   &pre_reserve.balance));
    FAILIF (0 !=
            TALER_amount_cmp (&delta,
                              &value));
  }

  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         "test-3"));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->select_recoup_above_serial_id (plugin->cls,
                                                 0,
                                                 &recoup_cb,
                                                 &coin_blind));
  /* Do reserve close */
  now = GNUNET_TIME_timestamp_get ();
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fee_closing));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_reserve_closed (plugin->cls,
                                         &reserve_pub2,
                                         now,
                                         sndr,
                                         &wire_out_wtid,
                                         &amount_with_fee,
                                         &fee_closing));
  FAILIF (GNUNET_OK !=
          check_reserve (&reserve_pub2,
                         0,
                         0,
                         value.currency));
  now = GNUNET_TIME_timestamp_get ();
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_reserve_closed (plugin->cls,
                                         &reserve_pub,
                                         now,
                                         sndr,
                                         &wire_out_wtid,
                                         &value,
                                         &fee_closing));
  FAILIF (GNUNET_OK !=
          check_reserve (&reserve_pub,
                         0,
                         0,
                         value.currency));
  result = 7;

  /* check reserve history */
  {
    struct TALER_Amount balance;

    qs = plugin->get_reserve_history (plugin->cls,
                                      &reserve_pub,
                                      &balance,
                                      &rh);
  }
  FAILIF (0 > qs);
  FAILIF (NULL == rh);
  rh_head = rh;
  for (cnt = 0; NULL != rh_head; rh_head = rh_head->next, cnt++)
  {
    switch (rh_head->type)
    {
    case TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE:
      bt = rh_head->details.bank;
      FAILIF (0 !=
              GNUNET_memcmp (&bt->reserve_pub,
                             &reserve_pub));
      /* this is the amount we transferred twice*/
      FAILIF (1 != bt->amount.value);
      FAILIF (1000 != bt->amount.fraction);
      FAILIF (0 != strcmp (CURRENCY, bt->amount.currency));
      FAILIF (NULL == bt->sender_account_details);
      break;
    case TALER_EXCHANGEDB_RO_WITHDRAW_COIN:
      withdraw = rh_head->details.withdraw;
      FAILIF (0 !=
              GNUNET_memcmp (&withdraw->reserve_pub,
                             &reserve_pub));
      FAILIF (0 !=
              GNUNET_memcmp (&withdraw->h_coin_envelope,
                             &cbc.h_coin_envelope));
      break;
    case TALER_EXCHANGEDB_RO_RECOUP_COIN:
      {
        struct TALER_EXCHANGEDB_Recoup *recoup = rh_head->details.recoup;

        FAILIF (0 !=
                GNUNET_memcmp (&recoup->coin_sig,
                               &coin_sig));
        FAILIF (0 !=
                GNUNET_memcmp (&recoup->coin_blind,
                               &coin_blind));
        FAILIF (0 !=
                GNUNET_memcmp (&recoup->reserve_pub,
                               &reserve_pub));
        FAILIF (0 !=
                GNUNET_memcmp (&recoup->coin.coin_pub,
                               &deposit.coin.coin_pub));
        FAILIF (0 !=
                TALER_amount_cmp (&recoup->value,
                                  &value));
      }
      break;
    case TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK:
      {
        struct TALER_EXCHANGEDB_ClosingTransfer *closing
          = rh_head->details.closing;

        FAILIF (0 !=
                GNUNET_memcmp (&closing->reserve_pub,
                               &reserve_pub));
        FAILIF (0 != TALER_amount_cmp (&closing->amount,
                                       &amount_with_fee));
        FAILIF (0 != TALER_amount_cmp (&closing->closing_fee,
                                       &fee_closing));
      }
      break;
    }
  }
  FAILIF (4 != cnt);

  auditor_row_cnt = 0;
  FAILIF (0 >=
          plugin->select_reserves_in_above_serial_id (plugin->cls,
                                                      0,
                                                      &audit_reserve_in_cb,
                                                      NULL));
  FAILIF (0 >=
          plugin->select_withdrawals_above_serial_id (plugin->cls,
                                                      0,
                                                      &audit_reserve_out_cb,
                                                      NULL));
  FAILIF (3 != auditor_row_cnt);


  auditor_row_cnt = 0;
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->select_refunds_above_serial_id (plugin->cls,
                                                  0,
                                                  &audit_refund_cb,
                                                  NULL));
  FAILIF (1 != auditor_row_cnt);
  qs = plugin->get_coin_transactions (plugin->cls,
                                      &refund.coin.coin_pub,
                                      GNUNET_YES,
                                      &tl);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs);
  GNUNET_assert (NULL != tl);
  matched = 0;
  for (tlp = tl; NULL != tlp; tlp = tlp->next)
  {
    switch (tlp->type)
    {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      {
        struct TALER_EXCHANGEDB_DepositListEntry *have = tlp->details.deposit;

        /* Note: we're not comparing the denomination keys, as there is
           still the question of whether we should even bother exporting
           them here. */
        FAILIF (0 !=
                GNUNET_memcmp (&have->csig,
                               &deposit.csig));
        FAILIF (0 !=
                GNUNET_memcmp (&have->merchant_pub,
                               &deposit.merchant_pub));
        FAILIF (0 !=
                GNUNET_memcmp (&have->h_contract_terms,
                               &deposit.h_contract_terms));
        FAILIF (0 !=
                GNUNET_memcmp (&have->wire_salt,
                               &deposit.wire_salt));
        FAILIF (GNUNET_TIME_timestamp_cmp (have->timestamp,
                                           !=,
                                           deposit.timestamp));
        FAILIF (GNUNET_TIME_timestamp_cmp (have->refund_deadline,
                                           !=,
                                           deposit.refund_deadline));
        FAILIF (GNUNET_TIME_timestamp_cmp (have->wire_deadline,
                                           !=,
                                           deposit.wire_deadline));
        FAILIF (0 != TALER_amount_cmp (&have->amount_with_fee,
                                       &deposit.amount_with_fee));
        FAILIF (0 != TALER_amount_cmp (&have->deposit_fee,
                                       &deposit.deposit_fee));
        matched |= 1;
        break;
      }
    /* this coin pub was actually never melted... */
    case TALER_EXCHANGEDB_TT_MELT:
      FAILIF (0 !=
              GNUNET_memcmp (&refresh.rc,
                             &tlp->details.melt->rc));
      matched |= 2;
      break;
    case TALER_EXCHANGEDB_TT_REFUND:
      {
        struct TALER_EXCHANGEDB_RefundListEntry *have = tlp->details.refund;

        /* Note: we're not comparing the denomination keys, as there is
           still the question of whether we should even bother exporting
           them here. */
        FAILIF (0 != GNUNET_memcmp (&have->merchant_pub,
                                    &refund.details.merchant_pub));
        FAILIF (0 != GNUNET_memcmp (&have->merchant_sig,
                                    &refund.details.merchant_sig));
        FAILIF (0 != GNUNET_memcmp (&have->h_contract_terms,
                                    &refund.details.h_contract_terms));
        FAILIF (have->rtransaction_id != refund.details.rtransaction_id);
        FAILIF (0 != TALER_amount_cmp (&have->refund_amount,
                                       &refund.details.refund_amount));
        FAILIF (0 != TALER_amount_cmp (&have->refund_fee,
                                       &refund.details.refund_fee));
        matched |= 4;
        break;
      }
    case TALER_EXCHANGEDB_TT_RECOUP:
      {
        struct TALER_EXCHANGEDB_RecoupListEntry *recoup =
          tlp->details.recoup;

        FAILIF (0 != GNUNET_memcmp (&recoup->coin_sig,
                                    &coin_sig));
        FAILIF (0 != GNUNET_memcmp (&recoup->coin_blind,
                                    &coin_blind));
        FAILIF (0 != GNUNET_memcmp (&recoup->reserve_pub,
                                    &reserve_pub));
        FAILIF (0 != TALER_amount_cmp (&recoup->value,
                                       &value));
        matched |= 8;
        break;
      }
    case TALER_EXCHANGEDB_TT_OLD_COIN_RECOUP:
      /* TODO: check fields better... */
      matched |= 16;
      break;
    default:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Unexpected coin history transaction type: %d\n",
                  tlp->type);
      FAILIF (1);
      break;
    }
  }
  FAILIF (31 != matched);

  plugin->free_coin_transaction_list (plugin->cls,
                                      tl);


  /* Tests for deposits+wire */
  TALER_denom_sig_free (&deposit.coin.denom_sig);
  memset (&deposit,
          0,
          sizeof (deposit));
  deposit.deposit_fee = fees.deposit;
  RND_BLK (&deposit.coin.coin_pub);
  TALER_denom_pub_hash (&dkp->pub,
                        &deposit.coin.denom_pub_hash);
  GNUNET_assert (GNUNET_OK ==
                 TALER_denom_sig_unblind (&deposit.coin.denom_sig,
                                          &cbc.sig,
                                          &bks,
                                          &c_hash,
                                          &alg_values,
                                          &dkp->pub));
  RND_BLK (&deposit.csig);
  RND_BLK (&deposit.merchant_pub);
  RND_BLK (&deposit.h_contract_terms);
  RND_BLK (&deposit.wire_salt);
  deposit.receiver_wire_account =
    "payto://iban/DE67830654080004822650?receiver-name=Test";
  TALER_merchant_wire_signature_hash (
    "payto://iban/DE67830654080004822650?receiver-name=Test",
    &deposit.wire_salt,
    &h_wire_wt);
  deposit.amount_with_fee = value;
  deposit.deposit_fee = fees.deposit;

  deposit.refund_deadline = deadline;
  deposit.wire_deadline = deadline;
  result = 8;
  {
    uint64_t known_coin_id;
    struct TALER_DenominationHashP dph;
    struct TALER_AgeCommitmentHash agh;

    FAILIF (TALER_EXCHANGEDB_CKS_ADDED !=
            plugin->ensure_coin_known (plugin->cls,
                                       &deposit.coin,
                                       &known_coin_id,
                                       &dph,
                                       &agh));
  }
  {
    struct GNUNET_TIME_Timestamp now;
    struct GNUNET_TIME_Timestamp r;
    struct TALER_Amount deposit_fee;
    struct TALER_MerchantWireHashP h_wire;

    now = GNUNET_TIME_timestamp_get ();
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->insert_deposit (plugin->cls,
                                    now,
                                    &deposit));
    TALER_merchant_wire_signature_hash (deposit.receiver_wire_account,
                                        &deposit.wire_salt,
                                        &h_wire);
    FAILIF (1 !=
            plugin->have_deposit2 (plugin->cls,
                                   &deposit.h_contract_terms,
                                   &h_wire,
                                   &deposit.coin.coin_pub,
                                   &deposit.merchant_pub,
                                   deposit.refund_deadline,
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
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->select_deposits_missing_wire (plugin->cls,
                                                  start_range,
                                                  end_range,
                                                  &wire_missing_cb,
                                                  &deposit));
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
  sleep (2); /* give deposit time to be ready */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_ready_deposit (plugin->cls,
                                     0,
                                     INT32_MAX,
                                     true,
                                     &deposit_cb,
                                     &deposit));
  FAILIF (8 == result);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->iterate_matching_deposits (plugin->cls,
                                             &wire_target_h_payto,
                                             &deposit.merchant_pub,
                                             &matching_deposit_cb,
                                             &deposit,
                                             2));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls));
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         "test-2"));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->mark_deposit_tiny (plugin->cls,
                                     &deposit.merchant_pub,
                                     deposit_rowid));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->get_ready_deposit (plugin->cls,
                                     0,
                                     INT32_MAX,
                                     true,
                                     &deposit_cb,
                                     &deposit));
  plugin->rollback (plugin->cls);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_ready_deposit (plugin->cls,
                                     0,
                                     INT32_MAX,
                                     true,
                                     &deposit_cb,
                                     &deposit));
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         "test-3"));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->mark_deposit_done (plugin->cls,
                                     &deposit.merchant_pub,
                                     deposit_rowid));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls));

  result = 10;
  deposit2 = deposit;
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         "test-2"));
  RND_BLK (&deposit2.merchant_pub); /* should fail if merchant is different */
  {
    struct TALER_MerchantWireHashP h_wire;
    struct GNUNET_TIME_Timestamp r;
    struct TALER_Amount deposit_fee;

    TALER_merchant_wire_signature_hash (deposit2.receiver_wire_account,
                                        &deposit2.wire_salt,
                                        &h_wire);
    FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
            plugin->have_deposit2 (plugin->cls,
                                   &deposit2.h_contract_terms,
                                   &h_wire,
                                   &deposit2.coin.coin_pub,
                                   &deposit2.merchant_pub,
                                   deposit2.refund_deadline,
                                   &deposit_fee,
                                   &r));
    deposit2.merchant_pub = deposit.merchant_pub;
    RND_BLK (&deposit2.coin.coin_pub); /* should fail if coin is different */
    FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
            plugin->have_deposit2 (plugin->cls,
                                   &deposit2.h_contract_terms,
                                   &h_wire,
                                   &deposit2.coin.coin_pub,
                                   &deposit2.merchant_pub,
                                   deposit2.refund_deadline,
                                   &deposit_fee,
                                   &r));
  }
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls));


  /* test revocation */
  RND_BLK (&master_sig);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_denomination_revocation (plugin->cls,
                                                  &cbc.denom_pub_hash,
                                                  &master_sig));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls));
  plugin->preflight (plugin->cls);
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         "test-4"));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->insert_denomination_revocation (plugin->cls,
                                                  &cbc.denom_pub_hash,
                                                  &master_sig));
  plugin->rollback (plugin->cls);
  plugin->preflight (plugin->cls);
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         "test-5"));
  {
    struct TALER_MasterSignatureP msig;
    uint64_t rev_rowid;

    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->get_denomination_revocation (plugin->cls,
                                                 &cbc.denom_pub_hash,
                                                 &msig,
                                                 &rev_rowid));
    FAILIF (0 != GNUNET_memcmp (&msig,
                                &master_sig));
  }


  plugin->rollback (plugin->cls);
  FAILIF (GNUNET_OK !=
          test_wire_prepare ());
  FAILIF (GNUNET_OK !=
          test_wire_out (&deposit));
  FAILIF (GNUNET_OK !=
          test_gc ());
  FAILIF (GNUNET_OK !=
          test_wire_fees ());

  plugin->preflight (plugin->cls);

  result = 0;

drop:
  if (0 != result)
    plugin->rollback (plugin->cls);
  if (NULL != rh)
    plugin->free_reserve_history (plugin->cls,
                                  rh);
  rh = NULL;
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
  TALER_denom_sig_free (&deposit.coin.denom_sig);
  TALER_blinded_denom_sig_free (&cbc.sig);
  TALER_blinded_denom_sig_free (&cbc2.sig);
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


/* end of test_exchangedb.c */
