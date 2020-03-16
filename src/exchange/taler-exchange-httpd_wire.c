/*
  This file is part of TALER
  Copyright (C) 2015-2020 Taler Systems SA

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
 * @file taler-exchange-httpd_wire.c
 * @brief Handle /wire requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler-exchange-httpd_keystate.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_wire.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include <jansson.h>

/**
 * Cached JSON for /wire response.
 */
static json_t *wire_methods;

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
  if (0 !=
      json_object_set_new (wire_fee_object,
                           method,
                           fees))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Initialize account; checks if @a ai has /wire information, and if so,
 * adds the /wire information (if included) to our responses.
 *
 * @param cls pointer to `int` to set to #GNUNET_SYSERR on errors
 * @param ai details about the account we should load the wire details for
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

    {
      char *url;

      if (NULL == (url = TALER_JSON_wire_to_payto (wire_s)))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Wire response file `%s' malformed\n",
                    ai->wire_response_filename);
        json_decref (wire_s);
        *ret = GNUNET_SYSERR;
        return;
      }
      if (0 != strcasecmp (url,
                           ai->payto_uri))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "URL in wire response file `%s' does not match URL in configuration (%s vs %s)!\n",
                    ai->wire_response_filename,
                    url,
                    ai->payto_uri);
        json_decref (wire_s);
        GNUNET_free (url);
        *ret = GNUNET_SYSERR;
        return;
      }
      GNUNET_free (url);
    }
    /* Provide friendly error message if user forgot to sign wire response. */
    if (NULL == json_object_get (wire_s,
                                 "master_sig"))
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
    if (GNUNET_OK ==
        load_fee (ai->method))
    {
      GNUNET_assert (-1 !=
                     json_array_append_new (wire_accounts_array,
                                            wire_s));
    }
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Wire fees not specified for `%s'\n",
                  ai->method);
      *ret = GNUNET_SYSERR;
    }
  }
  else if (GNUNET_YES == ai->debit_enabled)
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
 * Convert fee structure to JSON result to be returned
 * as part of a /wire response.
 *
 * @param af fee structure to convert
 * @return NULL on error, otherwise json data structure for /wire.
 */
static json_t *
fees_to_json (struct TALER_EXCHANGEDB_AggregateFees *af)
{
  json_t *a;

  a = json_array ();
  if (NULL == a)
  {
    GNUNET_break (0); /* out of memory? */
    return NULL;
  }
  while (NULL != af)
  {
    if ( (GNUNET_NO == GNUNET_TIME_round_abs (&af->start_date)) ||
         (GNUNET_NO == GNUNET_TIME_round_abs (&af->end_date)) )
    {
      GNUNET_break (0); /* bad timestamps, should not happen */
      json_decref (a);
      return NULL;
    }
    if (0 !=
        json_array_append_new (a,
                               json_pack ("{s:o, s:o, s:o, s:o, s:o}",
                                          "wire_fee", TALER_JSON_from_amount (
                                            &af->wire_fee),
                                          "closing_fee",
                                          TALER_JSON_from_amount (
                                            &af->closing_fee),
                                          "start_date",
                                          GNUNET_JSON_from_time_abs (
                                            af->start_date),
                                          "end_date",
                                          GNUNET_JSON_from_time_abs (
                                            af->end_date),
                                          "sig", GNUNET_JSON_from_data_auto (
                                            &af->master_sig))))
    {
      GNUNET_break (0); /* out of memory? */
      json_decref (a);
      return NULL;
    }
    af = af->next;
  }
  return a;
}


/**
 * Obtain fee structure for @a method wire transfers.
 *
 * @param method method to load fees for
 * @return JSON object (to be freed by caller) with fee structure
 */
json_t *
TEH_WIRE_get_fees (const char *method)
{
  struct TALER_EXCHANGEDB_AggregateFees *af;
  struct GNUNET_TIME_Absolute now;

  af = TALER_EXCHANGEDB_fees_read (TEH_cfg,
                                   method);
  now = GNUNET_TIME_absolute_get ();
  while ( (NULL != af) &&
          (af->end_date.abs_value_us < now.abs_value_us) )
  {
    struct TALER_EXCHANGEDB_AggregateFees *n = af->next;

    GNUNET_free (af);
    af = n;
  }
  if (NULL == af)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to find current wire transfer fees for `%s' at time %s\n",
                method,
                GNUNET_STRINGS_absolute_time_to_string (now));
    return NULL;
  }
  {
    json_t *j;

    j = fees_to_json (af);
    TALER_EXCHANGEDB_fees_free (af);
    return j;
  }
}


/**
 * Handle a "/wire" request.
 *
 * @param rh context of the handler
 * @param connection the MHD connection to handle
 * @param args array of additional options (must be empty for this function)
 * @return MHD result code
  */
int
TEH_handler_wire (const struct TEH_RequestHandler *rh,
                  struct MHD_Connection *connection,
                  const char *const args[])
{
  (void) rh;
  (void) args;
  GNUNET_assert (NULL != wire_methods);
  return TALER_MHD_reply_json (connection,
                               wire_methods,
                               MHD_HTTP_OK);
}


/**
 * Initialize wire subsystem.
 *
 * @param cfg configuration to use
 * @return #GNUNET_OK on success, #GNUNET_SYSERR if we found no valid
 *         wire methods
 */
int
TEH_WIRE_init (const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  wire_accounts_array = json_array ();
  if (NULL == wire_accounts_array)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  wire_fee_object = json_object ();
  if (NULL == wire_fee_object)
  {
    GNUNET_break (0);
    TEH_WIRE_done ();
    return GNUNET_SYSERR;
  }
  {
    int ret;

    ret = GNUNET_OK;
    TALER_EXCHANGEDB_find_accounts (cfg,
                                    &load_account,
                                    &ret);
    if (GNUNET_OK != ret)
    {
      TEH_WIRE_done ();
      return GNUNET_SYSERR;
    }
  }
  if ( (0 == json_array_size (wire_accounts_array)) ||
       (0 == json_object_size (wire_fee_object)) )
  {
    TEH_WIRE_done ();
    return GNUNET_SYSERR;
  }
  wire_methods = json_pack ("{s:O, s:O, s:o}",
                            "accounts", wire_accounts_array,
                            "fees", wire_fee_object,
                            "master_public_key",
                            GNUNET_JSON_from_data_auto (
                              &TEH_master_public_key));
  if (NULL == wire_methods)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to find properly configured wire transfer method\n");
    TEH_WIRE_done ();
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Clean up wire subsystem.
 */
void
TEH_WIRE_done ()
{
  if (NULL != wire_methods)
  {
    json_decref (wire_methods);
    wire_methods = NULL;
  }
  if (NULL != wire_fee_object)
  {
    json_decref (wire_fee_object);
    wire_fee_object = NULL;
  }
  if (NULL != wire_accounts_array)
  {
    json_decref (wire_accounts_array);
    wire_accounts_array = NULL;
  }
}


/* end of taler-exchange-httpd_wire.c */
