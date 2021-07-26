/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

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
TALER_JSON_pack_time_abs (const char *name,
                          struct GNUNET_TIME_Absolute at)
{
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_TIME_round_abs (&at));
  return GNUNET_JSON_pack_time_abs (name,
                                    at);
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_time_abs_nbo (const char *name,
                              struct GNUNET_TIME_AbsoluteNBO at)
{
  return TALER_JSON_pack_time_abs (name,
                                   GNUNET_TIME_absolute_ntoh (at));
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_time_rel (const char *name,
                          struct GNUNET_TIME_Relative rt)
{
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_TIME_round_rel (&rt));
  return GNUNET_JSON_pack_time_rel (name,
                                    rt);
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_time_rel_nbo (const char *name,
                              struct GNUNET_TIME_RelativeNBO rt)
{
  return TALER_JSON_pack_time_rel (name,
                                   GNUNET_TIME_relative_ntoh (rt));
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_denomination_public_key (const char *name,
                                         const struct
                                         TALER_DenominationPublicKey *pk)
{
  return GNUNET_JSON_pack_rsa_public_key (name,
                                          pk->rsa_public_key);
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_denomination_signature (const char *name,
                                        const struct
                                        TALER_DenominationSignature *sig)
{
  return GNUNET_JSON_pack_rsa_signature (name,
                                         sig->rsa_signature);
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_amount (const char *name,
                        const struct TALER_Amount *amount)
{
  json_t *json;

  json = TALER_JSON_from_amount (amount);
  GNUNET_assert (NULL != json);
  return GNUNET_JSON_pack_object_steal (name,
                                        json);
}


struct GNUNET_JSON_PackSpec
TALER_JSON_pack_amount_nbo (const char *name,
                            const struct TALER_AmountNBO *amount)
{
  json_t *json;

  json = TALER_JSON_from_amount_nbo (amount);
  GNUNET_assert (NULL != json);
  return GNUNET_JSON_pack_object_steal (name,
                                        json);
}


/* End of json/json_pack.c */
