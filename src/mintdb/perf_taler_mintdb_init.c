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
#define PERF_TALER_MINTDB_RSA_SIZE 256


/**
 * @return a randomly generated CollectableBlindcoin
 */
struct TALER_MINTDB_CollectableBlindcoin *
PERF_TALER_MINTDB_collectable_blindcoin_init (
  const struct TALER_MINTDB_DenominationKeyIssueInformation *dki,
  const struct TALER_MINTDB_Reserve *reserve)
{
  uint32_t random_int;
  struct GNUNET_CRYPTO_rsa_PrivateKey  *denomination_key;
  struct GNUNET_CRYPTO_EddsaPrivateKey *reserve_sig_key;
  struct {
    struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
    uint32_t data;
  } unsigned_data;
  struct TALER_MINTDB_CollectableBlindcoin *coin;


  GNUNET_assert (NULL != 
    (coin = GNUNET_new (struct TALER_MINTDB_CollectableBlindcoin)));
  GNUNET_assert (NULL !=
                 (reserve_sig_key = GNUNET_CRYPTO_eddsa_key_create ()));
  GNUNET_assert (NULL !=
                 (denomination_key = GNUNET_CRYPTO_rsa_private_key_create (512)));
  GNUNET_assert (NULL !=
                 (coin->denom_pub.rsa_public_key =
                  GNUNET_CRYPTO_rsa_private_key_get_public (denomination_key)));
  GNUNET_CRYPTO_eddsa_key_get_public (reserve_sig_key,
                                      &coin->reserve_pub.eddsa_pub);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.1",
                                         &coin->amount_with_fee));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.1",
                                         &coin->withdraw_fee));
  random_int =
    GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK, UINT32_MAX);
  GNUNET_assert (NULL !=
                 (coin->sig.rsa_signature =
                  GNUNET_CRYPTO_rsa_sign (denomination_key,
                                          &random_int,
                                          sizeof (random_int))));
  GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_WEAK,
                                    &coin->h_coin_envelope);
  unsigned_data.purpose.size = htonl (sizeof (unsigned_data));
  unsigned_data.purpose.purpose = htonl (GNUNET_SIGNATURE_PURPOSE_TEST);
  unsigned_data.data = htonl (random_int);
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (reserve_sig_key,
                                           (struct GNUNET_CRYPTO_EccSignaturePurpose *) &unsigned_data,
                                           &coin->reserve_sig.eddsa_signature));
  GNUNET_free (reserve_sig_key);
  GNUNET_CRYPTO_rsa_private_key_free (denomination_key);
  return coin;
}


struct TALER_MINTDB_CollectableBlindcoin *
PERF_TALER_MINTDB_collectable_blindcoin_copy (const struct TALER_MINTDB_CollectableBlindcoin *coin)
{
  struct TALER_MINTDB_CollectableBlindcoin *copy;

  GNUNET_assert (NULL != 
    (copy = GNUNET_new (struct TALER_MINTDB_CollectableBlindcoin)));
  *copy = *coin;
  // No signature copy function found, Hacking it in
  {
    char *buffer = NULL;
    int size;
    GNUNET_assert (0 <
                   (size = GNUNET_CRYPTO_rsa_signature_encode (
                       coin->sig.rsa_signature,
                       &buffer)));
    GNUNET_assert (NULL !=
                   (copy->sig.rsa_signature = GNUNET_CRYPTO_rsa_signature_decode(
                       buffer,
                       size)));
    GNUNET_free (buffer);
  }
  GNUNET_assert (NULL !=
                 (copy->denom_pub.rsa_public_key = 
                  GNUNET_CRYPTO_rsa_public_key_dup (coin->denom_pub.rsa_public_key)));
  return copy;
}

/**
 * Liberate memory of @a coin
 */
int
PERF_TALER_MINTDB_collectable_blindcoin_free (struct TALER_MINTDB_CollectableBlindcoin *coin)
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
PERF_TALER_MINTDB_reserve_init ()
{
  struct TALER_MINTDB_Reserve *reserve;
  struct GNUNET_CRYPTO_EddsaPrivateKey *reserve_priv;

  GNUNET_assert (NULL !=
                 (reserve = GNUNET_new (struct TALER_MINTDB_Reserve)));
  GNUNET_assert (NULL !=
                 (reserve_priv = GNUNET_CRYPTO_eddsa_key_create ()));
  GNUNET_CRYPTO_eddsa_key_get_public (reserve_priv ,
                                      &reserve->pub.eddsa_pub);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.1", &reserve->balance));
  reserve->expiry = GNUNET_TIME_absolute_get_forever_ ();
  GNUNET_free (reserve_priv);
  return reserve;
}



