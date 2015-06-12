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
 * @file mintdb/perf_taler_mintdb_init.c
 * @brief Interpreter library for mint database performance analysis
 * @author Nicolas Fournier
 */
#include "platform.h"
#include "perf_taler_mintdb_init.h"
#include <gnunet/gnunet_signatures.h>
#include "taler_signatures.h"
#include "taler_amount_lib.h"


#define CURRENCY "EUR"


/**
 * @return a randomly generated CollectableBlindcoin
 */
struct TALER_MINTDB_CollectableBlindcoin *
collectable_blindcoin_init ()
{
  struct GNUNET_CRYPTO_rsa_PrivateKey  *denomination_key;
  struct GNUNET_CRYPTO_EddsaPrivateKey *reserve_sig_key;
  // indent by 2 spaces
  struct TALER_MINTDB_CollectableBlindcoin *coin =
    GNUNET_new (struct TALER_MINTDB_CollectableBlindcoin);

  GNUNET_assert (NULL !=
    (reserve_sig_key = GNUNET_CRYPTO_eddsa_key_create ())
    );
  GNUNET_assert (NULL !=
    (denomination_key = GNUNET_CRYPTO_rsa_private_key_create (512))
    );
  GNUNET_assert (NULL ==
    (coin->denom_pub.rsa_public_key =
     GNUNET_CRYPTO_rsa_private_key_get_public (denomination_key))
    );

  GNUNET_CRYPTO_eddsa_key_get_public (reserve_sig_key,
    &coin->reserve_pub.eddsa_pub);

  GNUNET_assert (GNUNET_OK ==
    TALER_string_to_amount (CURRENCY ":1.1",
      &coin->amount_with_fee));

  GNUNET_assert (GNUNET_OK ==
    TALER_string_to_amount (CURRENCY ":1.1",
      &coin->withdraw_fee));



  uint32_t random_int =
    GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK, UINT32_MAX);
  GNUNET_assert (NULL !=
    (coin->sig.rsa_signature =
     GNUNET_CRYPTO_rsa_sign (denomination_key,
       &random_int,
       sizeof (random_int)
       ))
    );

  GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_WEAK,
    &coin->h_coin_envelope);

  struct {
    struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
    uint32_t data;
  } unsigned_data;

  unsigned_data.purpose.size = sizeof (unsigned_data);
  unsigned_data.purpose.purpose = GNUNET_SIGNATURE_PURPOSE_TEST;
  unsigned_data.data = random_int;

  GNUNET_assert (GNUNET_OK ==
    GNUNET_CRYPTO_eddsa_sign (reserve_sig_key,
      (struct GNUNET_CRYPTO_EccSignaturePurpose *) &unsigned_data,
      &coin->reserve_sig.eddsa_signature)
    );


  GNUNET_CRYPTO_eddsa_key_clear (reserve_sig_key);
  GNUNET_CRYPTO_rsa_private_key_free (denomination_key);
  return coin;
}

/**
 * Liberate memory of @a coin
 */
int
collectable_blindcoin_free (struct TALER_MINTDB_CollectableBlindcoin *coin)
{
  if (NULL == coin)
    return GNUNET_OK;
  GNUNET_CRYPTO_rsa_signature_free (coin->sig.rsa_signature);
  GNUNET_CRYPTO_rsa_public_key_free (coin->denom_pub.rsa_public_key);

  GNUNET_free (coin);

  return GNUNET_OK;
}


/**
 * @return a randomly generated reserve
 */
struct TALER_MINTDB_Reserve *
reserve_init ()
{
  struct TALER_MINTDB_Reserve *reserve ;

  GNUNET_assert (NULL !=
    (reserve = GNUNET_new (struct TALER_MINTDB_Reserve)
    ));

  struct GNUNET_CRYPTO_EddsaPrivateKey *reserve_priv ;

  GNUNET_assert (NULL !=
    (reserve_priv = GNUNET_CRYPTO_eddsa_key_create ()
    ));

  GNUNET_CRYPTO_eddsa_key_get_public (reserve_priv ,
    &reserve->pub.eddsa_pub);

  GNUNET_assert (GNUNET_OK ==
    TALER_string_to_amount (CURRENCY ":1.1", &reserve->balance)
    );

  reserve->expiry = GNUNET_TIME_absolute_get_forever_ ();

  GNUNET_CRYPTO_eddsa_key_clear (reserve_priv);
  return reserve;
}


