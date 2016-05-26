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
 * @author Sree Harsha Totakura
 * @author Christian Grothoff
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
    if (!(cond)){ break;}                      \
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
 * Currency we use.
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
                 unsigned long long rowid,
                 const char *wire_method,
                 const char *buf,
                 size_t buf_size)
{
  GNUNET_assert (0);
}


/**
 * Callback that is called with wire prepare data
 * and then marks it as finished.
 */
static void
mark_prepare_cb (void *cls,
                 unsigned long long rowid,
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
  GNUNET_break (GNUNET_OK ==
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
  FAILIF (GNUNET_NO !=
          plugin->wire_prepare_data_get (plugin->cls,
                                         session,
                                         &dead_prepare_cb,
                                         NULL));
  FAILIF (GNUNET_OK !=
          plugin->wire_prepare_data_insert (plugin->cls,
                                            session,
                                            "testcase",
                                            "hello world",
                                            11));
  FAILIF (GNUNET_OK !=
          plugin->wire_prepare_data_get (plugin->cls,
                                         session,
                                         &mark_prepare_cb,
                                         session));
  FAILIF (GNUNET_NO !=
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
                       const struct TALER_Amount *fee_refresh,
                       const struct TALER_Amount *fee_refund)
{
  struct DenomKeyPair *dkp;
  struct TALER_EXCHANGEDB_DenominationKeyIssueInformation dki;
  struct TALER_EXCHANGEDB_DenominationKeyInformationP issue2;
  struct GNUNET_TIME_Absolute now;

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
  now = GNUNET_TIME_absolute_get ();
  GNUNET_TIME_round_abs (&now);
  dki.issue.properties.start = GNUNET_TIME_absolute_hton (now);
  dki.issue.properties.expire_withdraw = GNUNET_TIME_absolute_hton
    (GNUNET_TIME_absolute_add (now,
                               GNUNET_TIME_UNIT_HOURS));
  dki.issue.properties.expire_deposit = GNUNET_TIME_absolute_hton
      (GNUNET_TIME_absolute_add
       (now,
        GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_HOURS, 2)));
  dki.issue.properties.expire_legal = GNUNET_TIME_absolute_hton
      (GNUNET_TIME_absolute_add
       (now,
        GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_HOURS, 3)));
  TALER_amount_hton (&dki.issue.properties.value, value);
  TALER_amount_hton (&dki.issue.properties.fee_withdraw, fee_withdraw);
  TALER_amount_hton (&dki.issue.properties.fee_deposit, fee_deposit);
  TALER_amount_hton (&dki.issue.properties.fee_refresh, fee_refresh);
  TALER_amount_hton (&dki.issue.properties.fee_refund, fee_refund);
  GNUNET_CRYPTO_rsa_public_key_hash (dkp->pub.rsa_public_key,
                                     &dki.issue.properties.denom_hash);

  dki.issue.properties.purpose.size = htonl (sizeof (struct TALER_DenominationKeyValidityPS));
  dki.issue.properties.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
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
  if (GNUNET_OK !=
      plugin->get_denomination_info (plugin->cls,
                                     session,
                                     &dki.denom_pub,
                                     &issue2))
  {
    GNUNET_break(0);
    destroy_denom_key_pair (dkp);
    return NULL;
  }
  if (0 != memcmp (&dki.issue,
                   &issue2,
                   sizeof (issue2)))
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
static struct TALER_Amount fee_refund;
static struct TALER_Amount amount_with_fee;


/**
 * Compare two coin encrypted refresh links.
 *
 * @param rc1 first commitment
 * @param rc2 second commitment
 * @return 0 if they are equal
 */
static int
refresh_link_encrypted_cmp (struct TALER_RefreshLinkEncryptedP *rl1,
                            struct TALER_RefreshLinkEncryptedP *rl2)
{
  if (0 ==
      memcmp (rl1,
	      rl2,
	      sizeof (struct TALER_RefreshLinkEncryptedP)))
    return 0;
  return 1;
}


/**
 * Compare two coin commitments.
 *
 * @param rc1 first commitment
 * @param rc2 second commitment
 * @return 0 if they are equal
 */
static int
commit_coin_cmp (struct TALER_EXCHANGEDB_RefreshCommitCoin *rc1,
                 struct TALER_EXCHANGEDB_RefreshCommitCoin *rc2)
{
  FAILIF (rc1->coin_ev_size != rc2->coin_ev_size);
  FAILIF (0 != memcmp (rc1->coin_ev,
                       rc2->coin_ev,
                       rc2->coin_ev_size));
  FAILIF (0 !=
          refresh_link_encrypted_cmp (&rc1->refresh_link,
                                      &rc2->refresh_link));
  return 0;
 drop:
  return 1;
}


/**
 * Number of newly minted coins to use in the test.
 */
#define MELT_NEW_COINS 5

/**
 * Which index was 'randomly' chosen for the reveal for the test?
 */
#define MELT_NOREVEAL_INDEX 1


static struct TALER_EXCHANGEDB_RefreshCommitCoin *commit_coins[TALER_CNC_KAPPA];

/**
 * Test APIs related to the "insert_refresh_commit_coins" function.
 *
 * @param session database sesison to use
 * @param refresh_session details about the refresh session to use
 * @param session_hash refresh melt session hash to use
 * @return #GNUNET_OK on success
 */
static int
test_refresh_commit_coins (struct TALER_EXCHANGEDB_Session *session,
                           const struct TALER_EXCHANGEDB_RefreshSession *refresh_session,
                           const struct GNUNET_HashCode *session_hash)
{
  struct TALER_EXCHANGEDB_RefreshCommitCoin *ret_commit_coins;
  struct TALER_EXCHANGEDB_RefreshCommitCoin *a_ccoin;
  struct TALER_RefreshLinkEncryptedP a_rlink;
  struct TALER_EXCHANGEDB_RefreshCommitCoin *b_ccoin;
  struct TALER_RefreshLinkEncryptedP b_rlink;
  unsigned int cnt;
  uint16_t cnc_index;
  int ret;

#define COIN_ENC_MAX_SIZE 512
  ret = GNUNET_SYSERR;
  ret_commit_coins = NULL;
  for (cnc_index=0;cnc_index < TALER_CNC_KAPPA; cnc_index++)
  {
    commit_coins[cnc_index]
      = GNUNET_new_array (MELT_NEW_COINS,
                          struct TALER_EXCHANGEDB_RefreshCommitCoin);
    for (cnt=0; cnt < MELT_NEW_COINS; cnt++)
    {
      struct TALER_EXCHANGEDB_RefreshCommitCoin *ccoin;
      struct TALER_RefreshLinkEncryptedP rlink;

      ccoin = &commit_coins[cnc_index][cnt];
      GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                  &rlink,
                                  sizeof (rlink));
      ccoin->refresh_link = rlink;
      ccoin->coin_ev_size = GNUNET_CRYPTO_random_u64
        (GNUNET_CRYPTO_QUALITY_WEAK, COIN_ENC_MAX_SIZE);
      ccoin->coin_ev = GNUNET_malloc (ccoin->coin_ev_size);
      GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                  ccoin->coin_ev,
                                  ccoin->coin_ev_size);
    }
    FAILIF (GNUNET_OK !=
            plugin->insert_refresh_commit_coins (plugin->cls,
                                                 session,
                                                 session_hash,
                                                 cnc_index,
                                                 MELT_NEW_COINS,
                                                 commit_coins[cnc_index]));
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
      a_ccoin = &commit_coins[cnc_index][cnt];
      b_ccoin = &ret_commit_coins[cnt];
      FAILIF (a_ccoin->coin_ev_size != b_ccoin->coin_ev_size);
      FAILIF (0 != memcmp (a_ccoin->coin_ev,
                           a_ccoin->coin_ev,
                           a_ccoin->coin_ev_size));
      a_rlink = a_ccoin->refresh_link;
      b_rlink = b_ccoin->refresh_link;
      FAILIF (0 != memcmp (a_rlink.blinding_key_enc,
                           b_rlink.blinding_key_enc,
                           sizeof (a_rlink.blinding_key_enc)));
      FAILIF (0 != memcmp (a_rlink.coin_priv_enc,
                           b_rlink.coin_priv_enc,
                           sizeof (a_rlink.coin_priv_enc)));
    }
  }
  ret = GNUNET_OK;

 drop:
  if (NULL != ret_commit_coins)
  {
    plugin->free_refresh_commit_coins (plugin->cls,
                                       MELT_NEW_COINS,
                                       ret_commit_coins);
    GNUNET_free (ret_commit_coins);
  }
  return ret;
}


