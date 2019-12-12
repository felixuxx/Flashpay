/*
  This file is part of TALER
  Copyright (C) 2016, 2017, 2018 Taler Systems SA

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
#include "taler_wire_lib.h"


/**
 * Information we keep for each plugin.
 */
struct Plugin
{

  /**
   * We keep plugins in a DLL.
   */
  struct Plugin *next;

  /**
   * We keep plugins in a DLL.
   */
  struct Plugin *prev;

  /**
   * Pointer to the plugin.
   */
  struct TALER_WIRE_Plugin *plugin;

};


/**
 * Head of DLL of wire plugins.
 */
static struct Plugin *wire_head;

/**
 * Tail of DLL of wire plugins.
 */
static struct Plugin *wire_tail;

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
    method = TALER_WIRE_payto_get_method (ai->payto_url);
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
                  "Wire fees not specified for `%s', ignoring plugin %s\n",
                  method,
                  ai->plugin_name);
      *ret = GNUNET_SYSERR;
    }
    GNUNET_free (method);
  }

  if (GNUNET_YES == ai->debit_enabled)
  {
    struct Plugin *p;

    p = GNUNET_new (struct Plugin);
    p->plugin = TALER_WIRE_plugin_load (cfg,
                                        ai->plugin_name);
    if (NULL == p->plugin)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to load plugin %s\n",
                  ai->plugin_name);
      GNUNET_free (p);
      *ret = GNUNET_SYSERR;
      return;
    }
    if (GNUNET_OK !=
        load_fee (p->plugin->method))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Disabling plugin `%s' as wire transfer fees for `%s' are not given correctly\n",
                  ai->plugin_name,
                  p->plugin->method);
      TALER_WIRE_plugin_unload (p->plugin);
      GNUNET_free (p);
      *ret = GNUNET_SYSERR;
      return;
    }
    GNUNET_CONTAINER_DLL_insert (wire_head,
                                 wire_tail,
                                 p);
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
  if (NULL == wire_head)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to find properly configured wire transfer method\n");
    ret = GNUNET_SYSERR;
  }
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
  struct Plugin *p;

  while (NULL != (p = wire_head))
  {
    GNUNET_CONTAINER_DLL_remove (wire_head,
                                 wire_tail,
                                 p);
    TALER_WIRE_plugin_unload (p->plugin);
    GNUNET_free (p);
  }
  json_decref (wire_fee_object);
  wire_fee_object = NULL;
  json_decref (wire_accounts_array);
  wire_accounts_array = NULL;
}


/**
 * Check if the given wire format JSON object is correctly formatted as
 * a wire address.
 *
 * @param wire the JSON wire format object
 * @param[out] emsg set to error message if we return an error code
 * @return #TALER_EC_NONE if correctly formatted; otherwise error code
 */
enum TALER_ErrorCode
TEH_json_validate_wireformat (const json_t *wire,
                              char **emsg)
{
  const char *payto_url;
  json_error_t error;
  char *method;

  *emsg = NULL;
  if (0 != json_unpack_ex ((json_t *) wire,
                           &error, 0,
                           "{s:s}",
                           "url", &payto_url))
  {
    GNUNET_asprintf (emsg,
                     "No `url' specified in the wire details\n");
    return TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_TYPE_MISSING;
  }
  method = TALER_WIRE_payto_get_method (payto_url);
  if (NULL == method)
  {
    GNUNET_asprintf (emsg,
                     "Malformed payto URL `%s'\n",
                     payto_url);
    return TALER_EC_PAYTO_MALFORMED;
  }
  for (struct Plugin *p = wire_head; NULL != p; p = p->next)
  {
    if (0 == strcasecmp (p->plugin->method,
                         method))
    {
      enum TALER_ErrorCode ec;

      GNUNET_free (method);
      ec = p->plugin->wire_validate (p->plugin->cls,
                                     payto_url);
      if (TALER_EC_NONE != ec)
        GNUNET_asprintf (emsg,
                         "Payto URL `%s' rejected by plugin\n",
                         payto_url);
      return ec;
    }
  }
  GNUNET_asprintf (emsg,
                   "Wire format type `%s' is not supported by this exchange\n",
                   method);
  GNUNET_free (method);
  return TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_TYPE_UNSUPPORTED;
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
