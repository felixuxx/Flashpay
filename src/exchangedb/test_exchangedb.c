/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file exchangedb/test_exchangedb.c
 * @brief test cases for DB interaction functions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include "taler_exchangedb_lib.h"
#include "taler_exchangedb_plugin.h"

static int result;

#define FAILIF(cond)                              \
  do {                                          \
    if (!(cond)){ break;}                      \
    GNUNET_break (0);                           \
    goto drop;                                  \
  } while (0)


#define RND_BLK(ptr)                                                    \
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK, ptr, sizeof (*ptr))

#define ZR_BLK(ptr) \
  memset (ptr, 0, sizeof (*ptr))


#define CURRENCY "EUR"

static struct TALER_EXCHANGEDB_Plugin *plugin;

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

  FAILIF (GNUNET_OK !=
          plugin->reserve_get (plugin->cls,
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
 * @return the denominaiton key pair; NULL upon error
 */
static struct DenomKeyPair *
create_denom_key_pair (unsigned int size,
                       struct TALER_EXCHANGEDB_Session *session,
                       const struct TALER_Amount *value,
                       const struct TALER_Amount *fee_withdraw,
                       const struct TALER_Amount *fee_deposit,
                       const struct TALER_Amount *fee_refresh)
{
  struct DenomKeyPair *dkp;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation dki;

  dkp = GNUNET_new (struct DenomKeyPair);
  dkp->priv.rsa_private_key = GNUNET_CRYPTO_rsa_private_key_create (size);
  GNUNET_assert (NULL != dkp->priv.rsa_private_key);
  dkp->pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_private_key_get_public (dkp->priv.rsa_private_key);

  /* Using memset() as fields like master key and signature
     are not properly initialized for this test. */
  memset (&dki,
          0,
          sizeof (struct TALER_EXCHANGEDB_DenominationKeyIssueInformation));
  dki.denom_pub = dkp->pub;
  dki.issue.properties.start = GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_get ());
  dki.issue.properties.expire_withdraw = GNUNET_TIME_absolute_hton
      (GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get (),
                                 GNUNET_TIME_UNIT_HOURS));
  dki.issue.properties.expire_spend = GNUNET_TIME_absolute_hton
      (GNUNET_TIME_absolute_add
       (GNUNET_TIME_absolute_get (),
        GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_HOURS, 2)));
  dki.issue.properties.expire_legal = GNUNET_TIME_absolute_hton
      (GNUNET_TIME_absolute_add
       (GNUNET_TIME_absolute_get (),
        GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_HOURS, 3)));
  TALER_amount_hton (&dki.issue.properties.value, value);
  TALER_amount_hton (&dki.issue.properties.fee_withdraw, fee_withdraw);
  TALER_amount_hton (&dki.issue.properties.fee_deposit, fee_deposit);
  TALER_amount_hton (&dki.issue.properties.fee_refresh, fee_refresh);
  GNUNET_CRYPTO_rsa_public_key_hash (dkp->pub.rsa_public_key,
                                     &dki.issue.properties.denom_hash);
  if (GNUNET_OK !=
      plugin->insert_denomination_info (plugin->cls,
                                        session,
                                        &dki.denom_pub,
                                        &dki.issue))
  {
    GNUNET_break(0);
    destroy_denom_key_pair (dkp);
    return NULL;
  }
  return dkp;
}

static struct TALER_Amount value;
static struct TALER_Amount fee_withdraw;
static struct TALER_Amount fee_deposit;
static struct TALER_Amount fee_refresh;
static struct TALER_Amount amount_with_fee;

static void
free_refresh_commit_coins_array(struct TALER_EXCHANGEDB_RefreshCommitCoin
                                *commit_coins,
                                unsigned int size)
{
  unsigned int cnt;
  struct TALER_EXCHANGEDB_RefreshCommitCoin *ccoin;
  struct TALER_RefreshLinkEncrypted *rlink;

  for (cnt = 0; cnt < size; cnt++)
  {
    ccoin = &commit_coins[cnt];
    GNUNET_free_non_null (ccoin->coin_ev);
    rlink = (struct TALER_RefreshLinkEncrypted *) ccoin->refresh_link;
    GNUNET_free_non_null (rlink);
  }
  GNUNET_free (commit_coins);
}

#define MELT_NEW_COINS 5