struct TALER_MINTDB_Reserve *
PERF_TALER_MINTDB_reserve_copy (const struct TALER_MINTDB_Reserve *reserve)
{
  struct TALER_MINTDB_Reserve *copy;
  GNUNET_assert (NULL != (copy = GNUNET_new (struct TALER_MINTDB_Reserve)));
  *copy = *reserve;
  return copy;
} 

/**
 * Free memory of a reserve
 */
int
PERF_TALER_MINTDB_reserve_free (struct TALER_MINTDB_Reserve *reserve)
{
  if (NULL == reserve)
    return GNUNET_OK;
  GNUNET_free (reserve);
  return GNUNET_OK;
}


/**
 * @return a randomly generated refresh session
 */
struct TALER_MINTDB_RefreshSession *
PERF_TALER_MINTDB_refresh_session_init ()
{
  struct TALER_MINTDB_RefreshSession *refresh_session;

  GNUNET_assert (NULL !=
                 (refresh_session = GNUNET_new (struct TALER_MINTDB_RefreshSession)));
  refresh_session->noreveal_index = 1;
  refresh_session->num_oldcoins = 1;
  refresh_session->num_newcoins = 1;

  return refresh_session;
}


/**
 * Free a refresh session
 */
int
PERF_TALER_MINTDB_refresh_session_free (struct TALER_MINTDB_RefreshSession *refresh_session)
{
  GNUNET_free (refresh_session);
  return GNUNET_OK;
}


/**
 * Create a randomly generated deposit
 */
struct TALER_MINTDB_Deposit *
PERF_TALER_MINTDB_deposit_init (const struct TALER_MINTDB_DenominationKeyIssueInformation *dki)
{
  struct TALER_MINTDB_Deposit *deposit;
  struct TALER_CoinPublicInfo coin;
  struct TALER_CoinSpendSignatureP csig;
  struct TALER_MerchantPublicKeyP merchant_pub;
  struct GNUNET_HashCode h_contract;
  struct GNUNET_HashCode h_wire;
  const char wire[] = "{"
    "\"type\":\"SEPA\","
    "\"IBAN\":\"DE67830654080004822650\","
    "\"NAME\":\"GNUNET E.\","
    "\"BIC\":\"GENODEF1SRL\""
    "}";
  static uint64_t transaction_id = 0;
  struct GNUNET_TIME_Absolute timestamp;  
  struct GNUNET_TIME_Absolute refund_deadline;  
  struct TALER_Amount amount_with_fee;
  struct TALER_Amount deposit_fee;

  GNUNET_assert (NULL !=
                 (deposit = GNUNET_malloc (sizeof (struct TALER_MINTDB_Deposit) + sizeof (wire))));
  { // coin
    struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_prvt;

    GNUNET_assert (NULL !=
                   (eddsa_prvt = GNUNET_CRYPTO_eddsa_key_create ()));
    GNUNET_CRYPTO_eddsa_key_get_public (eddsa_prvt,
                                        &coin.coin_pub.eddsa_pub);    
    GNUNET_assert (NULL != 
                   (coin.denom_pub.rsa_public_key = 
                    GNUNET_CRYPTO_rsa_public_key_dup (dki->denom_pub.rsa_public_key)));
    GNUNET_assert (NULL !=
                   (coin.denom_sig.rsa_signature =
                    GNUNET_CRYPTO_rsa_sign (dki->denom_priv.rsa_private_key,
                                            &coin.coin_pub.eddsa_pub,
                                            sizeof (struct GNUNET_CRYPTO_EddsaPublicKey))));

    GNUNET_free (eddsa_prvt);
  }
  { //csig
    struct u32_presign
    {
      struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
      uint32_t data;
    } unsigned_data;
    struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_prvt;

    GNUNET_assert (NULL !=
                   (eddsa_prvt = GNUNET_CRYPTO_eddsa_key_create ()));
    unsigned_data.data = GNUNET_CRYPTO_random_u32 (GNUNET_CRYPTO_QUALITY_WEAK, 
                                                   UINT32_MAX);
    unsigned_data.purpose.size = htonl (sizeof (struct u32_presign));
    unsigned_data.purpose.purpose = htonl (GNUNET_SIGNATURE_PURPOSE_TEST);
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CRYPTO_eddsa_sign (eddsa_prvt,
                                             &unsigned_data.purpose,
                                             &csig.eddsa_signature));
    GNUNET_free (eddsa_prvt);
  }
  { //merchant_pub
    struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_prv;

    GNUNET_assert(NULL !=
                  (eddsa_prv = GNUNET_CRYPTO_eddsa_key_create ()));
    GNUNET_CRYPTO_eddsa_key_get_public (
                                        eddsa_prv,
                                        &merchant_pub.eddsa_pub);
    GNUNET_free (eddsa_prv);
  }
  GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_WEAK,
                                    &h_contract);
  GNUNET_CRYPTO_hash_create_random (GNUNET_CRYPTO_QUALITY_WEAK,
                                    &h_wire);
  timestamp = GNUNET_TIME_absolute_get ();
  refund_deadline = GNUNET_TIME_absolute_get ();
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.1", 
                                         &amount_with_fee));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":0.1", 
                                         &deposit_fee));
  deposit->coin = coin;
  deposit->csig = csig;
  deposit->h_contract = h_contract;
  deposit->h_wire = h_wire;
  deposit->wire = json_loads (wire, 0, NULL);
  deposit->transaction_id = transaction_id++;
  deposit->timestamp = timestamp;
  deposit->refund_deadline = refund_deadline;
  deposit->amount_with_fee = amount_with_fee;
  deposit->deposit_fee = deposit_fee;
  return deposit;
}


