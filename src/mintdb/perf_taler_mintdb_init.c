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
 * Generate a dummy DenominationKeyInformation for testing purposes
 * @return a dummy denomination key
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
                                     &dki->issue.properties.denom_hash);
  GNUNET_assert (NULL !=
                 (master_prvt = GNUNET_CRYPTO_eddsa_key_create ()));
  GNUNET_CRYPTO_eddsa_key_get_public (master_prvt,
                                      &dki->issue.properties.master.eddsa_pub);
  anchor = GNUNET_TIME_absolute_get ();
  dki->issue.properties.start = GNUNET_TIME_absolute_hton (anchor);
  dki->issue.properties.expire_withdraw =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (anchor,
                                                         GNUNET_TIME_relative_get_hour_ ()));
  dki->issue.properties.expire_spend =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (anchor,
                                                         GNUNET_TIME_relative_get_hour_ ()));
  dki->issue.properties.expire_legal =
    GNUNET_TIME_absolute_hton (GNUNET_TIME_absolute_add (anchor,
                                                         GNUNET_TIME_relative_get_hour_ ()));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (CURRENCY ":1.1", &amount));
  TALER_amount_hton (&dki->issue.properties.value, &amount);
  TALER_amount_hton (&dki->issue.properties.fee_withdraw, &amount);
  TALER_amount_hton (&dki->issue.properties.fee_deposit, &amount);
  TALER_amount_hton (&dki->issue.properties.fee_refresh, &amount);
  dki->issue.properties.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY);
  dki->issue.properties.purpose.size =
    htonl (sizeof (struct TALER_MINTDB_DenominationKeyIssueInformation));
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CRYPTO_eddsa_sign (master_prvt,
                                           &dki->issue.properties.purpose,
                                           &dki->issue.signature.eddsa_signature));
  GNUNET_free (master_prvt);

  return dki;
}


/**
 * Copies the given denomination
 * @param reserve the deposit copy
 * @return a copy of @a deposit; NULL if error
 */
struct TALER_MINTDB_DenominationKeyIssueInformation *
PERF_TALER_MINTDB_denomination_copy (const struct TALER_MINTDB_DenominationKeyIssueInformation *dki)
{
  struct TALER_MINTDB_DenominationKeyIssueInformation *copy;

  GNUNET_assert (NULL !=
                 (copy = GNUNET_new (struct TALER_MINTDB_DenominationKeyIssueInformation)));
  *copy = *dki;
  copy->denom_priv.rsa_private_key = 
    GNUNET_CRYPTO_rsa_private_key_dup (dki->denom_priv.rsa_private_key);
  GNUNET_assert (NULL !=
                 (copy->denom_pub.rsa_public_key = 
                  GNUNET_CRYPTO_rsa_public_key_dup (dki->denom_pub.rsa_public_key)));
  return copy;
}


/**
 * Free memory of a DenominationKeyIssueInformation
 * @param dki pointer to the struct to free
 */
int
PERF_TALER_MINTDB_denomination_free (struct TALER_MINTDB_DenominationKeyIssueInformation *dki)
{
  if (NULL ==dki)
    return GNUNET_OK;
  GNUNET_CRYPTO_rsa_private_key_free (dki->denom_priv.rsa_private_key);
  GNUNET_CRYPTO_rsa_public_key_free (dki->denom_pub.rsa_public_key);

  return GNUNET_OK;
}


/**
 * Generate a dummy reserve for testing
 * @return a reserve with 1000 EUR in it
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
                 TALER_string_to_amount (CURRENCY ":1000", &reserve->balance));
  reserve->expiry = GNUNET_TIME_absolute_get_forever_ ();
  GNUNET_free (reserve_priv);
  return reserve;
}


/**
 * Copies the given reserve
 * @param reserve the reserve to copy
 * @return a copy of @a reserve; NULL if error
 */
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
 * @param reserve pointer to the structure to be freed
 */
int
PERF_TALER_MINTDB_reserve_free (struct TALER_MINTDB_Reserve *reserve)
{
  if (NULL == reserve)
    return GNUNET_OK;
  return GNUNET_OK;
}


/**
 * Generate a dummy deposit for testing purposes
 * @param dki the denomination key used to sign the key
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


/**
 * Copies the given deposit
 * @param reserve the deposit copy
 * @return a copy of @a deposit; NULL if error
 */
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
 * @param deposit pointer to the structure to free
 */
int
PERF_TALER_MINTDB_deposit_free (struct TALER_MINTDB_Deposit *deposit)
{
  if ( NULL == deposit)
    return GNUNET_OK;
  GNUNET_CRYPTO_rsa_public_key_free (deposit->coin.denom_pub.rsa_public_key);
  GNUNET_CRYPTO_rsa_signature_free (deposit->coin.denom_sig.rsa_signature);
  json_decref (deposit->wire);

  return GNUNET_OK;
}


