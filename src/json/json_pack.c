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
TALER_JSON_pack_time_abs_nbo_human (const char *name,
                                    struct GNUNET_TIME_AbsoluteNBO at)
{
  return TALER_JSON_pack_time_abs_human (name,
                                         GNUNET_TIME_absolute_ntoh (at));
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_denom_pub (
  const char *name,
  const struct TALER_DenominationPublicKey *pk)
{
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
  };

  switch (pk->cipher)
  {
  case TALER_DENOMINATION_RSA:
    ps.object
      = GNUNET_JSON_PACK (
          GNUNET_JSON_pack_uint64 ("cipher",
                                   TALER_DENOMINATION_RSA),
          GNUNET_JSON_pack_uint64 ("age_mask",
                                   pk->age_mask.mask),
          GNUNET_JSON_pack_rsa_public_key ("rsa_public_key",
                                           pk->details.rsa_public_key));
    break;
  case TALER_DENOMINATION_CS:
    ps.object
      = GNUNET_JSON_PACK (
          GNUNET_JSON_pack_uint64 ("cipher",
                                   TALER_DENOMINATION_CS),
          GNUNET_JSON_pack_uint64 ("age_mask",
                                   pk->age_mask.mask),
          GNUNET_JSON_pack_data_varsize ("cs_public_key",
                                         &pk->details.cs_public_key,
                                         sizeof (pk->details.cs_public_key)));
    break;
  default:
    GNUNET_assert (0);
  }
  return ps;
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_denom_sig (
  const char *name,
  const struct TALER_DenominationSignature *sig)
{
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
  };

  switch (sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("cipher",
                               TALER_DENOMINATION_RSA),
      GNUNET_JSON_pack_rsa_signature ("rsa_signature",
                                      sig->details.rsa_signature));
    break;
  case TALER_DENOMINATION_CS:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("cipher",
                               TALER_DENOMINATION_CS),
      GNUNET_JSON_pack_data_auto ("cs_signature_r",
                                  &sig->details.cs_signature.r_point),
      GNUNET_JSON_pack_data_auto ("cs_signature_s",
                                  &sig->details.cs_signature.s_scalar));
    break;
  default:
    GNUNET_assert (0);
  }
  return ps;
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_exchange_withdraw_values (
  const char *name,
  const struct TALER_ExchangeWithdrawValues *ewv)
{
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
  };

  switch (ewv->cipher)
  {
  case TALER_DENOMINATION_RSA:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("cipher",
                               TALER_DENOMINATION_RSA));
    break;
  case TALER_DENOMINATION_CS:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("cipher",
                               TALER_DENOMINATION_CS),
      GNUNET_JSON_pack_data_varsize (
        "r_pub_0",
        &ewv->details.cs_values.r_pub_pair.r_pub[0],
        sizeof(struct GNUNET_CRYPTO_CsRPublic)),
      GNUNET_JSON_pack_data_varsize (
        "r_pub_1",
        &ewv->details.cs_values.r_pub_pair.r_pub[1],
        sizeof(struct GNUNET_CRYPTO_CsRPublic))
      );
    break;
  default:
    GNUNET_assert (0);
  }
  return ps;
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_blinded_denom_sig (
  const char *name,
  const struct TALER_BlindedDenominationSignature *sig)
{
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
  };

  switch (sig->cipher)
  {
  case TALER_DENOMINATION_RSA:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("cipher",
                               TALER_DENOMINATION_RSA),
      GNUNET_JSON_pack_rsa_signature ("blinded_rsa_signature",
                                      sig->details.blinded_rsa_signature));
    break;
  case TALER_DENOMINATION_CS:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("cipher",
                               TALER_DENOMINATION_CS),
      GNUNET_JSON_pack_uint64 ("b",
                               sig->details.blinded_cs_answer.b),
      GNUNET_JSON_pack_data_auto ("s",
                                  &sig->details.blinded_cs_answer.s_scalar));
    break;
  default:
    GNUNET_assert (0);
  }
  return ps;
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_blinded_planchet (
  const char *name,
  const struct TALER_BlindedPlanchet *blinded_planchet)
{
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
  };

  switch (blinded_planchet->cipher)
  {
  case TALER_DENOMINATION_RSA:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("cipher",
                               TALER_DENOMINATION_RSA),
      GNUNET_JSON_pack_data_varsize (
        "rsa_blinded_planchet",
        blinded_planchet->details.rsa_blinded_planchet.blinded_msg,
        blinded_planchet->details.rsa_blinded_planchet.blinded_msg_size));
    break;
  case TALER_DENOMINATION_CS:
    ps.object = GNUNET_JSON_PACK (
      GNUNET_JSON_pack_uint64 ("cipher",
                               TALER_DENOMINATION_CS),
      GNUNET_JSON_pack_data_auto (
        "cs_nonce",
        &blinded_planchet->details.cs_blinded_planchet.nonce),
      GNUNET_JSON_pack_data_auto (
        "cs_blinded_c0",
        &blinded_planchet->details.cs_blinded_planchet.c[0]),
      GNUNET_JSON_pack_data_auto (
        "cs_blinded_c1",
        &blinded_planchet->details.cs_blinded_planchet.c[1]));
    break;
  default:
    GNUNET_assert (0);
  }
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


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_amount_nbo (const char *name,
                            const struct TALER_AmountNBO *amount)
{
  struct GNUNET_JSON_PackSpec ps = {
    .field_name = name,
    .object = (NULL != amount)
              ? TALER_JSON_from_amount_nbo (amount)
              : NULL
  };

  return ps;
}


/* End of json/json_pack.c */
