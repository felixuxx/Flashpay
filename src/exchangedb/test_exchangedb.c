/*
  This file is part of TALER
  Copyright (C) 2014-2018 Taler Systems SA

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
  struct TALER_EXCHANGEDB_Session *session = cls;

  GNUNET_assert (11 == buf_size);
  GNUNET_assert (0 == strcasecmp (wire_method,
                                  "testcase"));
  GNUNET_assert (0 == memcmp (buf,
                              "hello world",
                              buf_size));
  GNUNET_break (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT ==
                plugin->wire_prepare_data_mark_finished (plugin->cls,
                                                         session,
                                                         rowid));
}


/**
 * Test API relating to persisting the wire plugins preparation data.
 *
 * @param session database session to use for the test
 * @return #GNUNET_OK on success
 */
static int
test_wire_prepare (struct TALER_EXCHANGEDB_Session *session)
{
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->wire_prepare_data_get (plugin->cls,
                                         session,
                                         &dead_prepare_cb,
                                         NULL));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->wire_prepare_data_insert (plugin->cls,
                                            session,
                                            "testcase",
                                            "hello world",
                                            11));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->wire_prepare_data_get (plugin->cls,
                                         session,
                                         &mark_prepare_cb,
                                         session));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->wire_prepare_data_get (plugin->cls,
                                         session,
                                         &dead_prepare_cb,
                                         NULL));
  return GNUNET_OK;
drop:
  return GNUNET_SYSERR;
}


/**
 * Checks if the given reserve has the given amount of balance and expiry
 *
 * @param session the database connection
 * @param pub the public key of the reserve
 * @param value balance value
 * @param fraction balance fraction
 * @param currency currency of the reserve
 * @return #GNUNET_OK if the given reserve has the same balance and expiration
 *           as the given parameters; #GNUNET_SYSERR if not
 */
static int
check_reserve (struct TALER_EXCHANGEDB_Session *session,
               const struct TALER_ReservePublicKeyP *pub,
               uint64_t value,
               uint32_t fraction,
               const char *currency)
{
  struct TALER_EXCHANGEDB_Reserve reserve;

  reserve.pub = *pub;
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->reserves_get (plugin->cls,
                                session,
                                &reserve));
  FAILIF (value != reserve.balance.value);
  FAILIF (fraction != reserve.balance.fraction);
  FAILIF (0 != strcmp (currency, reserve.balance.currency));

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
 * @param dkp the keypair to destroy
 */
static void
destroy_denom_key_pair (struct DenomKeyPair *dkp)
{
  GNUNET_CRYPTO_rsa_public_key_free (dkp->pub.rsa_public_key);
  GNUNET_CRYPTO_rsa_private_key_free (dkp->priv.rsa_private_key);
  GNUNET_free (dkp);
}


/**
 * Create a denominaiton key pair by registering the denomination in the DB.
 *
 * @param size the size of the denomination key
 * @param session the DB session
 * @param now time to use for key generation, legal expiration will be 3h later.
 * @param fee_withdraw withdraw fee to use
 * @param fee_deposit deposit fee to use
 * @param fee_refresh refresh fee to use
 * @param fee_refund refund fee to use
 * @return the denominaiton key pair; NULL upon error
 */