/**
 * Free memory of a reserve
 */
int
reserve_free (struct TALER_MINTDB_Reserve *reserve)
{
  GNUNET_free (reserve);
  return GNUNET_OK;
}


/**
 * @return a randomly generated refresh session
 */
struct TALER_MINTDB_RefreshSession *
refresh_session_init ()
{
  struct TALER_MINTDB_RefreshSession *refresh_session;
  GNUNET_assert (NULL !=
    (refresh_session = GNUNET_new (struct TALER_MINTDB_RefreshSession)
    ));

  refresh_session->noreveal_index = 1;
  refresh_session->num_oldcoins = 1;
  refresh_session->num_newcoins = 1;

  return refresh_session;
}


/**
 * Free a refresh session
 */
int
refresh_session_free (struct TALER_MINTDB_RefreshSession *refresh_session)
{
  GNUNET_free (refresh_session);
  return GNUNET_OK;
}


/**
 * Create a randomly generated deposit
 */
struct TALER_MINTDB_Deposit *
deposit_init ()
{
  static int transaction_id = 0;
  struct TALER_MINTDB_Deposit *deposit;

  GNUNET_assert (NULL !=
    (deposit = GNUNET_new (struct TALER_MINTDB_Deposit)
    ));
  deposit-> transaction_id = transaction_id;
  GNUNET_assert (GNUNET_OK ==
    TALER_string_to_amount (CURRENCY ":1.1", &deposit->amount_with_fee)
    );

  GNUNET_assert (GNUNET_OK ==
    TALER_string_to_amount (CURRENCY ":0.1", &deposit->deposit_fee)
    );


  deposit->timestamp = GNUNET_TIME_absolute_get ();
  deposit->refund_deadline = GNUNET_TIME_absolute_get ();

  GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_WEAK,
    &deposit->h_contract);
  GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_WEAK,
    &deposit->h_wire);

  // Coin Spend Signature
  {
    struct u32_presign
    {
      struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
      uint32_t data;
    } unsigned_data;

    struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_prvt;
    GNUNET_assert (NULL !=
      (eddsa_prvt = GNUNET_CRYPTO_eddsa_key_create ()
      ));

    uint32_t random_int =
      GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK, UINT32_MAX);


    unsigned_data.purpose.size = htonl (sizeof (struct u32_presign));
    unsigned_data.purpose.purpose = htonl (GNUNET_SIGNATURE_PURPOSE_TEST);
    unsigned_data.data = random_int;

    GNUNET_assert (GNUNET_OK ==
      GNUNET_CRYPTO_eddsa_sign (eddsa_prvt,
                                &unsigned_data.purpose,
                                &deposit->csig.eddsa_signature));

    GNUNET_CRYPTO_eddsa_key_clear (eddsa_prvt);
  }

  printf("coin signed");
  // Merchant Key
  {
    struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_prv;
    GNUNET_assert(NULL !=
      (eddsa_prv = GNUNET_CRYPTO_eddsa_key_create ()
      ));

    GNUNET_CRYPTO_eddsa_key_get_public (
      eddsa_prv,
      &deposit->merchant_pub.eddsa_pub);


    GNUNET_CRYPTO_eddsa_key_clear (eddsa_prv);
  }

  printf("merchant ok");
  // Coin
  {
    {
      struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_prvt;
      GNUNET_assert (NULL !=
        (eddsa_prvt = GNUNET_CRYPTO_eddsa_key_create ()
        ));

      GNUNET_CRYPTO_eddsa_key_get_public (
        eddsa_prvt,
        &deposit->coin.coin_pub.eddsa_pub
        );


      GNUNET_CRYPTO_eddsa_key_clear (eddsa_prvt);
    }

    {
      struct GNUNET_CRYPTO_rsa_PrivateKey *rsa_prv;
      GNUNET_assert (NULL !=
        (rsa_prv = GNUNET_CRYPTO_rsa_private_key_create (128)
        ));

      GNUNET_assert (NULL !=
        (deposit->coin.denom_pub.rsa_public_key =
         GNUNET_CRYPTO_rsa_private_key_get_public (rsa_prv)
        ));

      GNUNET_assert (NULL !=
        (deposit->coin.denom_sig.rsa_signature =
         GNUNET_CRYPTO_rsa_sign (rsa_prv,
           (void *) &deposit->coin.coin_pub.eddsa_pub,
           sizeof (struct GNUNET_CRYPTO_EddsaPublicKey)
           )
        ));

      GNUNET_CRYPTO_rsa_private_key_free (rsa_prv);
    }
  }
  return deposit;
}