static struct TALER_RefreshCommitLinkP rclp[TALER_CNC_KAPPA];


/**
 * Test APIs related to the "insert_refresh_commit_coins" function.
 *
 * @param session database sesison to use
 * @param refresh_session details about the refresh session to use
 * @param session_hash refresh melt session hash to use
 * @return #GNUNET_OK on success
 */
static int
test_refresh_commit_links (struct TALER_EXCHANGEDB_Session *session,
                           const struct TALER_EXCHANGEDB_RefreshSession *refresh_session,
                           const struct GNUNET_HashCode *session_hash)
{
  struct TALER_RefreshCommitLinkP cl2;
  int ret;
  unsigned int i;

  ret = GNUNET_SYSERR;
  FAILIF (GNUNET_NO !=
          plugin->get_refresh_commit_link (plugin->cls,
                                           session,
                                           session_hash,
                                           MELT_NOREVEAL_INDEX,
                                           &cl2));
  for (i=0;i<TALER_CNC_KAPPA;i++)
  {
    RND_BLK (&rclp[i]);
    FAILIF (GNUNET_OK !=
            plugin->insert_refresh_commit_link (plugin->cls,
                                                session,
                                                session_hash,
                                                i,
                                                &rclp[i]));

    FAILIF (GNUNET_OK !=
            plugin->get_refresh_commit_link (plugin->cls,
                                             session,
                                             session_hash,
                                             i,
                                             &cl2));
    FAILIF (0 !=
            memcmp (&rclp[i],
                    &cl2,
                    sizeof (struct TALER_RefreshCommitLinkP)));
  }
  ret = GNUNET_OK;
 drop:
  return ret;
}