static struct DenomKeyPair *
create_denom_key_pair (unsigned int size,
                       struct TALER_EXCHANGEDB_Session *session,
                       struct GNUNET_TIME_Absolute now,
                       const struct TALER_Amount *value,
                       const struct TALER_Amount *fee_withdraw,
                       const struct TALER_Amount *fee_deposit,
                       const struct TALER_Amount *fee_refresh,
                       const struct TALER_Amount *fee_refund)
{
  struct DenomKeyPair *dkp;
  struct TALER_EXCHANGEDB_DenominationKey dki;
  struct TALER_EXCHANGEDB_DenominationKeyInformationP issue2;

  dkp = GNUNET_new (struct DenomKeyPair);
  dkp->priv.rsa_private_key = GNUNET_CRYPTO_rsa_private_key_create (size);
  GNUNET_assert (NULL != dkp->priv.rsa_private_key);
  dkp->pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_private_key_get_public (dkp->priv.rsa_private_key);

  /* Using memset() as fields like master key and signature
     are not properly initialized for this test. */
  memset (&dki,
          0,
          sizeof (struct TALER_EXCHANGEDB_DenominationKey));
  dki.denom_pub = dkp->pub;
  GNUNET_TIME_round_abs (&now);
  dki.issue.properties.start = GNUNET_TIME_absolute_hton (now);
  dki.issue.properties.expire_withdraw = GNUNET_TIME_absolute_hton
                                           (GNUNET_TIME_absolute_add (now,
                                                                      GNUNET_TIME_UNIT_HOURS));
  dki.issue.properties.expire_deposit = GNUNET_TIME_absolute_hton
                                          (GNUNET_TIME_absolute_add
                                            (now,
                                            GNUNET_TIME_relative_multiply (
                                              GNUNET_TIME_UNIT_HOURS, 2)));
  dki.issue.properties.expire_legal = GNUNET_TIME_absolute_hton
                                        (GNUNET_TIME_absolute_add
                                          (now,
                                          GNUNET_TIME_relative_multiply (
                                            GNUNET_TIME_UNIT_HOURS, 3)));
  TALER_amount_hton (&dki.issue.properties.value, value);
  TALER_amount_hton (&dki.issue.properties.fee_withdraw, fee_withdraw);
  TALER_amount_hton (&dki.issue.properties.fee_deposit, fee_deposit);
  TALER_amount_hton (&dki.issue.properties.fee_refresh, fee_refresh);
  TALER_amount_hton (&dki.issue.properties.fee_refund, fee_refund);
  GNUNET_CRYPTO_rsa_public_key_hash (dkp->pub.rsa_public_key,
                                     &dki.issue.properties.denom_hash);

  dki.issue.properties.purpose.size = htonl (sizeof (struct
                                                     TALER_DenominationKeyValidityPS));
  dki.issue.properties.purpose.purpose = htonl (
    TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      plugin->insert_denomination_info (plugin->cls,
                                        session,
                                        &dki.denom_pub,
                                        &dki.issue))
  {
    GNUNET_break (0);
    destroy_denom_key_pair (dkp);
    return NULL;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      plugin->get_denomination_info (plugin->cls,
                                     session,
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
static struct TALER_Amount fee_withdraw;
static struct TALER_Amount fee_deposit;
static struct TALER_Amount fee_refresh;
static struct TALER_Amount fee_refund;
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
 * How big do we make the coin envelopes?
 */
#define COIN_ENC_MAX_SIZE 512

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
 * @param num_tprivs number of entries in @a tprivs, should be #TALER_CNC_KAPPA - 1
 * @param tprivs array of @e num_tprivs transfer private keys
 * @param tp transfer public key information
 */
static void
never_called_cb (void *cls,
                 uint32_t num_freshcoins,
                 const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs,
                 unsigned int num_tprivs,
                 const struct TALER_TransferPrivateKeyP *tprivs,
                 const struct TALER_TransferPublicKeyP *tp)
{
  (void) cls;
  (void) num_freshcoins;
  (void) rrcs;
  (void) num_tprivs;
  (void) tprivs;
  (void) tp;
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
 * @param num_tprivs number of entries in @a tprivs, should be #TALER_CNC_KAPPA - 1
 * @param tprivsr array of @e num_tprivs transfer private keys
 * @param tpr transfer public key information
 */
static void
check_refresh_reveal_cb (
  void *cls,
  uint32_t num_freshcoins,
  const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs,
  unsigned int num_tprivs,
  const struct TALER_TransferPrivateKeyP *tprivsr,
  const struct TALER_TransferPublicKeyP *tpr)
{
  (void) cls;
  /* compare the refresh commit coin arrays */
  for (unsigned int cnt = 0; cnt < num_freshcoins; cnt++)
  {
    const struct TALER_EXCHANGEDB_RefreshRevealedCoin *acoin =
      &revealed_coins[cnt];
    const struct TALER_EXCHANGEDB_RefreshRevealedCoin *bcoin = &rrcs[cnt];

    GNUNET_assert (acoin->coin_ev_size == bcoin->coin_ev_size);
    GNUNET_assert (0 ==
                   GNUNET_memcmp (acoin->coin_ev,
                                  bcoin->coin_ev));
    GNUNET_assert (0 ==
                   GNUNET_CRYPTO_rsa_public_key_cmp (
                     acoin->denom_pub.rsa_public_key,
                     bcoin->denom_pub.
                     rsa_public_key));
  }
  GNUNET_assert (0 == GNUNET_memcmp (&tpub, tpr));
  GNUNET_assert (0 == memcmp (tprivs, tprivsr,
                              sizeof(struct TALER_TransferPrivateKeyP)
                              * (TALER_CNC_KAPPA - 1)));
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
 * @param coin_pub public key of the coin
 * @param coin_sig signature from the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param num_freshcoins how many coins were issued
 * @param noreveal_index which index was picked by the exchange in cut-and-choose
 * @param rc what is the session hash
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
audit_refresh_session_cb (void *cls,
                          uint64_t rowid,
                          const struct TALER_DenominationPublicKey *denom_pub,
                          const struct TALER_CoinSpendPublicKeyP *coin_pub,
                          const struct TALER_CoinSpendSignatureP *coin_sig,
                          const struct TALER_Amount *amount_with_fee,
                          uint32_t noreveal_index,
                          const struct TALER_RefreshCommitmentP *rc)
{
  (void) cls;
  (void) rowid;
  (void) denom_pub;
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
    int found;

    found = GNUNET_NO;
    for (unsigned int cnt = 0; cnt < MELT_NEW_COINS; cnt++)
    {
      GNUNET_assert (NULL != ldlp->ev_sig.rsa_signature);
      if ( (0 ==
            GNUNET_CRYPTO_rsa_public_key_cmp (ldlp->denom_pub.rsa_public_key,
                                              new_dkp[cnt]->pub.rsa_public_key))
           &&
           (0 ==
            GNUNET_CRYPTO_rsa_signature_cmp (ldlp->ev_sig.rsa_signature,
                                             revealed_coins[cnt].coin_sig.
                                             rsa_signature)) )
      {
        found = GNUNET_YES;
        break;
      }
    }
    GNUNET_assert (GNUNET_NO != found);
  }
}


/**
 * Function to test melting of coins as part of a refresh session
 *
 * @param session the database session
 * @param refresh_session the refresh session
 * @return #GNUNET_OK if everything went well; #GNUNET_SYSERR if not
 */
static int
test_melting (struct TALER_EXCHANGEDB_Session *session)
{
  struct TALER_EXCHANGEDB_Refresh refresh_session;
  struct TALER_EXCHANGEDB_Melt ret_refresh_session;
  struct DenomKeyPair *dkp;
  struct TALER_DenominationPublicKey *new_denom_pubs;
  int ret;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Absolute now;

  ret = GNUNET_SYSERR;
  RND_BLK (&refresh_session);
  dkp = NULL;
  new_dkp = NULL;
  new_denom_pubs = NULL;
  /* create and test a refresh session */
  refresh_session.noreveal_index = MELT_NOREVEAL_INDEX;
  /* create a denomination (value: 1; fraction: 100) */
  now = GNUNET_TIME_absolute_get ();
  GNUNET_TIME_round_abs (&now);
  dkp = create_denom_key_pair (512,
                               session,
                               now,
                               &value,
                               &fee_withdraw,
                               &fee_deposit,
                               &fee_refresh,
                               &fee_refund);
  GNUNET_assert (NULL != dkp);
  /* initialize refresh session melt data */
  {
    struct GNUNET_HashCode hc;

    RND_BLK (&refresh_session.coin.coin_pub);
    GNUNET_CRYPTO_hash (&refresh_session.coin.coin_pub,
                        sizeof (refresh_session.coin.coin_pub),
                        &hc);
    refresh_session.coin.denom_sig.rsa_signature =
      GNUNET_CRYPTO_rsa_sign_fdh (dkp->priv.rsa_private_key,
                                  &hc);
    GNUNET_assert (NULL != refresh_session.coin.denom_sig.rsa_signature);
    GNUNET_CRYPTO_rsa_public_key_hash (dkp->pub.rsa_public_key,
                                       &refresh_session.coin.denom_pub_hash);
    refresh_session.amount_with_fee = amount_with_fee;
  }

  /* test insert_melt & get_melt */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->get_melt (plugin->cls,
                            session,
                            &refresh_session.rc,
                            &ret_refresh_session));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->ensure_coin_known (plugin->cls,
                                     session,
                                     &refresh_session.coin));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_melt (plugin->cls,
                               session,
                               &refresh_session));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_melt (plugin->cls,
                            session,
                            &refresh_session.rc,
                            &ret_refresh_session));
  FAILIF (refresh_session.noreveal_index !=
          ret_refresh_session.session.noreveal_index);
  FAILIF (0 !=
          TALER_amount_cmp (&refresh_session.amount_with_fee,
                            &ret_refresh_session.session.amount_with_fee));
  FAILIF (0 !=
          TALER_amount_cmp (&fee_refresh,
                            &ret_refresh_session.melt_fee));
  FAILIF (0 !=
          GNUNET_memcmp (&refresh_session.rc, &ret_refresh_session.session.rc));
  FAILIF (0 != GNUNET_memcmp (&refresh_session.coin_sig,
                              &ret_refresh_session.session.coin_sig));
  FAILIF (NULL !=
          ret_refresh_session.session.coin.denom_sig.rsa_signature);
  FAILIF (0 != memcmp (&refresh_session.coin.coin_pub,
                       &ret_refresh_session.session.coin.coin_pub,
                       sizeof (refresh_session.coin.coin_pub)));
  FAILIF (0 !=
          GNUNET_memcmp (&refresh_session.coin.denom_pub_hash,
                         &ret_refresh_session.session.coin.denom_pub_hash));

  /* test 'select_refreshes_above_serial_id' */
  auditor_row_cnt = 0;
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->select_refreshes_above_serial_id (plugin->cls,
                                                    session,
                                                    0,
                                                    &audit_refresh_session_cb,
                                                    NULL));
  FAILIF (1 != auditor_row_cnt);

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
    struct GNUNET_HashCode hc;
    struct GNUNET_TIME_Absolute now;

    now = GNUNET_TIME_absolute_get ();
    GNUNET_TIME_round_abs (&now);
    new_dkp[cnt] = create_denom_key_pair (1024,
                                          session,
                                          now,
                                          &value,
                                          &fee_withdraw,
                                          &fee_deposit,
                                          &fee_refresh,
                                          &fee_refund);
    GNUNET_assert (NULL != new_dkp[cnt]);
    new_denom_pubs[cnt] = new_dkp[cnt]->pub;
    ccoin = &revealed_coins[cnt];
    ccoin->coin_ev_size = (size_t) GNUNET_CRYPTO_random_u64 (
      GNUNET_CRYPTO_QUALITY_WEAK,
      COIN_ENC_MAX_SIZE);
    ccoin->coin_ev = GNUNET_malloc (ccoin->coin_ev_size);
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                ccoin->coin_ev,
                                ccoin->coin_ev_size);
    RND_BLK (&hc);
    ccoin->denom_pub = new_dkp[cnt]->pub;
    ccoin->coin_sig.rsa_signature
      = GNUNET_CRYPTO_rsa_sign_fdh (new_dkp[cnt]->priv.rsa_private_key,
                                    &hc);
  }
  RND_BLK (&tprivs);
  RND_BLK (&tpub);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->get_refresh_reveal (plugin->cls,
                                      session,
                                      &refresh_session.rc,
                                      &never_called_cb,
                                      NULL));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_refresh_reveal (plugin->cls,
                                         session,
                                         &refresh_session.rc,
                                         MELT_NEW_COINS,
                                         revealed_coins,
                                         TALER_CNC_KAPPA - 1,
                                         tprivs,
                                         &tpub));
  FAILIF (0 >=
          plugin->get_refresh_reveal (plugin->cls,
                                      session,
                                      &refresh_session.rc,
                                      &check_refresh_reveal_cb,
                                      NULL));


  qs = plugin->get_link_data (plugin->cls,
                              session,
                              &refresh_session.coin.coin_pub,
                              &handle_link_data_cb,
                              NULL);
  FAILIF (0 >= qs);
  {
    /* Just to test fetching a coin with melt history */
    struct TALER_EXCHANGEDB_TransactionList *tl;
    enum GNUNET_DB_QueryStatus qs;

    qs = plugin->get_coin_transactions (plugin->cls,
                                        session,
                                        &refresh_session.coin.coin_pub,
                                        GNUNET_YES,
                                        &tl);
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs);
    plugin->free_coin_transaction_list (plugin->cls,
                                        tl);
  }


  ret = GNUNET_OK;