/**
 * Free memory of a deposit
 */
int
deposit_free (struct TALER_MINTDB_Deposit *deposit)
{
  if ( NULL == deposit)
    return GNUNET_OK;
  GNUNET_CRYPTO_rsa_public_key_free (deposit->coin.denom_pub.rsa_public_key);
  GNUNET_CRYPTO_rsa_signature_free (deposit->coin.denom_sig.rsa_signature);

  GNUNET_free (deposit);

  return GNUNET_OK;
}


/**
 * Generate a randomly generate DenominationKeyInformation
 */
struct TALER_MINTDB_DenominationKeyIssueInformation *
denomination_init ()
{
  struct TALER_MINTDB_DenominationKeyIssueInformation *dki;
  struct GNUNET_CRYPTO_EddsaPrivateKey *master_prvt;
  struct GNUNET_TIME_Absolute anchor;
  struct TALER_Amount amount;

  GNUNET_assert (NULL !=
    (dki = GNUNET_new (struct TALER_MINTDB_DenominationKeyIssueInformation)
    ));

  GNUNET_assert (NULL !=
    (dki->denom_priv.rsa_private_key
     = GNUNET_CRYPTO_rsa_private_key_create (128)
    ));
  GNUNET_assert (NULL !=
    (dki->denom_pub.rsa_public_key =
     GNUNET_CRYPTO_rsa_private_key_get_public (dki->denom_priv.rsa_private_key)
    ));

  GNUNET_CRYPTO_rsa_public_key_hash (dki->denom_pub.rsa_public_key,
    &dki->issue.denom_hash);

  GNUNET_assert (NULL !=
    (master_prvt = GNUNET_CRYPTO_eddsa_key_create ()
    ));


  GNUNET_CRYPTO_eddsa_key_get_public (master_prvt,
    &dki->issue.master.eddsa_pub);

  anchor = GNUNET_TIME_absolute_get ();

  dki->issue.start = GNUNET_TIME_absolute_hton (anchor);
  dki->issue.expire_withdraw =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (anchor,
        GNUNET_TIME_relative_get_hour_ ()));
  dki->issue.expire_spend =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (anchor,
        GNUNET_TIME_relative_get_hour_ ()));
  dki->issue.expire_legal =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (anchor,
        GNUNET_TIME_relative_get_hour_ ()));

  GNUNET_assert (GNUNET_OK ==
    TALER_string_to_amount (CURRENCY ":1.1", &amount)
    );

  TALER_amount_hton (&dki->issue.value, &amount);
  TALER_amount_hton (&dki->issue.fee_withdraw, &amount);
  TALER_amount_hton (&dki->issue.fee_deposit, &amount);
  TALER_amount_hton (&dki->issue.fee_refresh, &amount);
  dki->issue.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
  dki->issue.purpose.size =
    htonl (sizeof (struct TALER_MINTDB_DenominationKeyIssueInformation) -
      offsetof (struct TALER_MINTDB_DenominationKeyIssueInformation,
        issue.purpose));
  GNUNET_assert (GNUNET_OK ==
    GNUNET_CRYPTO_eddsa_sign (master_prvt,
      &dki->issue.purpose,
      &dki->issue.signature.eddsa_signature));

  GNUNET_CRYPTO_eddsa_key_clear (master_prvt);

  return dki;
}


/**
 * Free memory for a DenominationKeyIssueInformation
 */
int
denomination_free (struct TALER_MINTDB_DenominationKeyIssueInformation *dki)
{
  if (NULL ==dki)
    return GNUNET_OK;
  GNUNET_CRYPTO_rsa_private_key_free (dki->denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_free (dki->denom_pub.rsa_public_key);

  GNUNET_free (dki);

  return GNUNET_OK;
}