/**
 * Generate a CollectableBlindcoin for testing purpuses
 * @param dki denomination key used to sign the coin
 * @param reserve reserve providing the money for the coin
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
  {
    char *buffer = NULL;
    int size;
    GNUNET_assert (0 <
                   (size = GNUNET_CRYPTO_rsa_private_key_encode (
                       dki->denom_priv.rsa_private_key,
                       &buffer)));
    GNUNET_assert (NULL !=
                   (denomination_key = 
                    GNUNET_CRYPTO_rsa_private_key_decode (buffer, size)));
    GNUNET_free (buffer);
  }
  GNUNET_assert (NULL !=
                 (coin->denom_pub.rsa_public_key =
                  GNUNET_CRYPTO_rsa_private_key_get_public (denomination_key)));
  coin->reserve_pub.eddsa_pub = reserve->pub.eddsa_pub;
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
  char *buffer;
  GNUNET_CRYPTO_rsa_signature_encode (coin->sig.rsa_signature, &buffer);
  free (buffer);
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


/**
 * Copies the given coin
 * @param coin the coin to copy
 * @return a copy of coin; NULL if error
 */
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
 * @param coin pointer to the structure to free
 */
int
PERF_TALER_MINTDB_collectable_blindcoin_free (struct TALER_MINTDB_CollectableBlindcoin *coin)
{
  if (NULL == coin)
    return GNUNET_OK;

  GNUNET_CRYPTO_rsa_signature_free (coin->sig.rsa_signature);
  GNUNET_CRYPTO_rsa_public_key_free (coin->denom_pub.rsa_public_key);
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
 * @return #GNUNET_OK if the copy was successful, #GNUNET_SYSERR if it wasn't
 */
int
PERF_TALER_MINTDB_refresh_session_copy (struct TALER_MINTDB_RefreshSession *session, 
                                        struct TALER_MINTDB_RefreshSession *copy)
{
  *copy = *session;
  return GNUNET_OK;
}


/**
 * Free a refresh session
 */
int
PERF_TALER_MINTDB_refresh_session_free (struct TALER_MINTDB_RefreshSession *refresh_session)
{
  if (NULL == refresh_session)
    return GNUNET_OK;
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
  return GNUNET_OK;
}

/**
 * Create a melt operation
 *
 * @param session the refresh session 
 * @param dki the denomination the melted coin uses
 * @return a pointer to a #TALER_MINTDB_RefreshMelt 
 */
struct TALER_MINTDB_RefreshMelt *
PERF_TALER_MINTDB_refresh_melt_init (struct GNUNET_HashCode *session,
                                     struct TALER_MINTDB_DenominationKeyIssueInformation *dki)
{
  struct TALER_MINTDB_RefreshMelt *melt;
  struct GNUNET_CRYPTO_EddsaPrivateKey *coin_key;
  struct TALER_CoinPublicInfo cpi;
  struct TALER_CoinSpendSignatureP coin_spent;
  struct TALER_Amount amount;
  struct TALER_Amount amount_with_fee; 

  coin_key = GNUNET_CRYPTO_eddsa_key_create ();
  cpi.denom_pub = dki->denom_pub;
  GNUNET_CRYPTO_eddsa_key_get_public (coin_key, 
                                      &cpi.coin_pub.eddsa_pub);
  GNUNET_assert (NULL !=
                 (cpi.denom_sig.rsa_signature = 
                  GNUNET_CRYPTO_rsa_sign (dki->denom_priv.rsa_private_key,
                                          &cpi.coin_pub.eddsa_pub,
                                          sizeof (struct GNUNET_CRYPTO_EddsaPublicKey))));
  {
    struct 
    {
      struct GNUNET_CRYPTO_EccSignaturePurpose purpose;
      struct GNUNET_HashCode session;
    } to_sign;
    
    to_sign.purpose.purpose = GNUNET_SIGNATURE_PURPOSE_TEST; 
    to_sign.purpose.size = htonl (sizeof (to_sign));
    to_sign.session = *session; 
    GNUNET_CRYPTO_eddsa_sign (coin_key,
                              &to_sign.purpose,
                              &coin_spent.eddsa_signature);
  }
  GNUNET_assert (GNUNET_OK == TALER_string_to_amount (CURRENCY ":10.0",
                                                      &amount));
  GNUNET_assert (GNUNET_OK == TALER_string_to_amount (CURRENCY ":0.1",
                                                      &amount_with_fee));
  melt = GNUNET_new (struct TALER_MINTDB_RefreshMelt); 
  melt->coin = cpi;
  melt->coin_sig = coin_spent;
  melt->session_hash = *session;
  melt->amount_with_fee = amount;
  melt->melt_fee = amount_with_fee;

  GNUNET_free (coin_key);
  return melt;
}


/**
 * Copies the internals of a #TALER_MINTDB_RefreshMelt
 * 
 * @param melt the refresh melt to copy
 * @return an copy of @ melt
 */
struct TALER_MINTDB_RefreshMelt *
PERF_TALER_MINTDB_refresh_melt_copy (const struct TALER_MINTDB_RefreshMelt *melt)
{
  struct TALER_MINTDB_RefreshMelt *copy;

  copy = GNUNET_new (struct TALER_MINTDB_RefreshMelt);
  *copy = *melt;
  GNUNET_assert (NULL != 
                 (copy->coin.denom_sig.rsa_signature = 
                  GNUNET_CRYPTO_rsa_signature_dup (melt->coin.denom_sig.rsa_signature)));

  return copy;
}


/**
 * Free the internal memory of a #TALER_MINTDB_RefreshMelt
 *
 * @param melt the #TALER_MINTDB_RefreshMelt to free
 * @return #GNUNET_OK if the operation was successful, #GNUNET_SYSERROR
 */
int
PERF_TALER_MINTDB_refresh_melt_free (struct TALER_MINTDB_RefreshMelt *melt)
{
  GNUNET_CRYPTO_rsa_signature_free (melt->coin.denom_sig.rsa_signature);
  return GNUNET_OK;
}
