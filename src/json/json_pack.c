/*
  This file is part of TALER
  Copyright (C) 2021, 2022 Taler Systems SA

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
 * @file json/json_pack.c
 * @brief helper functions for JSON object packing
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_time_abs_human (const char *name,
                                struct GNUNET_TIME_Absolute at)
{
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
    .object = json_string (
      GNUNET_STRINGS_absolute_time_to_string (at))
  };

  return ps;
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_econtract (
  const char *name,
  const struct TALER_EncryptedContract *econtract)
{
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
  };

  if (NULL == econtract)
    return ps;
  ps.object
    = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_varsize ("econtract",
                                       econtract->econtract,
                                       econtract->econtract_size),
        GNUNET_JSON_pack_data_auto ("econtract_sig",
                                    &econtract->econtract_sig),
        GNUNET_JSON_pack_data_auto ("contract_pub",
                                    &econtract->contract_pub));
  return ps;
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_age_commitment (
  const char *name,
  const struct TALER_AgeCommitment *age_commitment)
{
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
  };
  json_t *keys;

  if (NULL == age_commitment ||
      0 == age_commitment->num)
    return ps;

  GNUNET_assert (NULL !=
                 (keys = json_array ()));

  for (size_t i = 0;
       i < age_commitment->num;
       i++)
  {
    json_t *val;
    val = GNUNET_JSON_from_data (&age_commitment->keys[i],
                                 sizeof(age_commitment->keys[i]));
    GNUNET_assert (NULL != val);
    GNUNET_assert (0 ==
                   json_array_append_new (keys, val));
  }

  ps.object = keys;
  return ps;
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_denom_pub (
  const char *name,
  const struct TALER_DenominationPublicKey *pk)
{
  const struct GNUNET_CRYPTO_BlindSignPublicKey *bsp;
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
  };

  if (NULL == pk)
    return ps;
  bsp = pk->bsign_pub_key;
  switch (bsp->cipher)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    break;
  case GNUNET_CRYPTO_BSA_RSA:
    ps.object
      = GNUNET_JSON_PACK (
          GNUNET_JSON_pack_string ("cipher",
                                   "RSA"),
          GNUNET_JSON_pack_uint64 ("age_mask",
                                   pk->age_mask.bits),
          GNUNET_JSON_pack_rsa_public_key ("rsa_public_key",
                                           bsp->details.rsa_public_key));
    return ps;
  case GNUNET_CRYPTO_BSA_CS:
    ps.object
      = GNUNET_JSON_PACK (
          GNUNET_JSON_pack_string ("cipher",
                                   "CS"),
          GNUNET_JSON_pack_uint64 ("age_mask",
                                   pk->age_mask.bits),
          GNUNET_JSON_pack_data_varsize ("cs_public_key",
                                         &bsp->details.cs_public_key,
                                         sizeof (bsp->details.cs_public_key)));
    return ps;
  }
  GNUNET_assert (0);
  return ps;
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_denom_sig (
  const char *name,
  const struct TALER_DenominationSignature *sig)
{
  const struct GNUNET_CRYPTO_UnblindedSignature *bs;
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
  };

  if (NULL == sig)
    return ps;
  bs = sig->unblinded_sig;
  switch (bs->cipher)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    break;
  case GNUNET_CRYPTO_BSA_RSA:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("cipher",
                               "RSA"),
      GNUNET_JSON_pack_rsa_signature ("rsa_signature",
                                      bs->details.rsa_signature));
    return ps;
  case GNUNET_CRYPTO_BSA_CS:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("cipher",
                               "CS"),
      GNUNET_JSON_pack_data_auto ("cs_signature_r",
                                  &bs->details.cs_signature.r_point),
      GNUNET_JSON_pack_data_auto ("cs_signature_s",
                                  &bs->details.cs_signature.s_scalar));
    return ps;
  }
  GNUNET_assert (0);
  return ps;
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_exchange_withdraw_values (
  const char *name,
  const struct TALER_ExchangeWithdrawValues *ewv)
{
  const struct GNUNET_CRYPTO_BlindingInputValues *biv;
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
  };

  if (NULL == ewv)
    return ps;
  biv = ewv->blinding_inputs;
  switch (biv->cipher)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    break;
  case GNUNET_CRYPTO_BSA_RSA:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("cipher",
                               "RSA"));
    return ps;
  case GNUNET_CRYPTO_BSA_CS:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("cipher",
                               "CS"),
      GNUNET_JSON_pack_data_varsize (
        "r_pub_0",
        &biv->details.cs_values.r_pub[0],
        sizeof(struct GNUNET_CRYPTO_CsRPublic)),
      GNUNET_JSON_pack_data_varsize (
        "r_pub_1",
        &biv->details.cs_values.r_pub[1],
        sizeof(struct GNUNET_CRYPTO_CsRPublic))
      );
    return ps;
  }
  GNUNET_assert (0);
  return ps;
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_blinded_denom_sig (
  const char *name,
  const struct TALER_BlindedDenominationSignature *sig)
{
  const struct GNUNET_CRYPTO_BlindedSignature *bs;
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
  };

  if (NULL == sig)
    return ps;
  bs = sig->blinded_sig;
  switch (bs->cipher)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    break;
  case GNUNET_CRYPTO_BSA_RSA:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("cipher",
                               "RSA"),
      GNUNET_JSON_pack_rsa_signature ("blinded_rsa_signature",
                                      bs->details.blinded_rsa_signature));
    return ps;
  case GNUNET_CRYPTO_BSA_CS:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("cipher",
                               "CS"),
      GNUNET_JSON_pack_uint64 ("b",
                               bs->details.blinded_cs_answer.b),
      GNUNET_JSON_pack_data_auto ("s",
                                  &bs->details.blinded_cs_answer.s_scalar));
    return ps;
  }
  GNUNET_assert (0);
  return ps;
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_blinded_planchet (
  const char *name,
  const struct TALER_BlindedPlanchet *blinded_planchet)
{
  const struct GNUNET_CRYPTO_BlindedMessage *bm;
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
  };

  if (NULL == blinded_planchet)
    return ps;
  bm = blinded_planchet->blinded_message;
  switch (bm->cipher)
  {
  case GNUNET_CRYPTO_BSA_INVALID:
    break;
  case GNUNET_CRYPTO_BSA_RSA:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("cipher",
                               "RSA"),
      GNUNET_JSON_pack_data_varsize (
        "rsa_blinded_planchet",
        bm->details.rsa_blinded_message.blinded_msg,
        bm->details.rsa_blinded_message.blinded_msg_size));
    return ps;
  case GNUNET_CRYPTO_BSA_CS:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_string ("cipher",
                               "CS"),
      GNUNET_JSON_pack_data_auto (
        "cs_nonce",
        &bm->details.cs_blinded_message.nonce),
      GNUNET_JSON_pack_data_auto (
        "cs_blinded_c0",
        &bm->details.cs_blinded_message.c[0]),
      GNUNET_JSON_pack_data_auto (
        "cs_blinded_c1",
        &bm->details.cs_blinded_message.c[1]));
    return ps;
  }
  GNUNET_assert (0);
  return ps;
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_amount (const char *name,
                        const struct TALER_Amount *amount)
{
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
    .object = (NULL != amount)
              ? TALER_JSON_from_amount (amount)
              : NULL
  };

  return ps;
}


/* End of json/json_pack.c */
