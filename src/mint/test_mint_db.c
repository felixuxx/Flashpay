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
#include "plugin.h"

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
               struct GNUNET_CRYPTO_EddsaPublicKey *pub,
               uint32_t value,
               uint32_t fraction,
               const char *currency,
               uint64_t expiry)
{
  struct Reserve reserve;
  reserve.pub = pub;

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
  struct GNUNET_CRYPTO_rsa_PrivateKey *priv;
  struct GNUNET_CRYPTO_rsa_PublicKey *pub;
};


static struct DenomKeyPair *
create_denom_key_pair (unsigned int size)
{
  struct DenomKeyPair *dkp;

  dkp = GNUNET_new (struct DenomKeyPair);
  dkp->priv = GNUNET_CRYPTO_rsa_private_key_create (size);
  GNUNET_assert (NULL != dkp->priv);
  dkp->pub = GNUNET_CRYPTO_rsa_private_key_get_public (dkp->priv);
  return dkp;
}


static void
destroy_denon_key_pair (struct DenomKeyPair *dkp)
{
  GNUNET_CRYPTO_rsa_public_key_free (dkp->pub);
  GNUNET_CRYPTO_rsa_private_key_free (dkp->priv);
  GNUNET_free (dkp);
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
  struct GNUNET_CRYPTO_EddsaPublicKey reserve_pub;
  struct Reserve reserve;
  struct GNUNET_TIME_Absolute expiry;
  struct TALER_Amount amount;
  struct DenomKeyPair *dkp;
  struct GNUNET_HashCode h_blind;
  struct CollectableBlindcoin cbc;
  struct CollectableBlindcoin cbc2;
  struct ReserveHistory *rh;
  struct ReserveHistory *rh_head;
  struct BankTransfer *bt;
  struct CollectableBlindcoin *withdraw;
  struct Deposit deposit;
  struct Deposit deposit2;
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
  ZR_BLK (&cbc);
  ZR_BLK (&cbc2);
  if (GNUNET_OK !=
      TALER_MINT_plugin_load (cfg))
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
  reserve.pub = &reserve_pub;
  amount.value = 1;
  amount.fraction = 1;
  strcpy (amount.currency, CURRENCY);
  expiry = GNUNET_TIME_absolute_add (GNUNET_TIME_absolute_get (),
                                     GNUNET_TIME_UNIT_HOURS);
  result = 4;
  FAILIF (GNUNET_OK !=
          plugin->reserves_in_insert (plugin->cls,
                                      session,
                                      &reserve,
                                      &amount,
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
                                      &reserve,
                                      &amount,
                                      expiry));
  FAILIF (GNUNET_OK !=
          check_reserve (session,
                         &reserve_pub,
                         ++amount.value,
                         ++amount.fraction,
                         amount.currency,
                         expiry.abs_value_us));
  dkp = create_denom_key_pair (1024);
  RND_BLK(&h_blind);
  RND_BLK(&cbc.reserve_sig);
  cbc.denom_pub = dkp->pub;
  cbc.sig = GNUNET_CRYPTO_rsa_sign (dkp->priv, &h_blind, sizeof (h_blind));
  (void) memcpy (&cbc.reserve_pub,
                 &reserve_pub,
                 sizeof (reserve_pub));
  amount.value--;
  amount.fraction--;
  FAILIF (GNUNET_OK !=
          plugin->insert_collectable_blindcoin (plugin->cls,
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
          plugin->get_collectable_blindcoin (plugin->cls,
                                             session,
                                             &h_blind,
                                             &cbc2));
  FAILIF (NULL == cbc2.denom_pub);
  FAILIF (0 != memcmp (&cbc2.reserve_sig,
                       &cbc.reserve_sig,
                       sizeof (cbc2.reserve_sig)));
  FAILIF (0 != memcmp (&cbc2.reserve_pub,
                       &cbc.reserve_pub,
                       sizeof (cbc2.reserve_pub)));
  FAILIF (GNUNET_OK !=
          GNUNET_CRYPTO_rsa_verify (&h_blind,
                                    cbc2.sig,
                                    dkp->pub));
  rh = plugin->get_reserve_history (plugin->cls,
                                    session,
                                    &reserve_pub);
  FAILIF (NULL == rh);
  rh_head = rh;
  for (cnt=0; NULL != rh_head; rh_head=rh_head->next, cnt++)
  {
    switch (rh_head->type)
    {
    case TALER_MINT_DB_RO_BANK_TO_MINT:
      bt = rh_head->details.bank;
      FAILIF (0 != memcmp (&bt->reserve_pub,
                           &reserve_pub,
                           sizeof (reserve_pub)));
      FAILIF (1 != bt->amount.value);
      FAILIF (1 != bt->amount.fraction);
      FAILIF (0 != strcmp (CURRENCY, bt->amount.currency));
      FAILIF (NULL != bt->wire); /* FIXME: write wire details to db */
      break;
    case TALER_MINT_DB_RO_WITHDRAW_COIN:
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
  deposit.amount = amount;
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
    destroy_denon_key_pair (dkp);
  if (NULL != cbc.sig)
    GNUNET_CRYPTO_rsa_signature_free (cbc.sig);
  if (NULL != cbc2.denom_pub)
    GNUNET_CRYPTO_rsa_public_key_free (cbc2.denom_pub);
  if (NULL != cbc2.sig)
    GNUNET_CRYPTO_rsa_signature_free (cbc2.sig);
  dkp = NULL;
}


int
main (int argc,
      char *const argv[])
{
   static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_END
  };

   result = -1;
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
                          "test-mint-db",
                          "Test cases for mint database helper functions.",
                          options, &run, NULL))
    return 3;
  return result;
}