drop:
  if (NULL != revealed_coins)
  {
    for (unsigned int cnt = 0; cnt < MELT_NEW_COINS; cnt++)
    {
      if (NULL != revealed_coins[cnt].coin_sig.rsa_signature)
        GNUNET_CRYPTO_rsa_signature_free (
          revealed_coins[cnt].coin_sig.rsa_signature);
      GNUNET_free (revealed_coins[cnt].coin_ev);
    }
    GNUNET_free (revealed_coins);
    revealed_coins = NULL;
  }
  destroy_denom_key_pair (dkp);
  GNUNET_CRYPTO_rsa_signature_free (
    refresh_session.coin.denom_sig.rsa_signature);
  GNUNET_free_non_null (new_denom_pubs);
  for (unsigned int cnt = 0;
       (NULL != new_dkp) && (cnt < MELT_NEW_COINS) && (NULL != new_dkp[cnt]);
       cnt++)
    destroy_denom_key_pair (new_dkp[cnt]);
  GNUNET_free_non_null (new_dkp);
  return ret;
}


/**
 * Callback that should never be called.
 */
static void
cb_wt_never (void *cls,
             uint64_t serial_id,
             const struct TALER_MerchantPublicKeyP *merchant_pub,
             const struct GNUNET_HashCode *h_wire,
             const json_t *wire,
             struct GNUNET_TIME_Absolute exec_time,
             const struct GNUNET_HashCode *h_contract_terms,
             const struct TALER_DenominationPublicKey *denom_pub,
             const struct TALER_CoinSpendPublicKeyP *coin_pub,
             const struct TALER_Amount *coin_value,
             const struct TALER_Amount *coin_fee)
{
  GNUNET_assert (0); /* this statement should be unreachable */
}


/**
 * Callback that should never be called.
 */
static void
cb_wtid_never (void *cls,
               const struct TALER_WireTransferIdentifierRawP *wtid,
               const struct TALER_Amount *coin_contribution,
               const struct TALER_Amount *coin_fee,
               struct GNUNET_TIME_Absolute execution_time)
{
  GNUNET_assert (0);
}


static struct TALER_MerchantPublicKeyP merchant_pub_wt;
static struct GNUNET_HashCode h_wire_wt;
static struct GNUNET_HashCode h_contract_terms_wt;
static struct TALER_CoinSpendPublicKeyP coin_pub_wt;
static struct TALER_Amount coin_value_wt;
static struct TALER_Amount coin_fee_wt;
static struct TALER_Amount transfer_value_wt;
static struct GNUNET_TIME_Absolute wire_out_date;
static struct TALER_WireTransferIdentifierRawP wire_out_wtid;


/**
 * Callback that should be called with the WT data.
 */