struct TALER_MINTDB_Deposit *
PERF_TALER_MINTDB_deposit_copy (const struct TALER_MINTDB_Deposit *deposit)
{
  struct TALER_MINTDB_Deposit *copy;

  GNUNET_assert (NULL != (copy = GNUNET_new (struct TALER_MINTDB_Deposit)));
  *copy = *deposit;
  json_incref (copy->wire);
  GNUNET_assert (NULL !=
                 (copy->coin.denom_pub.rsa_public_key = 
                  GNUNET_CRYPTO_rsa_public_key_dup (deposit->coin.denom_pub.rsa_public_key)));
  {
    char *buffer = NULL;
    int size;
    GNUNET_assert (0 <
                   (size = GNUNET_CRYPTO_rsa_signature_encode (
                       deposit->coin.denom_sig.rsa_signature,
                       &buffer)));
    GNUNET_assert (NULL !=
                   (copy->coin.denom_sig.rsa_signature = 
                    GNUNET_CRYPTO_rsa_signature_decode(buffer, size)));
    GNUNET_free (buffer);
  }
  return copy;
}


/**
 * Free memory of a deposit
 */
int
PERF_TALER_MINTDB_deposit_free (struct TALER_MINTDB_Deposit *deposit)
{
  if ( NULL == deposit)
    return GNUNET_OK;
  GNUNET_CRYPTO_rsa_public_key_free (deposit->coin.denom_pub.rsa_public_key);
  GNUNET_CRYPTO_rsa_signature_free (deposit->coin.denom_sig.rsa_signature);
  json_decref (deposit->wire);
  GNUNET_free (deposit);

  return GNUNET_OK;
}


/**
 * Generate a randomly generate DenominationKeyInformation
 */
struct TALER_MINTDB_DenominationKeyIssueInformation *
PERF_TALER_MINTDB_denomination_init ()
{
  struct TALER_MINTDB_DenominationKeyIssueInformation *dki;
  struct GNUNET_CRYPTO_EddsaPrivateKey *master_prvt;
  struct GNUNET_TIME_Absolute anchor;
  struct TALER_Amount amount;

  GNUNET_assert (NULL !=
                 (dki = GNUNET_new (struct TALER_MINTDB_DenominationKeyIssueInformation)));
  GNUNET_assert (NULL !=
                 (dki->denom_priv.rsa_private_key
                  = GNUNET_CRYPTO_rsa_private_key_create (PERF_TALER_MINTDB_RSA_SIZE)));
  GNUNET_assert (NULL !=
                 (dki->denom_pub.rsa_public_key =
                  GNUNET_CRYPTO_rsa_private_key_get_public (dki->denom_priv.rsa_private_key)));
  GNUNET_CRYPTO_rsa_public_key_hash (dki->denom_pub.rsa_public_key,
                                     &dki->issue.denom_hash);
  GNUNET_assert (NULL !=
                 (master_prvt = GNUNET_CRYPTO_eddsa_key_create ()));
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
                 TALER_string_to_amount (CURRENCY ":1.1", &amount));
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
  GNUNET_free (master_prvt);

  return dki;
}