static struct GNUNET_HashCode session_hash;


/**
 * Function called with the session hashes and transfer secret
 * information for a given coin.  Checks if they are as expected.
 *
 * @param cls closure
 * @param sh a session the coin was melted in
 * @param transfer_pub public transfer key for the session
 * @param shared_secret_enc set to shared secret for the session
 */
static void
check_transfer_data (void *cls,
                     const struct GNUNET_HashCode *sh,
                     const struct TALER_TransferPublicKeyP *transfer_pub,
                     const struct TALER_EncryptedLinkSecretP *shared_secret_enc)
{
  int *ok = cls;

  FAILIF (0 != memcmp (&rclp[MELT_NOREVEAL_INDEX].transfer_pub,
                       transfer_pub,
                       sizeof (struct TALER_TransferPublicKeyP)));
  FAILIF (0 != memcmp (&rclp[MELT_NOREVEAL_INDEX].shared_secret_enc,
                       shared_secret_enc,
                       sizeof (struct TALER_EncryptedLinkSecretP)));
  FAILIF (0 != memcmp (&session_hash,
                       sh,
                       sizeof (struct GNUNET_HashCode)));
  *ok = GNUNET_OK;
  return;
 drop:
  *ok = GNUNET_SYSERR;
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
  struct TALER_EXCHANGEDB_RefreshSession refresh_session;
  struct TALER_EXCHANGEDB_RefreshSession ret_refresh_session;
  struct DenomKeyPair *dkp;
  struct DenomKeyPair **new_dkp;
  /* struct TALER_CoinPublicInfo *coins; */
  struct TALER_EXCHANGEDB_RefreshMelt *meltp;
  struct TALER_DenominationPublicKey *new_denom_pubs;
  struct TALER_DenominationPublicKey *ret_denom_pubs;
  struct TALER_EXCHANGEDB_MeltCommitment *mc;
  struct TALER_EXCHANGEDB_LinkDataList *ldl;
  struct TALER_EXCHANGEDB_LinkDataList *ldlp;
  struct TALER_DenominationSignature ev_sigs[MELT_NEW_COINS];
    unsigned int cnt;
  unsigned int i;
  int ret;

  ret = GNUNET_SYSERR;
  RND_BLK (&refresh_session);
  RND_BLK (&session_hash);
  dkp = NULL;
  new_dkp = NULL;
  new_denom_pubs = NULL;
  ret_denom_pubs = NULL;
  /* create and test a refresh session */
  refresh_session.num_newcoins = MELT_NEW_COINS;
  refresh_session.noreveal_index = MELT_NOREVEAL_INDEX;
  /* create a denomination (value: 1; fraction: 100) */
  dkp = create_denom_key_pair (512,
                               session,
                               &value,
                               &fee_withdraw,
                               &fee_deposit,
                               &fee_refresh,
			       &fee_refund);
  /* initialize refresh session melt data */
  {
    struct GNUNET_HashCode hc;

    meltp = &refresh_session.melt;
    RND_BLK (&meltp->coin.coin_pub);
    GNUNET_CRYPTO_hash (&meltp->coin.coin_pub,
                        sizeof (meltp->coin.coin_pub),
                        &hc);
    meltp->coin.denom_sig.rsa_signature =
        GNUNET_CRYPTO_rsa_sign_fdh (dkp->priv.rsa_private_key,
                                    &hc);
    GNUNET_assert (NULL != meltp->coin.denom_sig.rsa_signature);
    meltp->coin.denom_pub = dkp->pub;
    RND_BLK (&meltp->coin_sig);
    meltp->session_hash = session_hash;
    meltp->amount_with_fee = amount_with_fee;
    meltp->melt_fee = fee_refresh;
  }

  FAILIF (GNUNET_OK != plugin->create_refresh_session (plugin->cls,
                                                       session,
                                                       &session_hash,
                                                       &refresh_session));
  FAILIF (GNUNET_OK != plugin->get_refresh_session (plugin->cls,
                                                    session,
                                                    &session_hash,
                                                    &ret_refresh_session));
  FAILIF (ret_refresh_session.num_newcoins != refresh_session.num_newcoins);
  FAILIF (ret_refresh_session.noreveal_index != refresh_session.noreveal_index);

  /* check refresh session melt data */
  {
    struct TALER_EXCHANGEDB_RefreshMelt *ret_melt;

    ret_melt = &ret_refresh_session.melt;
    FAILIF (0 != GNUNET_CRYPTO_rsa_signature_cmp
            (ret_melt->coin.denom_sig.rsa_signature,
             meltp->coin.denom_sig.rsa_signature));
    FAILIF (0 != memcmp (&ret_melt->coin.coin_pub,
                         &meltp->coin.coin_pub,
                         sizeof (ret_melt->coin.coin_pub)));
    FAILIF (0 != GNUNET_CRYPTO_rsa_public_key_cmp
            (ret_melt->coin.denom_pub.rsa_public_key,
             meltp->coin.denom_pub.rsa_public_key));
    FAILIF (0 != memcmp (&ret_melt->coin_sig,
                         &meltp->coin_sig,
                         sizeof (ret_melt->coin_sig)));
    FAILIF (0 != memcmp (&ret_melt->session_hash,
                         &meltp->session_hash,
                         sizeof (ret_melt->session_hash)));
    FAILIF (0 != TALER_amount_cmp (&ret_melt->amount_with_fee,
                                   &meltp->amount_with_fee));
    FAILIF (0 != TALER_amount_cmp (&ret_melt->melt_fee,
                                   &meltp->melt_fee));
    GNUNET_CRYPTO_rsa_signature_free (ret_melt->coin.denom_sig.rsa_signature);
    GNUNET_CRYPTO_rsa_public_key_free (ret_melt->coin.denom_pub.rsa_public_key);
  }
  new_dkp = GNUNET_new_array (MELT_NEW_COINS, struct DenomKeyPair *);
  new_denom_pubs = GNUNET_new_array (MELT_NEW_COINS,
                                     struct TALER_DenominationPublicKey);
  for (cnt=0; cnt < MELT_NEW_COINS; cnt++)
  {
    new_dkp[cnt] = create_denom_key_pair (1024,
                                          session,
                                          &value,
                                          &fee_withdraw,
                                          &fee_deposit,
                                          &fee_refresh,
					  &fee_refund);
    new_denom_pubs[cnt] = new_dkp[cnt]->pub;
  }
  FAILIF (GNUNET_OK !=
          plugin->insert_refresh_order (plugin->cls,
                                        session,
                                        &session_hash,
                                        MELT_NEW_COINS,
                                        new_denom_pubs));
  ret_denom_pubs = GNUNET_new_array (MELT_NEW_COINS,
                                     struct TALER_DenominationPublicKey);
  FAILIF (GNUNET_OK !=
          plugin->get_refresh_order (plugin->cls,
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
  FAILIF (GNUNET_OK !=
          test_refresh_commit_links (session,
                                     &refresh_session,
                                     &session_hash));

  /* checking 'get_melt_commitment' API */
  mc = plugin->get_melt_commitment (plugin->cls,
                                    session,
                                    &session_hash);
  FAILIF (NULL == mc);
  FAILIF (MELT_NEW_COINS != mc->num_newcoins);
  for (cnt=0; cnt < MELT_NEW_COINS; cnt++)
  {
    FAILIF (0 !=
            GNUNET_CRYPTO_rsa_public_key_cmp (new_dkp[cnt]->pub.rsa_public_key,
                                              mc->denom_pubs[cnt].rsa_public_key));
    for (i=0;i<TALER_CNC_KAPPA;i++)
    {
      FAILIF (0 !=
              commit_coin_cmp (&mc->commit_coins[i][cnt],
                               &commit_coins[i][cnt]));
    }
  }
  for (i=0;i<TALER_CNC_KAPPA;i++)
  {
    FAILIF (0 !=
            memcmp (&rclp[i],
                    &mc->commit_links[i],
                    sizeof (struct TALER_RefreshCommitLinkP)));
  }
  plugin->free_melt_commitment (plugin->cls,
                                mc);

  for (cnt=0; cnt < MELT_NEW_COINS; cnt++)
  {
    struct GNUNET_HashCode hc;

    RND_BLK (&hc);
    ev_sigs[cnt].rsa_signature
      = GNUNET_CRYPTO_rsa_sign_fdh (new_dkp[cnt]->priv.rsa_private_key,
                                    &hc);
    GNUNET_assert (NULL != ev_sigs[cnt].rsa_signature);
    FAILIF (GNUNET_OK !=
            plugin->insert_refresh_out (plugin->cls,
                                        session,
                                        &session_hash,
                                        cnt,
                                        &ev_sigs[cnt]));
  }

  ldl = plugin->get_link_data_list (plugin->cls,
                                    session,
                                    &session_hash);
  FAILIF (NULL == ldl);
  for (ldlp = ldl; NULL != ldlp; ldlp = ldlp->next)
  {
    struct TALER_RefreshLinkEncryptedP r1;
    struct TALER_RefreshLinkEncryptedP r2;
    int found;

    found = GNUNET_NO;
    for (cnt=0;cnt < MELT_NEW_COINS;cnt++)
    {
      r1 = commit_coins[MELT_NOREVEAL_INDEX][cnt].refresh_link;
      r2 = ldlp->link_data_enc;
      FAILIF (NULL == ldlp->ev_sig.rsa_signature);
      if ( (0 ==
            GNUNET_CRYPTO_rsa_public_key_cmp (ldlp->denom_pub.rsa_public_key,
                                              new_dkp[cnt]->pub.rsa_public_key)) &&
           (0 ==
            GNUNET_CRYPTO_rsa_signature_cmp (ldlp->ev_sig.rsa_signature,
                                             ev_sigs[cnt].rsa_signature)) &&
           (0 ==
            refresh_link_encrypted_cmp (&r1, &r2)) )
      {
        found = GNUNET_YES;
        break;
      }
    }
    FAILIF (GNUNET_NO == found);
  }
  plugin->free_link_data_list (plugin->cls,
                               ldl);

  {
    int ok;

    ok = GNUNET_NO;
    FAILIF (GNUNET_OK !=
            plugin->get_transfer (plugin->cls,
                                  session,
                                  &meltp->coin.coin_pub,
                                  &check_transfer_data,
                                  &ok));
    FAILIF (GNUNET_OK != ok);
  }

  ret = GNUNET_OK;
 drop:
  for (cnt=0;cnt<TALER_CNC_KAPPA;cnt++)
    if (NULL != commit_coins[cnt])
    {
      plugin->free_refresh_commit_coins (plugin->cls,
                                         MELT_NEW_COINS,
                                         commit_coins[cnt]);
      GNUNET_free (commit_coins[cnt]);
      commit_coins[cnt] = NULL;
    }
  if (NULL != dkp)
    destroy_denom_key_pair (dkp);
  GNUNET_CRYPTO_rsa_signature_free (meltp->coin.denom_sig.rsa_signature);
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
 * Here #deposit_cb() will store the row ID of the deposit.
 */
static unsigned long long deposit_rowid;


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
 * @param transaction_id unique transaction ID chosen by the merchant
 * @param h_contract hash of the contract between merchant and customer
 * @param wire_deadline by which the merchant adviced that he would like the
 *        wire transfer to be executed
 * @param wire wire details for the merchant, NULL from iterate_matching_deposits()
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR if deposit does
 *         not match our expectations
 */
static int
deposit_cb (void *cls,
            unsigned long long rowid,
            const struct TALER_MerchantPublicKeyP *merchant_pub,
            const struct TALER_CoinSpendPublicKeyP *coin_pub,
            const struct TALER_Amount *amount_with_fee,
            const struct TALER_Amount *deposit_fee,
            uint64_t transaction_id,
            const struct GNUNET_HashCode *h_contract,
            struct GNUNET_TIME_Absolute wire_deadline,
            const json_t *wire)
{
  struct TALER_EXCHANGEDB_Deposit *deposit = cls;
  struct GNUNET_HashCode h_wire;

  deposit_rowid = rowid;
  if (NULL != wire)
    TALER_JSON_hash (wire, &h_wire);
  if ( (0 != memcmp (merchant_pub,
                     &deposit->merchant_pub,
                     sizeof (struct TALER_MerchantPublicKeyP))) ||
       (0 != TALER_amount_cmp (amount_with_fee,
                               &deposit->amount_with_fee)) ||
       (0 != TALER_amount_cmp (deposit_fee,
                               &deposit->deposit_fee)) ||
       (0 != memcmp (h_contract,
                     &deposit->h_contract,
                     sizeof (struct GNUNET_HashCode))) ||
       (0 != memcmp (coin_pub,
                     &deposit->coin.coin_pub,
                     sizeof (struct TALER_CoinSpendPublicKeyP))) ||
       (transaction_id != deposit->transaction_id) ||
       ( (NULL != wire) &&
         (0 != memcmp (&h_wire,
                       &deposit->h_wire,
                       sizeof (struct GNUNET_HashCode))) ) )
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
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
  struct TALER_EXCHANGEDB_Refund refund;
  struct TALER_EXCHANGEDB_TransactionList *tl;
  struct TALER_EXCHANGEDB_TransactionList *tlp;
  struct TALER_WireTransferIdentifierRawP wtid;
  json_t *wire;
  json_t *just;
  json_t *sndr;
  unsigned int matched;
  const char * const json_wire_str =
      "{ \"type\":\"SEPA\", \
\"IBAN\":\"DE67830654080004822650\",                    \
\"name\":\"GNUnet e.V.\",                               \
\"bic\":\"GENODEF1SLR\",                                 \
\"wire_transfer_deadline\":\"1449930207000\",                                \
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
  sndr = json_loads ("{ \"account\":\"1\" }", 0, NULL);
  just = json_loads ("{ \"justification\":\"1\" }", 0, NULL);
  FAILIF (GNUNET_OK !=
          plugin->reserves_in_insert (plugin->cls,
                                      session,
                                      &reserve_pub,
                                      &value,
                                      GNUNET_TIME_absolute_get (),
                                      sndr,
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
				      sndr,
                                      just));
  json_decref (just);
  json_decref (sndr);
  FAILIF (GNUNET_OK !=
          check_reserve (session,
                         &reserve_pub,
                         value.value * 2,
                         value.fraction * 2,
                         value.currency));
  result = 5;
  dkp = create_denom_key_pair (1024, session,
                               &value,
                               &fee_withdraw,
                               &fee_deposit,
                               &fee_refresh,
			       &fee_refund);
  RND_BLK(&cbc.h_coin_envelope);
  RND_BLK(&cbc.reserve_sig);
  cbc.denom_pub = dkp->pub;
  cbc.sig.rsa_signature
    = GNUNET_CRYPTO_rsa_sign_fdh (dkp->priv.rsa_private_key,
                                  &cbc.h_coin_envelope);
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
  result = 6;
  FAILIF (GNUNET_OK !=
          GNUNET_CRYPTO_rsa_verify (&cbc.h_coin_envelope,
                                    cbc2.sig.rsa_signature,
                                    dkp->pub.rsa_public_key));
  result = 7;
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
      FAILIF (NULL == bt->sender_account_details);
      FAILIF (NULL == bt->transfer_details);
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
  wire = json_loads (json_wire_str, 0, NULL);
  TALER_JSON_hash (wire,
                   &deposit.h_wire);
  deposit.receiver_wire_account = wire;
  deposit.transaction_id =
      GNUNET_CRYPTO_random_u64 (GNUNET_CRYPTO_QUALITY_WEAK, UINT64_MAX);
  deposit.amount_with_fee = value;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (CURRENCY, &deposit.deposit_fee));
  result = 8;
  FAILIF (GNUNET_OK !=
          plugin->insert_deposit (plugin->cls,
                                  session, &deposit));
  FAILIF (GNUNET_YES !=
          plugin->have_deposit (plugin->cls,
                                session,
                                &deposit));
  result = 9;
  FAILIF (1 !=
          plugin->iterate_matching_deposits (plugin->cls,
                                             session,
                                             &deposit.h_wire,
                                             &deposit.merchant_pub,
                                             &deposit_cb, &deposit,
                                             2));

  FAILIF (1 !=
          plugin->get_ready_deposit (plugin->cls,
                                     session,
                                     &deposit_cb,
                                     &deposit));
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         session));
  FAILIF (GNUNET_OK !=
          plugin->mark_deposit_tiny (plugin->cls,
                                     session,
                                     deposit_rowid));
  FAILIF (0 !=
          plugin->get_ready_deposit (plugin->cls,
                                     session,
                                     &deposit_cb,
                                     &deposit));
  plugin->rollback (plugin->cls,
                    session);
  FAILIF (1 !=
          plugin->get_ready_deposit (plugin->cls,
                                     session,
                                     &deposit_cb,
                                     &deposit));
  FAILIF (GNUNET_OK !=
          plugin->start (plugin->cls,
                         session));
  FAILIF (GNUNET_NO !=
          plugin->test_deposit_done (plugin->cls,
                                     session,
                                     &deposit));
  FAILIF (GNUNET_OK !=
          plugin->mark_deposit_done (plugin->cls,
                                     session,
                                     deposit_rowid));
  FAILIF (GNUNET_OK !=
          plugin->commit (plugin->cls,
                          session));
  FAILIF (GNUNET_YES !=
          plugin->test_deposit_done (plugin->cls,
                                     session,
                                     &deposit));

  result = 10;
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


  /* test insert_refund! */
  refund.coin = deposit.coin;
  refund.merchant_pub = deposit.merchant_pub;
  RND_BLK (&refund.merchant_sig);
  refund.h_contract = deposit.h_contract;
  refund.transaction_id = deposit.transaction_id;
  refund.rtransaction_id = GNUNET_CRYPTO_random_u64 (GNUNET_CRYPTO_QUALITY_WEAK, UINT64_MAX);
  refund.refund_amount = deposit.amount_with_fee;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (CURRENCY, &refund.refund_fee));
  FAILIF (GNUNET_OK !=
          plugin->insert_refund (plugin->cls,
                                 session,
                                 &refund));

  tl = plugin->get_coin_transactions (plugin->cls,
                                      session,
                                      &refund.coin.coin_pub);
  GNUNET_assert (NULL != tl);
  matched = 0;
  for (tlp = tl; NULL != tlp; tlp = tlp->next)
  {
    switch (tlp->type)
    {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      {
        struct TALER_EXCHANGEDB_Deposit *have = tlp->details.deposit;

        FAILIF (0 != memcmp (&have->coin.coin_pub,
                             &deposit.coin.coin_pub,
                             sizeof (struct TALER_CoinSpendPublicKeyP)));
        /* Note: we're not comparing the denomination keys, as there is
           still the question of whether we should even bother exporting
           them here. */
        FAILIF (0 != memcmp (&have->csig,
                             &deposit.csig,
                             sizeof (struct TALER_CoinSpendSignatureP)));
        FAILIF (0 != memcmp (&have->merchant_pub,
                             &deposit.merchant_pub,
                             sizeof (struct TALER_MerchantPublicKeyP)));
        FAILIF (0 != memcmp (&have->h_contract,
                             &deposit.h_contract,
                             sizeof (struct GNUNET_HashCode)));
        FAILIF (0 != memcmp (&have->h_wire,
                             &deposit.h_wire,
                             sizeof (struct GNUNET_HashCode)));
        /* Note: not comparing 'wire', seems truly redundant and would be tricky */
        FAILIF (have->transaction_id != deposit.transaction_id);
        FAILIF (have->timestamp.abs_value_us != deposit.timestamp.abs_value_us);
        FAILIF (have->refund_deadline.abs_value_us != deposit.refund_deadline.abs_value_us);
        FAILIF (have->wire_deadline.abs_value_us != deposit.wire_deadline.abs_value_us);
        FAILIF (0 != TALER_amount_cmp (&have->amount_with_fee,
                                       &deposit.amount_with_fee));
        FAILIF (0 != TALER_amount_cmp (&have->deposit_fee,
                                       &deposit.deposit_fee));
        matched |= 1;
        break;
      }
#if 0
      /* this coin pub was actually never melted... */
    case TALER_EXCHANGEDB_TT_REFRESH_MELT:
      FAILIF (0 != memcmp (&melt,
                           &tlp->details.melt,
                           sizeof (struct TALER_EXCHANGEDB_RefreshMelt)));
      matched |= 2;
      break;
#endif
    case TALER_EXCHANGEDB_TT_REFUND:
      {
        struct TALER_EXCHANGEDB_Refund *have = tlp->details.refund;

        FAILIF (0 != memcmp (&have->coin.coin_pub,
                             &refund.coin.coin_pub,
                             sizeof (struct TALER_CoinSpendPublicKeyP)));
        /* Note: we're not comparing the denomination keys, as there is
           still the question of whether we should even bother exporting
           them here. */
        FAILIF (0 != memcmp (&have->merchant_pub,
                             &refund.merchant_pub,
                             sizeof (struct TALER_MerchantPublicKeyP)));
        FAILIF (0 != memcmp (&have->merchant_sig,
                             &refund.merchant_sig,
                             sizeof (struct TALER_MerchantSignatureP)));
        FAILIF (0 != memcmp (&have->h_contract,
                             &refund.h_contract,
                             sizeof (struct GNUNET_HashCode)));
        FAILIF (have->transaction_id != refund.transaction_id);
        FAILIF (have->rtransaction_id != refund.rtransaction_id);
        FAILIF (0 != TALER_amount_cmp (&have->refund_amount,
                                       &refund.refund_amount));
        FAILIF (0 != TALER_amount_cmp (&have->refund_fee,
                                       &refund.refund_fee));
        matched |= 4;
        break;
      }
    default:
      FAILIF (1);
      break;
    }
  }
  FAILIF (5 != matched);

  plugin->free_coin_transaction_list (plugin->cls,
                                      tl);

  FAILIF (GNUNET_OK != test_wire_prepare (session));

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
  GNUNET_break (GNUNET_OK ==
                plugin->drop_tables (plugin->cls));
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
                          "test-exchange-db-%s", plugin_name);
  (void) GNUNET_asprintf (&config_filename,
                          "%s.conf", testname);
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
  GNUNET_SCHEDULER_run (&run, cfg);
  GNUNET_CONFIGURATION_destroy (cfg);
  GNUNET_free (config_filename);
  GNUNET_free (testname);
  return result;
}