static void
cb_wt_check (void *cls,
             uint64_t rowid,
             const struct TALER_MerchantPublicKeyP *merchant_pub,
             const struct GNUNET_HashCode *h_wire,
             const json_t *wire,
             struct GNUNET_TIME_Absolute exec_time,
             const struct GNUNET_HashCode *h_contract_terms,
             const struct TALER_DenominationPublicKey *denom_pub,
             const struct TALER_CoinSpendPublicKeyP *coin_pub,
             const struct TALER_Amount *coin_value,
             const struct TALER_Amount *coin_fee)
{
  GNUNET_assert (cls == &cb_wt_never);
  GNUNET_assert (0 == GNUNET_memcmp (merchant_pub,
                                     &merchant_pub_wt));
  GNUNET_assert (0 == strcmp (json_string_value (json_object_get (wire,
                                                                  "payto_uri")),
                              "payto://sepa/DE67830654080004822650"));
  GNUNET_assert (0 == GNUNET_memcmp (h_wire,
                                     &h_wire_wt));
  GNUNET_assert (exec_time.abs_value_us == wire_out_date.abs_value_us);
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
 * Callback that should be called with the WT data.
 */
static void
cb_wtid_check (void *cls,
               const struct TALER_WireTransferIdentifierRawP *wtid,
               const struct TALER_Amount *coin_contribution,
               const struct TALER_Amount *coin_fee,
               struct GNUNET_TIME_Absolute execution_time)
{
  GNUNET_assert (cls == &cb_wtid_never);
  GNUNET_assert (0 == GNUNET_memcmp (wtid,
                                     &wire_out_wtid));
  GNUNET_assert (execution_time.abs_value_us ==
                 wire_out_date.abs_value_us);
  GNUNET_assert (0 == TALER_amount_cmp (coin_contribution,
                                        &coin_value_wt));
  GNUNET_assert (0 == TALER_amount_cmp (coin_fee,
                                        &coin_fee_wt));
}


/**
 * Here #deposit_cb() will store the row ID of the deposit.
 */
static uint64_t deposit_rowid;


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
 * @param wire_deadline by which the merchant adviced that he would like the
 *        wire transfer to be executed
 * @param wire wire details for the merchant, NULL from iterate_matching_deposits()
 * @return transaction status code, #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT to continue to iterate
 */
static enum GNUNET_DB_QueryStatus
deposit_cb (void *cls,
            uint64_t rowid,
            const struct TALER_MerchantPublicKeyP *merchant_pub,
            const struct TALER_CoinSpendPublicKeyP *coin_pub,
            const struct TALER_Amount *amount_with_fee,
            const struct TALER_Amount *deposit_fee,
            const struct GNUNET_HashCode *h_contract_terms,
            struct GNUNET_TIME_Absolute wire_deadline,
            const json_t *wire)
{
  struct TALER_EXCHANGEDB_Deposit *deposit = cls;
  struct GNUNET_HashCode h_wire;

  deposit_rowid = rowid;
  if (NULL != wire)
    GNUNET_assert (GNUNET_OK ==
                   TALER_JSON_merchant_wire_signature_hash (wire,
                                                            &h_wire));
  if ( (0 != GNUNET_memcmp (merchant_pub,
                            &deposit->merchant_pub)) ||
       (0 != TALER_amount_cmp (amount_with_fee,
                               &deposit->amount_with_fee)) ||
       (0 != TALER_amount_cmp (deposit_fee,
                               &deposit->deposit_fee)) ||
       (0 != GNUNET_memcmp (h_contract_terms,
                            &deposit->h_contract_terms)) ||
       (0 != memcmp (coin_pub,
                     &deposit->coin.coin_pub,
                     sizeof (struct TALER_CoinSpendPublicKeyP))) ||
       ( (NULL != wire) &&
         (0 != GNUNET_memcmp (&h_wire,
                              &deposit->h_wire)) ) )
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
 * @param timestamp when did the deposit happen
 * @param merchant_pub public key of the merchant
 * @param denom_pub denomination of the @a coin_pub
 * @param coin_pub public key of the coin
 * @param coin_sig signature from the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param h_contract_terms hash of the proposal data known to merchant and customer
 * @param refund_deadline by which the merchant adviced that he might want
 *        to get a refund
 * @param wire_deadline by which the merchant adviced that he would like the
 *        wire transfer to be executed
 * @param receiver_wire_account wire details for the merchant, NULL from iterate_matching_deposits()
 * @param done flag set if the deposit was already executed (or not)
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
audit_deposit_cb (void *cls,
                  uint64_t rowid,
                  struct GNUNET_TIME_Absolute timestamp,
                  const struct TALER_MerchantPublicKeyP *merchant_pub,
                  const struct TALER_DenominationPublicKey *denom_pub,
                  const struct TALER_CoinSpendPublicKeyP *coin_pub,
                  const struct TALER_CoinSpendSignatureP *coin_sig,
                  const struct TALER_Amount *amount_with_fee,
                  const struct GNUNET_HashCode *h_contract_terms,
                  struct GNUNET_TIME_Absolute refund_deadline,
                  struct GNUNET_TIME_Absolute wire_deadline,
                  const json_t *receiver_wire_account,
                  int done)
{
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
static int
audit_refund_cb (void *cls,
                 uint64_t rowid,
                 const struct TALER_DenominationPublicKey *denom_pub,
                 const struct TALER_CoinSpendPublicKeyP *coin_pub,
                 const struct TALER_MerchantPublicKeyP *merchant_pub,
                 const struct TALER_MerchantSignatureP *merchant_sig,
                 const struct GNUNET_HashCode *h_contract_terms,
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
static int
audit_reserve_in_cb (void *cls,
                     uint64_t rowid,
                     const struct TALER_ReservePublicKeyP *reserve_pub,
                     const struct TALER_Amount *credit,
                     const char *sender_account_details,
                     uint64_t wire_reference,
                     struct GNUNET_TIME_Absolute execution_date)
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
static int
audit_reserve_out_cb (void *cls,
                      uint64_t rowid,
                      const struct GNUNET_HashCode *h_blind_ev,
                      const struct TALER_DenominationPublicKey *denom_pub,
                      const struct TALER_ReservePublicKeyP *reserve_pub,
                      const struct TALER_ReserveSignatureP *reserve_sig,
                      struct GNUNET_TIME_Absolute execution_date,
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
 * @param session DB session to use
 * @return #GNUNET_OK on success
 */
static int
test_gc (struct TALER_EXCHANGEDB_Session *session)
{
  struct DenomKeyPair *dkp;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute past;
  struct TALER_EXCHANGEDB_DenominationKeyInformationP issue2;
  struct GNUNET_HashCode denom_hash;

  now = GNUNET_TIME_absolute_get ();
  GNUNET_TIME_round_abs (&now);
  past = GNUNET_TIME_absolute_subtract (now,
                                        GNUNET_TIME_relative_multiply (
                                          GNUNET_TIME_UNIT_HOURS,
                                          4));
  dkp = create_denom_key_pair (1024,
                               session,
                               past,
                               &value,
                               &fee_withdraw,
                               &fee_deposit,
                               &fee_refresh,
                               &fee_refund);
  GNUNET_assert (NULL != dkp);
  if (GNUNET_OK !=
      plugin->gc (plugin->cls))
  {
    GNUNET_break (0);
    destroy_denom_key_pair (dkp);
    return GNUNET_SYSERR;
  }
  GNUNET_CRYPTO_rsa_public_key_hash (dkp->pub.rsa_public_key,
                                     &denom_hash);

  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
      plugin->get_denomination_info (plugin->cls,
                                     session,
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
 * @param session DB session to use
 * @return #GNUNET_OK on success
 */
static int
test_wire_fees (struct TALER_EXCHANGEDB_Session *session)
{
  struct GNUNET_TIME_Absolute start_date;
  struct GNUNET_TIME_Absolute end_date;
  struct TALER_Amount wire_fee;
  struct TALER_Amount closing_fee;
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_TIME_Absolute sd;
  struct GNUNET_TIME_Absolute ed;
  struct TALER_Amount fee;
  struct TALER_Amount fee2;
  struct TALER_MasterSignatureP ms;

  start_date = GNUNET_TIME_absolute_get ();
  GNUNET_TIME_round_abs (&start_date);
  end_date = GNUNET_TIME_relative_to_absolute (GNUNET_TIME_UNIT_MINUTES);
  GNUNET_TIME_round_abs (&end_date);
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
                               session,
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
                               session,
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
                            session,
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
                            session,
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
  if ( (sd.abs_value_us != start_date.abs_value_us) ||
       (ed.abs_value_us != end_date.abs_value_us) ||
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
static int
audit_wire_cb (void *cls,
               uint64_t rowid,
               struct GNUNET_TIME_Absolute date,
               const struct TALER_WireTransferIdentifierRawP *wtid,
               const json_t *wire,
               const struct TALER_Amount *amount)
{
  auditor_row_cnt++;
  GNUNET_assert (0 ==
                 TALER_amount_cmp (amount,
                                   &wire_out_amount));
  GNUNET_assert (0 ==
                 GNUNET_memcmp (wtid,
                                &wire_out_wtid));
  GNUNET_assert (date.abs_value_us == wire_out_date.abs_value_us);
  return GNUNET_OK;
}


/**
 * Test API relating to wire_out handling.
 *
 * @param session database session to use for the test
 * @return #GNUNET_OK on success
 */
static int
test_wire_out (struct TALER_EXCHANGEDB_Session *session,
               const struct TALER_EXCHANGEDB_Deposit *deposit)
{
  auditor_row_cnt = 0;
  memset (&wire_out_wtid,
          42,
          sizeof (wire_out_wtid));
  wire_out_date = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&wire_out_date);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1",
                                         &wire_out_amount));

  /* we will transiently violate the wtid constraint on
     the aggregation table, so we need to start the special
     transaction where this is allowed... */
  FAILIF (GNUNET_OK !=
          plugin->start_deferred_wire_out (plugin->cls,
                                           session));

  /* setup values for wire transfer aggregation data */
  merchant_pub_wt = deposit->merchant_pub;
  h_wire_wt = deposit->h_wire;
  h_contract_terms_wt = deposit->h_contract_terms;
  coin_pub_wt = deposit->coin.coin_pub;

  coin_value_wt = deposit->amount_with_fee;
  coin_fee_wt = fee_deposit;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_subtract (&transfer_value_wt,
                                        &coin_value_wt,
                                        &coin_fee_wt));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->lookup_wire_transfer (plugin->cls,
                                        session,
                                        &wire_out_wtid,
                                        &cb_wt_never,
                                        NULL));

  {
    struct GNUNET_HashCode h_contract_terms_wt2 = h_contract_terms_wt;

    h_contract_terms_wt2.bits[0]++;
    FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
            plugin->lookup_transfer_by_deposit (plugin->cls,
                                                session,
                                                &h_contract_terms_wt2,
                                                &h_wire_wt,
                                                &coin_pub_wt,
                                                &merchant_pub_wt,
                                                &cb_wtid_never,
                                                NULL));
  }
  /* insert WT data */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_aggregation_tracking (plugin->cls,
                                               session,
                                               &wire_out_wtid,
                                               deposit_rowid));

  /* Now let's fix the transient constraint violation by
     putting in the WTID into the wire_out table */
  {
    json_t *wire_out_account;

    wire_out_account = json_pack ("{s:s,s:s}",
                                  "payto_uri",
                                  "payto://x-taler-bank/localhost:8080/1",
                                  "salt", "this-is-my-salt");
    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
        plugin->store_wire_transfer_out (plugin->cls,
                                         session,
                                         wire_out_date,
                                         &wire_out_wtid,
                                         wire_out_account,
                                         "my-config-section",
                                         &wire_out_amount))
    {
      json_decref (wire_out_account);
      FAILIF (1);
    }
    json_decref (wire_out_account);
  }
  /* And now the commit should still succeed! */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls,
                          session));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->lookup_wire_transfer (plugin->cls,
                                        session,
                                        &wire_out_wtid,
                                        &cb_wt_check,
                                        &cb_wt_never));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->lookup_transfer_by_deposit (plugin->cls,
                                              session,
                                              &h_contract_terms_wt,
                                              &h_wire_wt,
                                              &coin_pub_wt,
                                              &merchant_pub_wt,
                                              &cb_wtid_check,
                                              &cb_wtid_never));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->select_wire_out_above_serial_id (plugin->cls,
                                                   session,
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
static int
recoup_cb (void *cls,
           uint64_t rowid,
           struct GNUNET_TIME_Absolute timestamp,
           const struct TALER_Amount *amount,
           const struct TALER_ReservePublicKeyP *reserve_pub,
           const struct TALER_CoinPublicInfo *coin,
           const struct TALER_DenominationPublicKey *denom_pub,
           const struct TALER_CoinSpendSignatureP *coin_sig,
           const struct TALER_DenominationBlindingKeyP *coin_blind)
{
  const struct TALER_DenominationBlindingKeyP *cb = cls;

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
 * @param wire where should the funds be wired
 * @param deadline what was the requested wire transfer deadline
 * @param tiny did the exchange defer this transfer because it is too small?
 * @param done did the exchange claim that it made a transfer?
 */
static void
wire_missing_cb (void *cls,
                 uint64_t rowid,
                 const struct TALER_CoinSpendPublicKeyP *coin_pub,
                 const struct TALER_Amount *amount,
                 const json_t *wire,
                 struct GNUNET_TIME_Absolute deadline,
                 /* bool? */ int tiny,
                 /* bool? */ int done)
{
  const struct TALER_EXCHANGEDB_Deposit *deposit = cls;
  struct GNUNET_HashCode h_wire;

  (void) done;
  if (NULL != wire)
    GNUNET_assert (GNUNET_OK ==
                   TALER_JSON_merchant_wire_signature_hash (wire,
                                                            &h_wire));
  else
    memset (&h_wire,
            0,
            sizeof (h_wire));
  if (GNUNET_NO != tiny)
  {
    GNUNET_break (0);
    result = 66;
  }
  if (GNUNET_NO != done)
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
  if (0 != GNUNET_memcmp (&h_wire,
                          &deposit->h_wire))
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
static int
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
  struct TALER_EXCHANGEDB_Session *session;
  struct TALER_CoinSpendSignatureP coin_sig;
  struct GNUNET_TIME_Absolute deadline;
  struct TALER_DenominationBlindingKeyP coin_blind;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct TALER_ReservePublicKeyP reserve_pub2;
  struct DenomKeyPair *dkp;
  struct GNUNET_HashCode dkp_pub_hash;
  struct TALER_MasterSignatureP master_sig;
  struct TALER_EXCHANGEDB_CollectableBlindcoin cbc;
  struct TALER_EXCHANGEDB_CollectableBlindcoin cbc2;
  struct TALER_EXCHANGEDB_ReserveHistory *rh;
  struct TALER_EXCHANGEDB_ReserveHistory *rh_head;
  struct TALER_EXCHANGEDB_BankTransfer *bt;
  struct TALER_EXCHANGEDB_CollectableBlindcoin *withdraw;
  struct TALER_EXCHANGEDB_Deposit deposit;
  struct TALER_EXCHANGEDB_Deposit deposit2;
  struct TALER_EXCHANGEDB_Refund refund;
  struct TALER_EXCHANGEDB_TransactionList *tl;
  struct TALER_EXCHANGEDB_TransactionList *tlp;
  json_t *wire;
  const char *sndr = "payto://x-taler-bank/localhost:8080/1";
  unsigned int matched;
  unsigned int cnt;
  uint64_t rr;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_TIME_Absolute now;

  dkp = NULL;
  rh = NULL;
  session = NULL;
  deposit.coin.denom_sig.rsa_signature = NULL;
  wire = json_pack ("{s:s, s:s}",
                    "payto_uri", "payto://sepa/DE67830654080004822650",
                    "salt", "this-is-a-salt-value");
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
    goto drop;
  }
  if (NULL ==
      (session = plugin->get_session (plugin->cls)))
  {
    result = 77;
    goto drop;
  }

  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         session,
                         "test-1"));

  /* test DB is empty */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->select_recoup_above_serial_id (plugin->cls,
                                                 session,
                                                 0,
                                                 &recoup_cb,
                                                 NULL));
  RND_BLK (&reserve_pub);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.000010",
                                         &value));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fee_withdraw));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fee_deposit));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fee_refresh));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fee_refund));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.000010",
                                         &amount_with_fee));

  result = 4;
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->get_latest_reserve_in_reference (plugin->cls,
                                                   session,
                                                   "exchange-account-1",
                                                   &rr));
  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->reserves_in_insert (plugin->cls,
                                      session,
                                      &reserve_pub,
                                      &value,
                                      now,
                                      sndr,
                                      "exchange-account-1",
                                      4));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_latest_reserve_in_reference (plugin->cls,
                                                   session,
                                                   "exchange-account-1",
                                                   &rr));
  FAILIF (4 != rr);
  FAILIF (GNUNET_OK !=
          check_reserve (session,
                         &reserve_pub,
                         value.value,
                         value.fraction,
                         value.currency));
  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->reserves_in_insert (plugin->cls,
                                      session,
                                      &reserve_pub,
                                      &value,
                                      now,
                                      sndr,
                                      "exchange-account-1",
                                      5));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_latest_reserve_in_reference (plugin->cls,
                                                   session,
                                                   "exchange-account-1",
                                                   &rr));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_latest_reserve_in_reference (plugin->cls,
                                                   session,
                                                   "exchange-account-1",
                                                   &rr));
  FAILIF (5 != rr);
  FAILIF (GNUNET_OK !=
          check_reserve (session,
                         &reserve_pub,
                         value.value * 2,
                         value.fraction * 2,
                         value.currency));
  result = 5;
  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);
  dkp = create_denom_key_pair (1024,
                               session,
                               now,
                               &value,
                               &fee_withdraw,
                               &fee_deposit,
                               &fee_refresh,
                               &fee_refund);
  GNUNET_assert (NULL != dkp);
  GNUNET_CRYPTO_rsa_public_key_hash (dkp->pub.rsa_public_key,
                                     &dkp_pub_hash);
  RND_BLK (&cbc.h_coin_envelope);
  RND_BLK (&cbc.reserve_sig);
  cbc.denom_pub_hash = dkp_pub_hash;
  cbc.sig.rsa_signature
    = GNUNET_CRYPTO_rsa_sign_fdh (dkp->priv.rsa_private_key,
                                  &cbc.h_coin_envelope);
  cbc.reserve_pub = reserve_pub;
  cbc.amount_with_fee = value;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (CURRENCY, &cbc.withdraw_fee));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_withdraw_info (plugin->cls,
                                        session,
                                        &cbc));
  FAILIF (GNUNET_OK !=
          check_reserve (session,
                         &reserve_pub,
                         value.value,
                         value.fraction,
                         value.currency));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_reserve_by_h_blind (plugin->cls,
                                          session,
                                          &cbc.h_coin_envelope,
                                          &reserve_pub2));
  FAILIF (0 != GNUNET_memcmp (&reserve_pub,
                              &reserve_pub2));

  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_withdraw_info (plugin->cls,
                                     session,
                                     &cbc.h_coin_envelope,
                                     &cbc2));
  FAILIF (0 != GNUNET_memcmp (&cbc2.reserve_sig, &cbc.reserve_sig));
  FAILIF (0 != GNUNET_memcmp (&cbc2.reserve_pub, &cbc.reserve_pub));
  result = 6;
  FAILIF (GNUNET_OK !=
          GNUNET_CRYPTO_rsa_verify (&cbc.h_coin_envelope,
                                    cbc2.sig.rsa_signature,
                                    dkp->pub.rsa_public_key));


  RND_BLK (&coin_sig);
  RND_BLK (&coin_blind);
  RND_BLK (&deposit.coin.coin_pub);
  GNUNET_CRYPTO_rsa_public_key_hash (dkp->pub.rsa_public_key,
                                     &deposit.coin.denom_pub_hash);
  deposit.coin.denom_sig = cbc.sig;
  deadline = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&deadline);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->ensure_coin_known (plugin->cls,
                                     session,
                                     &deposit.coin));
  {
    struct TALER_EXCHANGEDB_Reserve pre_reserve;
    struct TALER_EXCHANGEDB_Reserve post_reserve;
    struct TALER_Amount delta;

    pre_reserve.pub = reserve_pub;
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->reserves_get (plugin->cls,
                                  session,
                                  &pre_reserve));
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->insert_recoup_request (plugin->cls,
                                           session,
                                           &reserve_pub,
                                           &deposit.coin,
                                           &coin_sig,
                                           &coin_blind,
                                           &value,
                                           &cbc.h_coin_envelope,
                                           deadline));
    post_reserve.pub = reserve_pub;
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->reserves_get (plugin->cls,
                                  session,
                                  &post_reserve));
    FAILIF (GNUNET_OK !=
            TALER_amount_subtract (&delta,
                                   &post_reserve.balance,
                                   &pre_reserve.balance));
    FAILIF (0 !=
            TALER_amount_cmp (&delta,
                              &value));
  }
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->select_recoup_above_serial_id (plugin->cls,
                                                 session,
                                                 0,
                                                 &recoup_cb,
                                                 &coin_blind));

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_add (&amount_with_fee,
                                   &value,
                                   &value));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.000010",
                                         &fee_closing));
  now = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&now);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_reserve_closed (plugin->cls,
                                         session,
                                         &reserve_pub,
                                         now,
                                         sndr,
                                         &wire_out_wtid,
                                         &amount_with_fee,
                                         &fee_closing));
  FAILIF (GNUNET_OK !=
          check_reserve (session,
                         &reserve_pub,
                         0,
                         0,
                         value.currency));

  result = 7;
  qs = plugin->get_reserve_history (plugin->cls,
                                    session,
                                    &reserve_pub,
                                    &rh);
  FAILIF (0 > qs);
  FAILIF (NULL == rh);
  rh_head = rh;
  for (cnt = 0; NULL != rh_head; rh_head = rh_head->next, cnt++)
  {
    switch (rh_head->type)
    {
    case TALER_EXCHANGEDB_RO_BANK_TO_EXCHANGE:
      bt = rh_head->details.bank;
      FAILIF (0 != memcmp (&bt->reserve_pub,
                           &reserve_pub,
                           sizeof (reserve_pub)));
      /* this is the amount we trasferred twice*/
      FAILIF (1 != bt->amount.value);
      FAILIF (1000 != bt->amount.fraction);
      FAILIF (0 != strcmp (CURRENCY, bt->amount.currency));
      FAILIF (NULL == bt->sender_account_details);
      break;
    case TALER_EXCHANGEDB_RO_WITHDRAW_COIN:
      withdraw = rh_head->details.withdraw;
      FAILIF (0 != memcmp (&withdraw->reserve_pub,
                           &reserve_pub,
                           sizeof (reserve_pub)));
      FAILIF (0 != memcmp (&withdraw->h_coin_envelope,
                           &cbc.h_coin_envelope,
                           sizeof (cbc.h_coin_envelope)));
      break;
    case TALER_EXCHANGEDB_RO_RECOUP_COIN:
      {
        struct TALER_EXCHANGEDB_Recoup *recoup = rh_head->details.recoup;

        FAILIF (0 != memcmp (&recoup->coin_sig,
                             &coin_sig,
                             sizeof (coin_sig)));
        FAILIF (0 != memcmp (&recoup->coin_blind,
                             &coin_blind,
                             sizeof (coin_blind)));
        FAILIF (0 != memcmp (&recoup->reserve_pub,
                             &reserve_pub,
                             sizeof (reserve_pub)));
        FAILIF (0 != memcmp (&recoup->coin.coin_pub,
                             &deposit.coin.coin_pub,
                             sizeof (deposit.coin.coin_pub)));
        FAILIF (0 != TALER_amount_cmp (&recoup->value,
                                       &value));
      }
      break;
    case TALER_EXCHANGEDB_RO_EXCHANGE_TO_BANK:
      {
        struct TALER_EXCHANGEDB_ClosingTransfer *closing
          = rh_head->details.closing;

        FAILIF (0 != memcmp (&closing->reserve_pub,
                             &reserve_pub,
                             sizeof (reserve_pub)));
        FAILIF (0 != TALER_amount_cmp (&closing->amount,
                                       &amount_with_fee));
        FAILIF (0 != TALER_amount_cmp (&closing->closing_fee,
                                       &fee_closing));
      }
      break;
    }
  }
  FAILIF (5 != cnt);

  auditor_row_cnt = 0;
  FAILIF (0 >=
          plugin->select_reserves_in_above_serial_id (plugin->cls,
                                                      session,
                                                      0,
                                                      &audit_reserve_in_cb,
                                                      NULL));
  FAILIF (0 >=
          plugin->select_withdrawals_above_serial_id (plugin->cls,
                                                      session,
                                                      0,
                                                      &audit_reserve_out_cb,
                                                      NULL));
  FAILIF (3 != auditor_row_cnt);

  /* Tests for deposits */
  memset (&deposit,
          0,
          sizeof (deposit));
  RND_BLK (&deposit.coin.coin_pub);
  GNUNET_CRYPTO_rsa_public_key_hash (dkp->pub.rsa_public_key,
                                     &deposit.coin.denom_pub_hash);
  deposit.coin.denom_sig = cbc.sig;
  RND_BLK (&deposit.csig);
  RND_BLK (&deposit.merchant_pub);
  RND_BLK (&deposit.h_contract_terms);
  GNUNET_assert (GNUNET_OK ==
                 TALER_JSON_merchant_wire_signature_hash (wire,
                                                          &deposit.h_wire));
  deposit.receiver_wire_account = wire;
  deposit.amount_with_fee = value;
  deposit.deposit_fee = fee_deposit;

  deposit.refund_deadline = deadline;
  deposit.wire_deadline = deadline;
  result = 8;
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->ensure_coin_known (plugin->cls,
                                     session,
                                     &deposit.coin));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_deposit (plugin->cls,
                                  session,
                                  &deposit));
  FAILIF (1 !=
          plugin->have_deposit (plugin->cls,
                                session,
                                &deposit,
                                GNUNET_YES));
  {
    struct GNUNET_TIME_Absolute start_range;
    struct GNUNET_TIME_Absolute end_range;

    start_range = GNUNET_TIME_absolute_subtract (deadline,
                                                 GNUNET_TIME_UNIT_SECONDS);
    end_range = GNUNET_TIME_absolute_add (deadline,
                                          GNUNET_TIME_UNIT_SECONDS);
    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->select_deposits_missing_wire (plugin->cls,
                                                  session,
                                                  start_range,
                                                  end_range,
                                                  &wire_missing_cb,
                                                  &deposit));
    FAILIF (8 != result);
  }
  auditor_row_cnt = 0;
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->select_deposits_above_serial_id (plugin->cls,
                                                   session,
                                                   0,
                                                   &audit_deposit_cb,
                                                   NULL));
  FAILIF (1 != auditor_row_cnt);
  result = 9;
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->iterate_matching_deposits (plugin->cls,
                                             session,
                                             &deposit.h_wire,
                                             &deposit.merchant_pub,
                                             &deposit_cb,
                                             &deposit,
                                             2));
  sleep (2); /* giv deposit time to be ready */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_ready_deposit (plugin->cls,
                                     session,
                                     &deposit_cb,
                                     &deposit));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls,
                          session));
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         session,
                         "test-2"));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->mark_deposit_tiny (plugin->cls,
                                     session,
                                     deposit_rowid));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->get_ready_deposit (plugin->cls,
                                     session,
                                     &deposit_cb,
                                     &deposit));
  plugin->rollback (plugin->cls,
                    session);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->get_ready_deposit (plugin->cls,
                                     session,
                                     &deposit_cb,
                                     &deposit));
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         session,
                         "test-3"));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->test_deposit_done (plugin->cls,
                                     session,
                                     &deposit.coin.coin_pub,
                                     &deposit.merchant_pub,
                                     &deposit.h_contract_terms,
                                     &deposit.h_wire));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->mark_deposit_done (plugin->cls,
                                     session,
                                     deposit_rowid));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls,
                          session));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->test_deposit_done (plugin->cls,
                                     session,
                                     &deposit.coin.coin_pub,
                                     &deposit.merchant_pub,
                                     &deposit.h_contract_terms,
                                     &deposit.h_wire));

  result = 10;
  deposit2 = deposit;
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         session,
                         "test-2"));
  RND_BLK (&deposit2.merchant_pub); /* should fail if merchant is different */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->have_deposit (plugin->cls,
                                session,
                                &deposit2,
                                GNUNET_YES));
  deposit2.merchant_pub = deposit.merchant_pub;
  RND_BLK (&deposit2.coin.coin_pub); /* should fail if coin is different */
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->have_deposit (plugin->cls,
                                session,
                                &deposit2,
                                GNUNET_YES));
  FAILIF (GNUNET_OK !=
          test_melting (session));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls,
                          session));


  /* test insert_refund! */
  refund.coin = deposit.coin;
  refund.details.merchant_pub = deposit.merchant_pub;
  RND_BLK (&refund.details.merchant_sig);
  refund.details.h_contract_terms = deposit.h_contract_terms;
  refund.details.rtransaction_id
    = GNUNET_CRYPTO_random_u64 (GNUNET_CRYPTO_QUALITY_WEAK,
                                UINT64_MAX);
  refund.details.refund_amount = deposit.amount_with_fee;
  refund.details.refund_fee = fee_refund;
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_refund (plugin->cls,
                                 session,
                                 &refund));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->select_refunds_by_coin (plugin->cls,
                                          session,
                                          &refund.coin.coin_pub,
                                          &refund.details.merchant_pub,
                                          &refund.details.h_contract_terms,
                                          &check_refund_cb,
                                          &refund));

  /* test recoup / revocation */
  RND_BLK (&master_sig);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_denomination_revocation (plugin->cls,
                                                  session,
                                                  &dkp_pub_hash,
                                                  &master_sig));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->commit (plugin->cls,
                          session));
  plugin->preflight (plugin->cls,
                     session);
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         session,
                         "test-4"));
  FAILIF (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS !=
          plugin->insert_denomination_revocation (plugin->cls,
                                                  session,
                                                  &dkp_pub_hash,
                                                  &master_sig));
  plugin->rollback (plugin->cls,
                    session);
  plugin->preflight (plugin->cls,
                     session);
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         session,
                         "test-5"));
  {
    struct TALER_MasterSignatureP msig;
    uint64_t rev_rowid;

    FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
            plugin->get_denomination_revocation (plugin->cls,
                                                 session,
                                                 &dkp_pub_hash,
                                                 &msig,
                                                 &rev_rowid));
    FAILIF (0 != GNUNET_memcmp (&msig,
                                &master_sig));
  }


  RND_BLK (&coin_sig);
  RND_BLK (&coin_blind);
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->insert_recoup_request (plugin->cls,
                                         session,
                                         &reserve_pub,
                                         &deposit.coin,
                                         &coin_sig,
                                         &coin_blind,
                                         &value,
                                         &cbc.h_coin_envelope,
                                         deadline));

  auditor_row_cnt = 0;
  FAILIF (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          plugin->select_refunds_above_serial_id (plugin->cls,
                                                  session,
                                                  0,
                                                  &audit_refund_cb,
                                                  NULL));

  FAILIF (1 != auditor_row_cnt);
  qs = plugin->get_coin_transactions (plugin->cls,
                                      session,
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
        FAILIF (0 != memcmp (&have->csig,
                             &deposit.csig,
                             sizeof (struct TALER_CoinSpendSignatureP)));
        FAILIF (0 != memcmp (&have->merchant_pub,
                             &deposit.merchant_pub,
                             sizeof (struct TALER_MerchantPublicKeyP)));
        FAILIF (0 != memcmp (&have->h_contract_terms,
                             &deposit.h_contract_terms,
                             sizeof (struct GNUNET_HashCode)));
        FAILIF (0 != memcmp (&have->h_wire,
                             &deposit.h_wire,
                             sizeof (struct GNUNET_HashCode)));
        /* Note: not comparing 'wire', seems truly redundant and would be tricky */
        FAILIF (have->timestamp.abs_value_us != deposit.timestamp.abs_value_us);
        FAILIF (have->refund_deadline.abs_value_us !=
                deposit.refund_deadline.abs_value_us);
        FAILIF (have->wire_deadline.abs_value_us !=
                deposit.wire_deadline.abs_value_us);
        FAILIF (0 != TALER_amount_cmp (&have->amount_with_fee,
                                       &deposit.amount_with_fee));
        FAILIF (0 != TALER_amount_cmp (&have->deposit_fee,
                                       &deposit.deposit_fee));
        matched |= 1;
        break;
      }
