/*
  This file is part of TALER
  Copyright (C) 2018, 2021 Taler Systems SA

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
  const char *payto_uri;
  struct TALER_WireSaltP salt;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("payto_uri",
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
              payto_uri);
  {
    char *err;

    err = TALER_payto_validate (payto_uri);
    if (NULL != err)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "URI `%s' ill-formed: %s\n",
                  payto_uri,
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


enum GNUNET_GenericReturnValue
TALER_JSON_exchange_wire_signature_check (
  const json_t *wire_s,
  const struct TALER_MasterPublicKeyP *master_pub)
{
  const char *payto_uri;
  struct TALER_MasterSignatureP master_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("payto_uri",
                             &payto_uri),
    GNUNET_JSON_spec_fixed_auto ("master_sig",
                                 &master_sig),
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

  {
    char *err;

    err = TALER_payto_validate (payto_uri);
    if (NULL != err)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "URI `%s' ill-formed: %s\n",
                  payto_uri,
                  err);
      GNUNET_free (err);
      return GNUNET_SYSERR;
    }
  }

  return TALER_exchange_wire_signature_check (payto_uri,
                                              master_pub,
                                              &master_sig);
}


json_t *
TALER_JSON_exchange_wire_signature_make (
  const char *payto_uri,
  const struct TALER_MasterPrivateKeyP *master_priv)
{
  struct TALER_MasterSignatureP master_sig;
  char *err;

  if (NULL !=
      (err = TALER_payto_validate (payto_uri)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Invalid payto URI `%s': %s\n",
                payto_uri,
                err);
    GNUNET_free (err);
    return NULL;
  }
  TALER_exchange_wire_signature_make (payto_uri,
                                      master_priv,
                                      &master_sig);
  return GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("payto_uri",
                             payto_uri),
    GNUNET_JSON_pack_data_auto ("master_sig",
                                &master_sig));
}


char *
TALER_JSON_wire_to_payto (const json_t *wire_s)
{
  json_t *payto_o;
  const char *payto_str;
  char *err;

  payto_o = json_object_get (wire_s,
                             "payto_uri");
  if ( (NULL == payto_o) ||
       (NULL == (payto_str = json_string_value (payto_o))) )
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Malformed wire record encountered: lacks payto://-url\n");
    return NULL;
  }
  if (NULL !=
      (err = TALER_payto_validate (payto_str)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Malformed wire record encountered: payto URI `%s' invalid: %s\n",
                payto_str,
                err);
    GNUNET_free (err);
    return NULL;
  }
  return GNUNET_strdup (payto_str);
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
