/*
  This file is part of TALER
  Copyright (C) 2018, 2021, 2024 Taler Systems SA

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
 * @file json/json_wire.c
 * @brief helper functions to generate or check /wire replies
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_util.h"
#include "taler_json_lib.h"


enum GNUNET_GenericReturnValue
TALER_JSON_merchant_wire_signature_hash (const json_t *wire_s,
                                         struct TALER_MerchantWireHashP *hc)
{
  struct TALER_FullPayto payto_uri;
  struct TALER_WireSaltP salt;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_full_payto_uri ("payto_uri",
                                    &payto_uri),
    GNUNET_JSON_spec_fixed_auto ("salt",
                                 &salt),
    GNUNET_JSON_spec_end ()
  };

  if (GNUNET_OK !=
      GNUNET_JSON_parse (wire_s,
                         spec,
                         NULL, NULL))
  {
    GNUNET_break_op (0);
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Validating `%s'\n",
              payto_uri.full_payto);
  {
    char *err;

    err = TALER_payto_validate (payto_uri);
    if (NULL != err)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "URI `%s' ill-formed: %s\n",
                  payto_uri.full_payto,
                  err);
      GNUNET_free (err);
      return GNUNET_SYSERR;
    }
  }
  TALER_merchant_wire_signature_hash (payto_uri,
                                      &salt,
                                      hc);
  return GNUNET_OK;
}


struct TALER_FullPayto
TALER_JSON_wire_to_payto (const json_t *wire_s)
{
  json_t *payto_o;
  const char *payto_str;
  struct TALER_FullPayto payto = {
    NULL
  };
  char *err;

  payto_o = json_object_get (wire_s,
                             "payto_uri");
  if ( (NULL == payto_o) ||
       (NULL == (payto_str = json_string_value (payto_o))) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Malformed wire record encountered: lacks payto://-url\n");
    return payto;
  }
  payto.full_payto = GNUNET_strdup (payto_str);
  if (NULL !=
      (err = TALER_payto_validate (payto)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Malformed wire record encountered: payto URI `%s' invalid: %s\n",
                payto_str,
                err);
    GNUNET_free (payto.full_payto);
    GNUNET_free (err);
    return payto;
  }
  return payto;
}


char *
TALER_JSON_wire_to_method (const json_t *wire_s)
{
  json_t *payto_o;
  const char *payto_str;

  payto_o = json_object_get (wire_s,
                             "payto_uri");
  if ( (NULL == payto_o) ||
       (NULL == (payto_str = json_string_value (payto_o))) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Fatally malformed wire record encountered: lacks payto://-url\n");
    return NULL;
  }
  return TALER_payto_get_method (payto_str);
}


/* end of json_wire.c */