struct TALER_MINTDB_DenominationKeyIssueInformation *
PERF_TALER_MINTDB_denomination_copy (const struct TALER_MINTDB_DenominationKeyIssueInformation *dki)
{
  struct TALER_MINTDB_DenominationKeyIssueInformation *copy;

  GNUNET_assert (NULL !=
                 (copy = GNUNET_new (struct TALER_MINTDB_DenominationKeyIssueInformation)));
  *copy = *dki;
  {
    char *buffer = NULL;
    int size;
    GNUNET_assert (0 <
                   (size = GNUNET_CRYPTO_rsa_private_key_encode (
                       dki->denom_priv.rsa_private_key,
                       &buffer)));
    GNUNET_assert (NULL !=
                   (copy->denom_priv.rsa_private_key = 
                    GNUNET_CRYPTO_rsa_private_key_decode(buffer, size)));
    GNUNET_free (buffer);
  }
  GNUNET_assert (NULL !=
                 (copy->denom_pub.rsa_public_key = 
                  GNUNET_CRYPTO_rsa_public_key_dup (dki->denom_pub.rsa_public_key)));
  return copy;
}


/**
 * Free memory for a DenominationKeyIssueInformation
 */
int
PERF_TALER_MINTDB_denomination_free (struct TALER_MINTDB_DenominationKeyIssueInformation *dki)
{
  if (NULL ==dki)
    return GNUNET_OK;
  GNUNET_CRYPTO_rsa_private_key_free (dki->denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_free (dki->denom_pub.rsa_public_key);
  GNUNET_free (dki);

  return GNUNET_OK;
}


/**
 * Generate a random CoinPublicInfo
 */
struct TALER_CoinPublicInfo *
PERF_TALER_MINTDB_coin_public_info_init ()
{
  struct GNUNET_CRYPTO_EddsaPrivateKey *coin_spent_prv;
  struct GNUNET_CRYPTO_rsa_PrivateKey *denom_prv;
  struct TALER_CoinPublicInfo *cpi;

  GNUNET_assert (NULL !=
                 (denom_prv = GNUNET_CRYPTO_rsa_private_key_create (PERF_TALER_MINTDB_RSA_SIZE)));
  GNUNET_assert (NULL != 
                 (coin_spent_prv = GNUNET_CRYPTO_eddsa_key_create ()));
  GNUNET_assert (NULL !=
                 (cpi = GNUNET_new (struct TALER_CoinPublicInfo)));
  GNUNET_CRYPTO_eddsa_key_get_public (coin_spent_prv, &cpi->coin_pub.eddsa_pub);
  GNUNET_assert (NULL !=
                 (cpi->denom_pub.rsa_public_key = GNUNET_CRYPTO_rsa_private_key_get_public (denom_prv)));
  GNUNET_assert (NULL !=
                 (cpi->denom_sig.rsa_signature = GNUNET_CRYPTO_rsa_sign (denom_prv, 
                                                                         &cpi->coin_pub, 
                                                                         sizeof (struct TALER_CoinSpendPublicKeyP)))); 
  GNUNET_free (coin_spent_prv);
  GNUNET_CRYPTO_rsa_private_key_free (denom_prv);
  return cpi;
}

/**
 * Free a CoinPublicInfo
 */
int
PERF_TALER_MINTDB_coin_public_info_free (struct TALER_CoinPublicInfo *cpi)
{
  GNUNET_CRYPTO_rsa_signature_free (cpi->denom_sig.rsa_signature);
  GNUNET_CRYPTO_rsa_public_key_free (cpi->denom_pub.rsa_public_key);
  GNUNET_free (cpi); 
  return GNUNET_OK;
}
