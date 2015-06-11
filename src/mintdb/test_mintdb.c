/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

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
 * @file mint/test_mint_db.c
 * @brief test cases for DB interaction functions
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include "taler_mintdb_lib.h"
#include "taler_mintdb_plugin.h"

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

static struct TALER_MINTDB_Plugin *plugin;

/**
 * Checks if the given reserve has the given amount of balance and expiry
 *
 * @param session the database connection
 * @param pub the public key of the reserve
 * @param value balance value
 * @param fraction balance fraction
 * @param currency currency of the reserve
 * @param expiry expiration of the reserve
 * @return #GNUNET_OK if the given reserve has the same balance and expiration
 *           as the given parameters; #GNUNET_SYSERR if not
 */
static int
check_reserve (struct TALER_MINTDB_Session *session,
               const struct TALER_ReservePublicKeyP *pub,
               uint64_t value,
               uint32_t fraction,
               const char *currency,
               uint64_t expiry)
{
  struct TALER_MINTDB_Reserve reserve;

  reserve.pub = *pub;

  FAILIF (GNUNET_OK !=
          plugin->reserve_get (plugin->cls,
                               session,
                               &reserve));
  FAILIF (value != reserve.balance.value);
  FAILIF (fraction != reserve.balance.fraction);
  FAILIF (0 != strcmp (currency, reserve.balance.currency));
  FAILIF (expiry != reserve.expiry.abs_value_us);

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
 * Register a denomination in the DB.
 *
 * @param dkp the denomination key pair
 * @param session the DB session
 * @return #GNUNET_OK upon success; #GNUNET_SYSERR upon failure
 */
static int
register_denomination(struct TALER_DenominationPublicKey denom_pub,
                      struct TALER_MINTDB_Session *session)
{
  struct TALER_MINTDB_DenominationKeyIssueInformation dki;
  dki.denom_pub = denom_pub;
  dki.issue.start = GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_get ());
  dki.issue.expire_withdraw = GNUNET_TIME_absolute_hton
      (GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get (),
                                 GNUNET_TIME_UNIT_HOURS));
  dki.issue.expire_spend = GNUNET_TIME_absolute_hton
      (GNUNET_TIME_absolute_add
       (GNUNET_TIME_absolute_get (),
        GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_HOURS, 2)));
  dki.issue.expire_legal = GNUNET_TIME_absolute_hton
      (GNUNET_TIME_absolute_add
       (GNUNET_TIME_absolute_get (),
        GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_HOURS, 3)));
  dki.issue.value.value = GNUNET_htonll (1);
  dki.issue.value.fraction = htonl (100);
  (void) strcpy (dki.issue.value.currency, CURRENCY);
  dki.issue.fee_withdraw.value = 0;
  dki.issue.fee_withdraw.fraction = htonl (100);
  (void) strcpy (dki.issue.fee_withdraw.currency, CURRENCY);
  dki.issue.fee_deposit = dki.issue.fee_withdraw;
  dki.issue.fee_refresh = dki.issue.fee_withdraw;
  if (GNUNET_OK !=
      plugin->insert_denomination (plugin->cls,
                                   session,
                                   &dki))
  {
    GNUNET_break(0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Create a denominaiton key pair
 *
 * @param size the size of the denomination key
 * @param session the DB session
 * @return the denominaiton key pair; NULL upon error
 */
static struct DenomKeyPair *
create_denom_key_pair (unsigned int size, struct TALER_MINTDB_Session *session)
{
  struct DenomKeyPair *dkp;

  dkp = GNUNET_new (struct DenomKeyPair);
  dkp->priv.rsa_private_key = GNUNET_CRYPTO_rsa_private_key_create (size);
  GNUNET_assert (NULL != dkp->priv.rsa_private_key);
  dkp->pub.rsa_public_key
    = GNUNET_CRYPTO_rsa_private_key_get_public (dkp->priv.rsa_private_key);
  (void) register_denomination (dkp->pub, session);
  return dkp;
}


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
 * Tests on the known_coins relation
 *
 * @param session the DB session
 * @return #GNUNET_OK if the tests are successful; #GNUNET_SYSERR if not.
 */
static int
test_known_coins (struct TALER_MINTDB_Session *session)
{
  struct TALER_CoinPublicInfo coin_info;
  struct TALER_CoinPublicInfo ret_coin_info;
  struct DenomKeyPair *dkp;
  int ret = GNUNET_SYSERR;

  dkp = create_denom_key_pair (1024, session);
  RND_BLK (&coin_info);
  coin_info.denom_pub = dkp->pub;
  coin_info.denom_sig.rsa_signature =
      GNUNET_CRYPTO_rsa_sign (dkp->priv.rsa_private_key,
                              "foobar", 6);
  FAILIF (GNUNET_NO !=
          plugin->get_known_coin (plugin->cls,
                                  session,
                                  &coin_info.coin_pub,
                                  &ret_coin_info));
  FAILIF (GNUNET_OK !=
          plugin->insert_known_coin (plugin->cls,
                                     session,
                                     &coin_info));
  FAILIF (GNUNET_YES !=
          plugin->get_known_coin (plugin->cls,
                                  session,
                                  &coin_info.coin_pub,
                                  &ret_coin_info));
  FAILIF (0 != GNUNET_CRYPTO_rsa_public_key_cmp
          (ret_coin_info.denom_pub.rsa_public_key,
           coin_info.denom_pub.rsa_public_key));
  FAILIF (0 != GNUNET_CRYPTO_rsa_signature_cmp
          (ret_coin_info.denom_sig.rsa_signature,
           coin_info.denom_sig.rsa_signature));
  GNUNET_CRYPTO_rsa_public_key_free (ret_coin_info.denom_pub.rsa_public_key);
  GNUNET_CRYPTO_rsa_signature_free (ret_coin_info.denom_sig.rsa_signature);
  ret = GNUNET_OK;
 drop:
  destroy_denom_key_pair (dkp);
  GNUNET_CRYPTO_rsa_signature_free (coin_info.denom_sig.rsa_signature);
  return ret;
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
  struct TALER_MINTDB_Session *session;
  struct TALER_ReservePublicKeyP reserve_pub;
  struct GNUNET_TIME_Absolute expiry;
  struct TALER_Amount amount;
  struct DenomKeyPair *dkp;
  struct GNUNET_HashCode h_blind;
  struct TALER_MINTDB_CollectableBlindcoin cbc;
  struct TALER_MINTDB_CollectableBlindcoin cbc2;
  struct TALER_MINTDB_ReserveHistory *rh;
  struct TALER_MINTDB_ReserveHistory *rh_head;
  struct TALER_MINTDB_BankTransfer *bt;
  struct TALER_MINTDB_CollectableBlindcoin *withdraw;
  struct TALER_MINTDB_Deposit deposit;
  struct TALER_MINTDB_Deposit deposit2;
  struct json_t *wire;
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
      (plugin = TALER_MINTDB_plugin_load (cfg)))
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
  amount.value = 1;
  amount.fraction = 1;
  strcpy (amount.currency, CURRENCY);
  expiry = GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get (),
                                     GNUNET_TIME_UNIT_HOURS);
  result = 4;
  FAILIF (GNUNET_OK !=
          plugin->reserves_in_insert (plugin->cls,
                                      session,
                                      &reserve_pub,
                                      &amount,
				      "justification 1",
                                      expiry));
  FAILIF (GNUNET_OK !=
          check_reserve (session,
                         &reserve_pub,
                         amount.value,
                         amount.fraction,
                         amount.currency,
                         expiry.abs_value_us));
  FAILIF (GNUNET_OK !=
          plugin->reserves_in_insert (plugin->cls,
                                      session,
                                      &reserve_pub,
                                      &amount,
				      "justification 2",
                                      expiry));
  FAILIF (GNUNET_OK !=
          check_reserve (session,
                         &reserve_pub,
                         ++amount.value,
                         ++amount.fraction,
                         amount.currency,
                         expiry.abs_value_us));
  dkp = create_denom_key_pair (1024, session);
  RND_BLK(&h_blind);
  RND_BLK(&cbc.reserve_sig);
  cbc.denom_pub = dkp->pub;
  cbc.sig.rsa_signature
    = GNUNET_CRYPTO_rsa_sign (dkp->priv.rsa_private_key,
                              &h_blind,
                              sizeof (h_blind));
  (void) memcpy (&cbc.reserve_pub,
                 &reserve_pub,
                 sizeof (reserve_pub));
  amount.value--;
  amount.fraction--;
  FAILIF (GNUNET_OK !=
          plugin->insert_withdraw_info (plugin->cls,
                                                session,
                                                &h_blind,
                                                amount,
                                                &cbc));
  FAILIF (GNUNET_OK !=
          check_reserve (session,
                         &reserve_pub,
                         amount.value,
                         amount.fraction,
                         amount.currency,
                         expiry.abs_value_us));
  FAILIF (GNUNET_YES !=
          plugin->get_withdraw_info (plugin->cls,
                                             session,
                                             &h_blind,
                                             &cbc2));
  FAILIF (NULL == cbc2.denom_pub.rsa_public_key);
  FAILIF (0 != memcmp (&cbc2.reserve_sig,
                       &cbc.reserve_sig,
                       sizeof (cbc2.reserve_sig)));
  FAILIF (0 != memcmp (&cbc2.reserve_pub,
                       &cbc.reserve_pub,
                       sizeof (cbc2.reserve_pub)));
  FAILIF (GNUNET_OK !=
          GNUNET_CRYPTO_rsa_verify (&h_blind,
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
    case TALER_MINTDB_RO_BANK_TO_MINT:
      bt = rh_head->details.bank;
      FAILIF (0 != memcmp (&bt->reserve_pub,
                           &reserve_pub,
                           sizeof (reserve_pub)));
      FAILIF (1 != bt->amount.value);
      FAILIF (1 != bt->amount.fraction);
      FAILIF (0 != strcmp (CURRENCY, bt->amount.currency));
      FAILIF (NULL != bt->wire); /* FIXME: write wire details to db */
      break;
    case TALER_MINTDB_RO_WITHDRAW_COIN:
      withdraw = rh_head->details.withdraw;
      FAILIF (0 != memcmp (&withdraw->reserve_pub,
                           &reserve_pub,
                           sizeof (reserve_pub)));
      FAILIF (0 != memcmp (&withdraw->h_coin_envelope,
                           &h_blind, sizeof (h_blind)));
      break;
    }
  }
  FAILIF (3 != cnt);
  /* Tests for deposits */
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
  deposit.amount_with_fee = amount;
  FAILIF (GNUNET_OK !=
          plugin->insert_deposit (plugin->cls,
                                  session, &deposit));
  FAILIF (GNUNET_YES !=
          plugin->have_deposit (plugin->cls,
                                session,
                                &deposit));
  (void) memcpy (&deposit2,
                 &deposit,
                 sizeof (deposit));
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
  (void) memcpy (&deposit2.merchant_pub,
                 &deposit.merchant_pub,
                 sizeof (deposit.merchant_pub));
  RND_BLK (&deposit2.coin.coin_pub); /* should fail if coin is different */
  FAILIF (GNUNET_NO !=
          plugin->have_deposit (plugin->cls,
                                session,
                                &deposit2));
  /* Tests for refreshing */
  {
    struct TALER_MINTDB_RefreshSession refresh_session;
    struct TALER_MINTDB_RefreshSession ret_refresh_session;
    struct GNUNET_HashCode session_hash;
    RND_BLK (&refresh_session);
    RND_BLK (&session_hash);
    refresh_session.num_oldcoins = UINT16_MAX;
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
  }
  FAILIF (GNUNET_OK != test_known_coins (session));
  result = 0;

  /* FIXME: test_refresh_melts */
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
  TALER_MINTDB_plugin_unload (plugin);
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
     "test-mint-db-<plugin_name>", /* will be replaced later */
     "-c", "test-mint-db-<plugin_name>.conf", /* will be replaced later */
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
                           "test-mint-db-%s", plugin_name);
   (void) GNUNET_asprintf (&config_filename,
                           "%s.conf", testname);
   argv2[0] = argv[0];
   argv2[2] = config_filename;
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run ((sizeof (argv2)/sizeof (char *)) - 1, argv2,
                          testname,
                          "Test cases for mint database helper functions.",
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