#if 0
    /* this coin pub was actually never melted... */
    case TALER_EXCHANGEDB_TT_MELT:
      FAILIF (0 != memcmp (&melt,
                           &tlp->details.melt,
                           sizeof (struct TALER_EXCHANGEDB_Melt)));
      matched |= 2;
      break;
#endif
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
    default:
      FAILIF (1);
      break;
    }
  }
  FAILIF (13 != matched);

  plugin->free_coin_transaction_list (plugin->cls,
                                      tl);

  plugin->rollback (plugin->cls,
                    session);
  FAILIF (GNUNET_OK !=
          test_wire_prepare (session));
  FAILIF (GNUNET_OK !=
          test_wire_out (session,
                         &deposit));
  FAILIF (GNUNET_OK !=
          test_gc (session));
  FAILIF (GNUNET_OK !=
          test_wire_fees (session));

  plugin->preflight (plugin->cls,
                     session);

  result = 0;

drop:
  if ( (0 != result) &&
       (NULL != session) )
    plugin->rollback (plugin->cls,
                      session);
  if (NULL != rh)
    plugin->free_reserve_history (plugin->cls,
                                  rh);
  rh = NULL;
  GNUNET_break (GNUNET_OK ==
                plugin->drop_tables (plugin->cls));
  if (NULL != dkp)
    destroy_denom_key_pair (dkp);
  if (NULL != cbc.sig.rsa_signature)
    GNUNET_CRYPTO_rsa_signature_free (cbc.sig.rsa_signature);
  if (NULL != cbc2.sig.rsa_signature)
    GNUNET_CRYPTO_rsa_signature_free (cbc2.sig.rsa_signature);
  dkp = NULL;
  json_decref (wire);
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
