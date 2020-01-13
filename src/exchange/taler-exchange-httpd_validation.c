/*
  This file is part of TALER
  Copyright (C) 2016-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/

/**
 * @file taler-exchange-httpd_validation.c
 * @brief helpers for calling the wire plugins to validate addresses
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler-exchange-httpd.h"
#include "taler-exchange-httpd_validation.h"
#include "taler-exchange-httpd_wire.h"
#include "taler_exchangedb_lib.h"
#include "taler_json_lib.h"


/**
 * Array of wire methods supported by this exchange.
 */
static json_t *wire_accounts_array;

/**
 * Object mapping wire methods to the respective fee structure.
 */
static json_t *wire_fee_object;


/**
 * Load wire fees for @a method.
 *
 * @param method wire method to load fee structure for
 * @return #GNUNET_OK on success
 */
static int
load_fee (const char *method)
{
  json_t *fees;

  if (NULL != json_object_get (wire_fee_object,
                               method))
    return GNUNET_OK; /* already have them */
  fees = TEH_WIRE_get_fees (method);
  if (NULL == fees)
    return GNUNET_SYSERR;
  /* Add fees to #wire_fee_object */
  GNUNET_assert (-1 !=
                 json_object_set_new (wire_fee_object,
                                      method,
                                      fees));
  return GNUNET_OK;
}


/**
 * Initialize account; checks if @ai has /wire information, and if so,
 * adds the /wire information (if included) to our responses. Also, if
 * the account is debitable, we try to load the plugin.
 *
 * @param cls pointer to `int` to set to #GNUNET_SYSERR on errors
 * @param name name of the plugin to load
 */
static void
load_account (void *cls,
              const struct TALER_EXCHANGEDB_AccountInfo *ai)
{
  int *ret = cls;

  if ( (NULL != ai->wire_response_filename) &&
       (GNUNET_YES == ai->credit_enabled) )
  {
    json_t *wire_s;
    json_error_t error;
    char *url;
    char *method;

    if (NULL == (wire_s = json_load_file (ai->wire_response_filename,
                                          JSON_REJECT_DUPLICATES,
                                          &error)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to parse `%s': %s at %d:%d (%d)\n",
                  ai->wire_response_filename,
                  error.text,
                  error.line,
                  error.column,
                  error.position);
      *ret = GNUNET_SYSERR;
      return;
    }
    if (NULL == (url = TALER_JSON_wire_to_payto (wire_s)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Wire response file `%s' lacks `url' entry\n",
                  ai->wire_response_filename);
      json_decref (wire_s);
      *ret = GNUNET_SYSERR;
      return;
    }
    if (0 != strcasecmp (url,
                         ai->payto_url))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "URL in Wire response file `%s' does not match URL in configuration!\n",
                  ai->wire_response_filename);
      json_decref (wire_s);
      GNUNET_free (url);
      *ret = GNUNET_SYSERR;
      return;
    }
    GNUNET_free (url);
    /* Provide friendly error message if user forgot to sign wire response. */
    if (NULL == json_object_get (wire_s, "master_sig"))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Wire response file `%s' has not been signed."
                  " Use taler-exchange-wire to sign it.\n",
                  ai->wire_response_filename);
      json_decref (wire_s);
      *ret = GNUNET_SYSERR;
      return;
    }
    if (GNUNET_OK !=
        TALER_JSON_exchange_wire_signature_check (wire_s,
                                                  &TEH_master_public_key))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Invalid signature in `%s' for public key `%s'\n",
                  ai->wire_response_filename,
                  GNUNET_p2s (&TEH_master_public_key.eddsa_pub));
      json_decref (wire_s);
      *ret = GNUNET_SYSERR;
      return;
    }
    method = TALER_payto_get_method (ai->payto_url);
    if (GNUNET_OK ==
        load_fee (method))
    {
      GNUNET_assert (-1 !=
                     json_array_append_new (wire_accounts_array,
                                            wire_s));
    }
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Wire fees not specified for `%s'\n",
                  method);
      *ret = GNUNET_SYSERR;
    }
    GNUNET_free (method);
  }

  if (GNUNET_YES == ai->debit_enabled)
  {
    if (GNUNET_OK !=
        load_fee (ai->method))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Wire transfer fees for `%s' are not given correctly\n",
                  ai->method);
      *ret = GNUNET_SYSERR;
      return;
    }
  }
}


/**
 * Initialize validation subsystem.
 *
 * @param cfg configuration to use
 * @return #GNUNET_OK on success
 */
int
TEH_VALIDATION_init (const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  int ret;

  ret = GNUNET_OK;
  wire_accounts_array = json_array ();
  wire_fee_object = json_object ();
  TALER_EXCHANGEDB_find_accounts (cfg,
                                  &load_account,
                                  &ret);
  if (GNUNET_OK != ret)
    TEH_VALIDATION_done ();
  return ret;
}


/**
 * Shutdown validation subsystem.
 */
void
TEH_VALIDATION_done ()
{
  json_decref (wire_fee_object);
  wire_fee_object = NULL;
  json_decref (wire_accounts_array);
  wire_accounts_array = NULL;
}


/**
 * Obtain JSON response for /wire
 *
 * @return JSON array with the supported validation methods, NULL on error
 */
json_t *
TEH_VALIDATION_get_wire_response ()
{
  if ( (0 == json_array_size (wire_accounts_array)) ||
       (0 == json_object_size (wire_fee_object)) )
    return NULL;
  return json_pack ("{s:O, s:O, s:o}",
                    "accounts", wire_accounts_array,
                    "fees", wire_fee_object,
                    "master_public_key", GNUNET_JSON_from_data_auto (
                      &TEH_master_public_key));
}


/* end of taler-exchange-httpd_validation.c */