static int
test_refresh_commit_coins (struct TALER_EXCHANGEDB_Session *session,
                           struct TALER_EXCHANGEDB_RefreshSession *refresh_session,
                           const struct GNUNET_HashCode *session_hash)
{
  struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coins;
  struct TALER_EXCHANGEDB_RefreshCommitCoin *ret_commit_coins;
  struct TALER_EXCHANGEDB_RefreshCommitCoin *a_ccoin;
  struct TALER_RefreshLinkEncrypted *a_rlink;
  struct TALER_EXCHANGEDB_RefreshCommitCoin *b_ccoin;
  struct TALER_RefreshLinkEncrypted *b_rlink;
  size_t size;
  unsigned int cnt;
  uint16_t cnc_index;
  int ret;

  #define COIN_ENC_MAX_SIZE 512
  ret = GNUNET_SYSERR;
  ret_commit_coins = NULL;
  commit_coins = GNUNET_new_array (MELT_NEW_COINS,
                                   struct TALER_EXCHANGEDB_RefreshCommitCoin);
  cnc_index = (uint16_t) GNUNET_CRYPTO_random_u32
      (GNUNET_CRYPTO_QUALITY_WEAK, GNUNET_MIN (MELT_NEW_COINS, UINT16_MAX));
  for (cnt=0; cnt < MELT_NEW_COINS; cnt++)
  {
    struct TALER_EXCHANGEDB_RefreshCommitCoin *ccoin;
    struct TALER_RefreshLinkEncrypted *rlink;
    ccoin = &commit_coins[cnt];
    size = GNUNET_CRYPTO_random_u64 (GNUNET_CRYPTO_QUALITY_WEAK,
                                  COIN_ENC_MAX_SIZE);
    rlink = GNUNET_malloc (sizeof (struct TALER_RefreshLinkEncrypted) + size);
    ccoin->refresh_link = rlink;
    ccoin->coin_ev_size = GNUNET_CRYPTO_random_u64
        (GNUNET_CRYPTO_QUALITY_WEAK, COIN_ENC_MAX_SIZE);
    ccoin->coin_ev = GNUNET_malloc (ccoin->coin_ev_size);
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                ccoin->coin_ev,
                                ccoin->coin_ev_size);
    rlink->blinding_key_enc_size = size;
    RND_BLK (&rlink->coin_priv_enc);
    rlink->blinding_key_enc = (const char *) &rlink[1];
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                (void *)rlink->blinding_key_enc,
                                rlink->blinding_key_enc_size);
  }
  FAILIF (GNUNET_OK !=
          plugin->insert_refresh_commit_coins (plugin->cls,
                                               session,
                                               session_hash,
                                               cnc_index,
                                               MELT_NEW_COINS,
                                               commit_coins));
  ret_commit_coins = GNUNET_new_array (MELT_NEW_COINS,
                                       struct TALER_EXCHANGEDB_RefreshCommitCoin);
  FAILIF (GNUNET_OK !=
          plugin->get_refresh_commit_coins (plugin->cls,
                                            session,
                                            session_hash,
                                            cnc_index,
                                            MELT_NEW_COINS,
                                            ret_commit_coins));
  /* compare the refresh commit coin arrays */
  for (cnt = 0; cnt < MELT_NEW_COINS; cnt++)
  {
    a_ccoin = &commit_coins[cnt];
    b_ccoin = &ret_commit_coins[cnt];
    FAILIF (a_ccoin->coin_ev_size != b_ccoin->coin_ev_size);
    FAILIF (0 != memcmp (a_ccoin->coin_ev,
                         a_ccoin->coin_ev,
                         a_ccoin->coin_ev_size));
    a_rlink = a_ccoin->refresh_link;
    b_rlink = b_ccoin->refresh_link;
    FAILIF (a_rlink->blinding_key_enc_size != b_rlink->blinding_key_enc_size);
    FAILIF (0 != memcmp (a_rlink->blinding_key_enc,
                         b_rlink->blinding_key_enc,
                         a_rlink->blinding_key_enc_size));
    FAILIF (0 != memcmp (a_rlink->coin_priv_enc,
                         b_rlink->coin_priv_enc,
                         sizeof (a_rlink->coin_priv_enc)));
  }
  ret = GNUNET_OK;

 drop:
  if (NULL != ret_commit_coins)
    free_refresh_commit_coins_array (ret_commit_coins, MELT_NEW_COINS);
  if (NULL != commit_coins)
    free_refresh_commit_coins_array (commit_coins, MELT_NEW_COINS);
  return ret;
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
#define MELT_OLD_COINS 10
  struct TALER_EXCHANGEDB_RefreshSession refresh_session;
  struct TALER_EXCHANGEDB_RefreshSession ret_refresh_session;
  struct GNUNET_HashCode session_hash;
  struct DenomKeyPair *dkp;
  struct DenomKeyPair **new_dkp;
  /* struct TALER_CoinPublicInfo *coins; */
  struct TALER_EXCHANGEDB_RefreshMelt *melts;
  struct TALER_DenominationPublicKey *new_denom_pubs;
  struct TALER_DenominationPublicKey *ret_denom_pubs;
  unsigned int cnt;
  int ret;

  ret = GNUNET_SYSERR;
  RND_BLK (&refresh_session);
  RND_BLK (&session_hash);
  melts = NULL;
  dkp = NULL;
  new_dkp = NULL;
  new_denom_pubs = NULL;
  ret_denom_pubs = NULL;
  /* create and test a refresh session */
  refresh_session.num_oldcoins = MELT_OLD_COINS;
  refresh_session.num_newcoins = 1;
  refresh_session.noreveal_index = 1;
  FAILIF (GNUNET_OK != plugin->create_refresh_session (plugin->cls,
                                                       session,
                                                       &session_hash,
                                                       &refresh_session));
  FAILIF (GNUNET_OK != plugin->get_refresh_session (plugin->cls,
                                                    session,
                                                    &session_hash,
                                                    &ret_refresh_session));
  FAILIF (0 != memcmp (&ret_refresh_session,
                       &refresh_session,
                       sizeof (refresh_session)));

  /* create a denomination (value: 1; fraction: 100) */
  dkp = create_denom_key_pair (512, session,
                               &value,
                               &fee_withdraw,
                               &fee_deposit,
                               &fee_refresh);
  /* create MELT_OLD_COINS number of refresh melts */
  melts = GNUNET_new_array (MELT_OLD_COINS, struct TALER_EXCHANGEDB_RefreshMelt);
  for (cnt=0; cnt < MELT_OLD_COINS; cnt++)
  {
    struct GNUNET_HashCode hc;

    RND_BLK (&melts[cnt].coin.coin_pub);
    GNUNET_CRYPTO_hash (&melts[cnt].coin.coin_pub,
                        sizeof (melts[cnt].coin.coin_pub),
                        &hc);
    melts[cnt].coin.denom_sig.rsa_signature =
        GNUNET_CRYPTO_rsa_sign_fdh (dkp->priv.rsa_private_key,
                                    &hc);
    melts[cnt].coin.denom_pub = dkp->pub;
    RND_BLK (&melts[cnt].coin_sig);
    melts[cnt].session_hash = session_hash;
    melts[cnt].amount_with_fee = amount_with_fee;
    melts[cnt].melt_fee = fee_refresh;
    FAILIF (GNUNET_OK != plugin->insert_refresh_melt (plugin->cls,
                                                      session,
                                                      cnt,
                                                      &melts[cnt]));
  }
  for (cnt = 0; cnt < MELT_OLD_COINS; cnt++)
  {
    struct TALER_EXCHANGEDB_RefreshMelt ret_melt;
    FAILIF (GNUNET_OK != plugin->get_refresh_melt (plugin->cls,
                                                   session,
                                                   &session_hash,
                                                   cnt,
                                                   &ret_melt));
    FAILIF (0 != GNUNET_CRYPTO_rsa_signature_cmp
            (ret_melt.coin.denom_sig.rsa_signature,
             melts[cnt].coin.denom_sig.rsa_signature));
    FAILIF (0 != memcmp (&ret_melt.coin.coin_pub,
                         &melts[cnt].coin.coin_pub,
                         sizeof (ret_melt.coin.coin_pub)));
    FAILIF (0 != GNUNET_CRYPTO_rsa_public_key_cmp
            (ret_melt.coin.denom_pub.rsa_public_key,
             melts[cnt].coin.denom_pub.rsa_public_key));
    FAILIF (0 != memcmp (&ret_melt.coin_sig,
                         &melts[cnt].coin_sig,
                         sizeof (ret_melt.coin_sig)));
    FAILIF (0 != memcmp (&ret_melt.session_hash,
                         &melts[cnt].session_hash,
                         sizeof (ret_melt.session_hash)));
    FAILIF (0 != TALER_amount_cmp (&ret_melt.amount_with_fee,
                                   &melts[cnt].amount_with_fee));
    FAILIF (0 != TALER_amount_cmp (&ret_melt.melt_fee,
                                   &melts[cnt].melt_fee));
    GNUNET_CRYPTO_rsa_signature_free (ret_melt.coin.denom_sig.rsa_signature);
    GNUNET_CRYPTO_rsa_public_key_free (ret_melt.coin.denom_pub.rsa_public_key);
  }
  new_dkp = GNUNET_new_array (MELT_NEW_COINS, struct DenomKeyPair *);
  new_denom_pubs = GNUNET_new_array (MELT_NEW_COINS,
                                     struct TALER_DenominationPublicKey);
  for (cnt=0; cnt < MELT_NEW_COINS; cnt++)
  {
    new_dkp[cnt] = create_denom_key_pair (128, session,
                                          &value,
                                          &fee_withdraw,
                                          &fee_deposit,
                                          &fee_refresh);
    new_denom_pubs[cnt]=new_dkp[cnt]->pub;
  }
  FAILIF (GNUNET_OK != plugin->insert_refresh_order (plugin->cls,
                                                       session,
                                                       &session_hash,
                                                       MELT_NEW_COINS,
                                                       new_denom_pubs));
  ret_denom_pubs = GNUNET_new_array (MELT_NEW_COINS,
                                     struct TALER_DenominationPublicKey);
  FAILIF (GNUNET_OK != plugin->get_refresh_order (plugin->cls,
                                                  session,
                                                  &session_hash,
                                                  MELT_NEW_COINS,
                                                  ret_denom_pubs));
  for (cnt=0; cnt < MELT_NEW_COINS; cnt++)
  {
    FAILIF (0 != GNUNET_CRYPTO_rsa_public_key_cmp
            (ret_denom_pubs[cnt].rsa_public_key,
             new_denom_pubs[cnt].rsa_public_key));
  }
  FAILIF (GNUNET_OK !=
          test_refresh_commit_coins (session,
                                     &refresh_session,
                                     &session_hash));

  ret = GNUNET_OK;

 drop:
  if (NULL != dkp)
    destroy_denom_key_pair (dkp);
  if (NULL != melts)
  {
    for (cnt = 0; cnt < MELT_OLD_COINS; cnt++)
      GNUNET_CRYPTO_rsa_signature_free (melts[cnt].coin.denom_sig.rsa_signature);
    GNUNET_free (melts);
  }
  for (cnt = 0;
       (NULL != ret_denom_pubs) && (cnt < MELT_NEW_COINS)
           && (NULL != ret_denom_pubs[cnt].rsa_public_key);
       cnt++)
    GNUNET_CRYPTO_rsa_public_key_free (ret_denom_pubs[cnt].rsa_public_key);
  GNUNET_free_non_null (ret_denom_pubs);
  GNUNET_free_non_null (new_denom_pubs);
  for (cnt = 0;
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
             const struct TALER_MerchantPublicKeyP *merchant_pub,
             const struct GNUNET_HashCode *h_wire,
             const struct GNUNET_HashCode *h_contract,
             uint64_t transaction_id,
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
static struct GNUNET_HashCode h_contract_wt;
static uint64_t transaction_id_wt;
static struct TALER_CoinSpendPublicKeyP coin_pub_wt;
static struct TALER_Amount coin_value_wt;
static struct TALER_Amount coin_fee_wt;
static struct TALER_Amount transfer_value_wt;
static struct GNUNET_TIME_Absolute execution_time_wt;
static struct TALER_WireTransferIdentifierRawP wtid_wt;


/**
 * Callback that should be called with the WT data.
 */
static void
cb_wt_check (void *cls,
             const struct TALER_MerchantPublicKeyP *merchant_pub,
             const struct GNUNET_HashCode *h_wire,
             const struct GNUNET_HashCode *h_contract,
             uint64_t transaction_id,
             const struct TALER_CoinSpendPublicKeyP *coin_pub,
             const struct TALER_Amount *coin_value,
             const struct TALER_Amount *coin_fee)
{
  GNUNET_assert (cls == &cb_wt_never);
  GNUNET_assert (0 == memcmp (merchant_pub,
                              &merchant_pub_wt,
                              sizeof (struct TALER_MerchantPublicKeyP)));
  GNUNET_assert (0 == memcmp (h_wire,
                              &h_wire_wt,
                              sizeof (struct GNUNET_HashCode)));
  GNUNET_assert (0 == memcmp (h_contract,
                              &h_contract_wt,
                              sizeof (struct GNUNET_HashCode)));
  GNUNET_assert (transaction_id == transaction_id_wt);
  GNUNET_assert (0 == memcmp (coin_pub,
                              &coin_pub_wt,
                              sizeof (struct TALER_CoinSpendPublicKeyP)));
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
  GNUNET_assert (0 == memcmp (wtid,
                              &wtid_wt,
                              sizeof (struct TALER_WireTransferIdentifierRawP)));
  GNUNET_assert (execution_time.abs_value_us ==
                 execution_time_wt.abs_value_us);
  GNUNET_assert (0 == TALER_amount_cmp (coin_contribution,
                                        &coin_value_wt));
  GNUNET_assert (0 == TALER_amount_cmp (coin_fee,
                                        &coin_fee_wt));
}


/**
 * Main function that will be run by the scheduler.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param cfg configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct TALER_EXCHANGEDB_Session *session;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct DenomKeyPair *dkp;
  struct TALER_EXCHANGEDB_CollectableBlindcoin cbc;
  struct TALER_EXCHANGEDB_CollectableBlindcoin cbc2;
  struct TALER_EXCHANGEDB_ReserveHistory *rh;
  struct TALER_EXCHANGEDB_ReserveHistory *rh_head;
  struct TALER_EXCHANGEDB_BankTransfer *bt;
  struct TALER_EXCHANGEDB_CollectableBlindcoin *withdraw;
  struct TALER_EXCHANGEDB_Deposit deposit;
  struct TALER_EXCHANGEDB_Deposit deposit2;
  struct TALER_WireTransferIdentifierRawP wtid;
  struct GNUNET_HashCode hc;
  json_t *wire;
  json_t *just;
  const char * const json_wire_str =
      "{ \"type\":\"SEPA\", \
\"IBAN\":\"DE67830654080004822650\",                    \
\"name\":\"GNUnet e.V.\",                               \
\"bic\":\"GENODEF1SLR\",                                 \
\"edate\":\"1449930207000\",                                \
\"r\":123456789,                                     \
\"address\": \"foobar\"}";
  unsigned int cnt;

  dkp = NULL;
  rh = NULL;
  wire = NULL;
  session = NULL;
  ZR_BLK (&cbc);
  ZR_BLK (&cbc2);
  if (NULL ==
      (plugin = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    result = 1;
    return;
  }
  if (GNUNET_OK !=
      plugin->create_tables (plugin->cls,
                             GNUNET_YES))
  {
    result = 2;
    goto drop;
  }
  if (NULL ==
      (session = plugin->get_session (plugin->cls,
                                      GNUNET_YES)))
  {
    result = 3;
    goto drop;
  }
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
                 TALER_string_to_amount (CURRENCY ":1.000010",
                                         &amount_with_fee));

  result = 4;
  just = json_loads ("{ \"justification\":\"1\" }", 0, NULL);
  FAILIF (GNUNET_OK !=
          plugin->reserves_in_insert (plugin->cls,
                                      session,
                                      &reserve_pub,
                                      &value,
                                      GNUNET_TIME_absolute_get (),
				      just));
  json_decref (just);
  FAILIF (GNUNET_OK !=
          check_reserve (session,
                         &reserve_pub,
                         value.value,
                         value.fraction,
                         value.currency));
  just = json_loads ("{ \"justification\":\"2\" }", 0, NULL);
  FAILIF (GNUNET_OK !=
          plugin->reserves_in_insert (plugin->cls,
                                      session,
                                      &reserve_pub,
                                      &value,
                                      GNUNET_TIME_absolute_get (),
				      just));
  json_decref (just);
  FAILIF (GNUNET_OK !=
          check_reserve (session,
                         &reserve_pub,
                         value.value * 2,
                         value.fraction * 2,
                         value.currency));
  dkp = create_denom_key_pair (1024, session,
                               &value,
                               &fee_withdraw,
                               &fee_deposit,
                               &fee_refresh);
  RND_BLK(&cbc.h_coin_envelope);
  RND_BLK(&cbc.reserve_sig);
  cbc.denom_pub = dkp->pub;
  GNUNET_CRYPTO_hash (&cbc.h_coin_envelope,
                      sizeof (cbc.h_coin_envelope),
                      &hc);
  cbc.sig.rsa_signature
    = GNUNET_CRYPTO_rsa_sign_fdh (dkp->priv.rsa_private_key,
                                  &hc);
  cbc.reserve_pub = reserve_pub;
  cbc.amount_with_fee = value;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (CURRENCY, &cbc.withdraw_fee));
  FAILIF (GNUNET_OK !=
          plugin->insert_withdraw_info (plugin->cls,
                                        session,
                                        &cbc));
  FAILIF (GNUNET_OK !=
          check_reserve (session,
                         &reserve_pub,
                         value.value,
                         value.fraction,
                         value.currency));
  FAILIF (GNUNET_YES !=
          plugin->get_withdraw_info (plugin->cls,
                                     session,
                                     &cbc.h_coin_envelope,
                                     &cbc2));
  FAILIF (NULL == cbc2.denom_pub.rsa_public_key);
  FAILIF (0 != memcmp (&cbc2.reserve_sig,
                       &cbc.reserve_sig,
                       sizeof (cbc2.reserve_sig)));
  FAILIF (0 != memcmp (&cbc2.reserve_pub,
                       &cbc.reserve_pub,
                       sizeof (cbc2.reserve_pub)));
  FAILIF (GNUNET_OK !=
          GNUNET_CRYPTO_rsa_verify (&cbc.h_coin_envelope,
                                    cbc2.sig.rsa_signature,
                                    dkp->pub.rsa_public_key));
  rh = plugin->get_reserve_history (plugin->cls,
                                    session,
                                    &reserve_pub);
  FAILIF (NULL == rh);
  rh_head = rh;
  for (cnt=0; NULL != rh_head; rh_head=rh_head->next, cnt++)
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
      FAILIF (10 != bt->amount.fraction);
      FAILIF (0 != strcmp (CURRENCY, bt->amount.currency));
      FAILIF (NULL == bt->wire);
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
    }
  }
  FAILIF (3 != cnt);
  /* Tests for deposits */
  memset (&deposit, 0, sizeof (deposit));
  RND_BLK (&deposit.coin.coin_pub);
  deposit.coin.denom_pub = dkp->pub;
  deposit.coin.denom_sig = cbc.sig;
  RND_BLK (&deposit.csig);
  RND_BLK (&deposit.merchant_pub);
  RND_BLK (&deposit.h_contract);
  RND_BLK (&deposit.h_wire);
  wire = json_loads (json_wire_str, 0, NULL);
  deposit.wire = wire;
  deposit.transaction_id =
      GNUNET_CRYPTO_random_u64 (GNUNET_CRYPTO_QUALITY_WEAK, UINT64_MAX);
  deposit.amount_with_fee = value;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (CURRENCY, &deposit.deposit_fee));
  FAILIF (GNUNET_OK !=
          plugin->insert_deposit (plugin->cls,
                                  session, &deposit));
  FAILIF (GNUNET_YES !=
          plugin->have_deposit (plugin->cls,
                                session,
                                &deposit));
  deposit2 = deposit;
  deposit2.transaction_id++;     /* should fail if transaction id is different */
  FAILIF (GNUNET_NO !=
          plugin->have_deposit (plugin->cls,
                                session,
                                &deposit2));
  deposit2.transaction_id = deposit.transaction_id;
  RND_BLK (&deposit2.merchant_pub); /* should fail if merchant is different */
  FAILIF (GNUNET_NO !=
          plugin->have_deposit (plugin->cls,
                                session,
                                &deposit2));
  deposit2.merchant_pub = deposit.merchant_pub;
  RND_BLK (&deposit2.coin.coin_pub); /* should fail if coin is different */
  FAILIF (GNUNET_NO !=
          plugin->have_deposit (plugin->cls,
                                session,
                                &deposit2));
  FAILIF (GNUNET_OK != test_melting (session));

  /* setup values for wire transfer aggregation data */
  memset (&wtid, 42, sizeof (wtid));
  memset (&merchant_pub_wt, 43, sizeof (merchant_pub_wt));
  memset (&h_wire_wt, 44, sizeof (h_wire_wt));
  memset (&h_contract_wt, 45, sizeof (h_contract_wt));
  memset (&coin_pub_wt, 46, sizeof (coin_pub_wt));
  transaction_id_wt = 47;
  execution_time_wt = GNUNET_TIME_absolute_get ();
  memset (&merchant_pub_wt, 48, sizeof (merchant_pub_wt));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY "KUDOS:1.000010",
                                         &coin_value_wt));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY "KUDOS:0.000010",
                                         &coin_fee_wt));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY "KUDOS:1.000000",
                                         &transfer_value_wt));

  FAILIF (GNUNET_NO !=
          plugin->lookup_wire_transfer (plugin->cls,
                                        session,
                                        &wtid_wt,
                                        &cb_wt_never,
                                        NULL));
  FAILIF (GNUNET_NO !=
          plugin->wire_lookup_deposit_wtid (plugin->cls,
                                            session,
                                            &h_contract_wt,
                                            &h_wire_wt,
                                            &coin_pub_wt,
                                            &merchant_pub_wt,
                                            transaction_id_wt,
                                            &cb_wtid_never,
                                            NULL));
  /* insert WT data */
  FAILIF (GNUNET_OK !=
          plugin->insert_aggregation_tracking (plugin->cls,
                                               session,
                                               &wtid_wt,
                                               &merchant_pub_wt,
                                               &h_wire_wt,
                                               &h_contract_wt,
                                               transaction_id_wt,
                                               execution_time_wt,
                                               &coin_pub_wt,
                                               &coin_value_wt,
                                               &coin_fee_wt));
  FAILIF (GNUNET_OK !=
          plugin->lookup_wire_transfer (plugin->cls,
                                        session,
                                        &wtid_wt,
                                        &cb_wt_check,
                                        &cb_wt_never));
  FAILIF (GNUNET_OK !=
          plugin->wire_lookup_deposit_wtid (plugin->cls,
                                            session,
                                            &h_contract_wt,
                                            &h_wire_wt,
                                            &coin_pub_wt,
                                            &merchant_pub_wt,
                                            transaction_id_wt,
                                            &cb_wtid_check,
                                            &cb_wtid_never));
  result = 0;

 drop:
  if (NULL != wire)
    json_decref (wire);
  if (NULL != rh)
    plugin->free_reserve_history (plugin->cls,
                                  rh);
  rh = NULL;
  if (NULL != session)
    GNUNET_break (GNUNET_OK ==
                  plugin->drop_temporary (plugin->cls,
                                          session));
  if (NULL != dkp)
    destroy_denom_key_pair (dkp);
  if (NULL != cbc.sig.rsa_signature)
    GNUNET_CRYPTO_rsa_signature_free (cbc.sig.rsa_signature);
  if (NULL != cbc2.denom_pub.rsa_public_key)
    GNUNET_CRYPTO_rsa_public_key_free (cbc2.denom_pub.rsa_public_key);
  if (NULL != cbc2.sig.rsa_signature)
    GNUNET_CRYPTO_rsa_signature_free (cbc2.sig.rsa_signature);
  dkp = NULL;
  TALER_EXCHANGEDB_plugin_unload (plugin);
  plugin = NULL;
}


int
main (int argc,
      char *const argv[])
{
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_END
  };
  char *argv2[] = {
    "test-exchange-db-<plugin_name>", /* will be replaced later */
    "-c", "test-exchange-db-<plugin_name>.conf", /* will be replaced later */
    NULL,
  };
  const char *plugin_name;
  char *config_filename;
  char *testname;

  result = -1;
  if (NULL == (plugin_name = strrchr (argv[0], (int) '-')))
  {
    GNUNET_break (0);
    return -1;
  }
  plugin_name++;
  (void) GNUNET_asprintf (&testname,
                          "test-exchange-db-%s", plugin_name);
  (void) GNUNET_asprintf (&config_filename,
                          "%s.conf", testname);

  argv2[0] = argv[0];
  argv2[2] = config_filename;
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run ((sizeof (argv2)/sizeof (char *)) - 1, argv2,
                          testname,
                          "Test cases for exchange database helper functions.",
                          options, &run, NULL))
  {
    GNUNET_free (config_filename);
    GNUNET_free (testname);
    return 3;
  }
  GNUNET_free (config_filename);
  GNUNET_free (testname);
  return result;
}
