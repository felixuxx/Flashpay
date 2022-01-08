/*
   This file is part of TALER
   Copyright (C) 2021 Taler Systems SA

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
 * @file taler-exchange-httpd_management_extensions.c
 * @brief Handle request to POST /management/extensions
 * @author Özgür Kesim
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_signatures.h"
#include "taler-exchange-httpd_management.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_extensions.h"
#include "taler_dbevents.h"


/**
 * Extension carries the necessary data for a particular extension.
 *
 */
struct Extension
{
  enum TALER_Extension_Type type;
  json_t *config;
};

/**
 * Closure for the #set_extensions transaction
 */
struct SetExtensionsContext
{
  uint32_t num_extensions;
  struct Extension *extensions;
  struct TALER_MasterSignatureP *extensions_sigs;
};


/**
 * @brief verifies the signature a configuration with the offline master key.
 *
 * @param config configuration of an extension given as JSON object
 * @param master_priv offline master public key of the exchange
 * @param[out] master_sig  signature
 * @return GNUNET_OK on success, GNUNET_SYSERR otherwise
 */
static enum GNUNET_GenericReturnValue
config_verify (
  const json_t *config,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_MasterSignatureP *master_sig
  )
{
  enum GNUNET_GenericReturnValue ret;
  struct TALER_ExtensionConfigHash h_config;

  ret = TALER_extension_config_hash (config, &h_config);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return ret;
  }

  return TALER_exchange_offline_extension_config_hash_verify (h_config,
                                                              master_pub,
                                                              master_sig);
}


/**
 * Function implementing database transaction to set the configuration of
 * extensions.  It runs the transaction logic.
 *  - IF it returns a non-error code, the transaction logic MUST NOT queue a
 *    MHD response.
 *  - IF it returns an hard error, the transaction logic MUST queue a MHD
 *    response and set @a mhd_ret.
 *  - IF it returns the soft error code, the function MAY be called again to
 *    retry and MUST not queue a MHD response.
 *
 * @param cls closure with a `struct SetExtensionsContext`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
set_extensions (void *cls,
                struct MHD_Connection *connection,
                MHD_RESULT *mhd_ret)
{
  struct SetExtensionsContext *sec = cls;

  /* save the configurations of all extensions */
  for (uint32_t i = 0; i<sec->num_extensions; i++)
  {
    struct Extension *ext = &sec->extensions[i];
    struct TALER_MasterSignatureP *sig = &sec->extensions_sigs[i];
    enum GNUNET_DB_QueryStatus qs;
    char *config;

    /* Sanity check.
     * TODO: replace with general API to retrieve the extension-handler
     */
    if (0 > ext->type || TALER_Extension_Max <= ext->type)
    {
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }

    config = json_dumps (ext->config, JSON_COMPACT | JSON_SORT_KEYS);
    if (NULL == config)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_JSON_INVALID,
                                             "convert configuration to string");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }

    qs = TEH_plugin->set_extension_config (
      TEH_plugin->cls,
      TEH_extensions[ext->type]->name,
      config,
      sig);

    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "save extension configuration");
    }

    /* Success, trigger event */
    {
      enum TALER_Extension_Type *type = &sec->extensions[i].type;
      struct GNUNET_DB_EventHeaderP ev = {
        .size = htons (sizeof (ev)),
        .type = htons (TALER_DBEVENT_EXCHANGE_EXTENSIONS_UPDATED)
      };
      TEH_plugin->event_notify (TEH_plugin->cls,
                                &ev,
                                type,
                                sizeof(*type));
    }

  }

  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT; /* only 'success', so >=0, matters here */
}


MHD_RESULT
TEH_handler_management_post_extensions (
  struct MHD_Connection *connection,
  const json_t *root)
{
  struct SetExtensionsContext sec = {0};
  json_t *extensions;
  json_t *extensions_sigs;
  struct GNUNET_JSON_Specification top_spec[] = {
    GNUNET_JSON_spec_json ("extensions",
                           &extensions),
    GNUNET_JSON_spec_json ("extensions_sigs",
                           &extensions_sigs),
    GNUNET_JSON_spec_end ()
  };
  MHD_RESULT ret;

  // Parse the top level json structure
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
                                     root,
                                     top_spec);
    if (GNUNET_SYSERR == res)
      return MHD_NO; /* hard failure */
    if (GNUNET_NO == res)
      return MHD_YES; /* failure */
  }

  // Ensure we have two arrays of the same size
  if (! (json_is_array (extensions) &&
         json_is_array (extensions_sigs)) )
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (top_spec);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      "array expected for extensions and extensions_sigs");
  }

  sec.num_extensions = json_array_size (extensions_sigs);
  if (json_array_size (extensions) != sec.num_extensions)
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (top_spec);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      "arrays extensions and extensions_sigs are not of the same size");
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received /management/extensions\n");

  sec.extensions = GNUNET_new_array (sec.num_extensions,
                                     struct Extension);
  sec.extensions_sigs = GNUNET_new_array (sec.num_extensions,
                                          struct TALER_MasterSignatureP);

  // Now parse individual extensions and signatures from those arrays.
  for (unsigned int i = 0; i<sec.num_extensions; i++)
  {
    // 1. parse the extension out of the json
    enum GNUNET_GenericReturnValue res;
    const struct TALER_Extension *extension;
    const char *name;
    struct GNUNET_JSON_Specification ext_spec[] = {
      GNUNET_JSON_spec_string ("extension",
                               &name),
      GNUNET_JSON_spec_json ("config",
                             &sec.extensions[i].config),
      GNUNET_JSON_spec_end ()
    };

    res = TALER_MHD_parse_json_array (connection,
                                      extensions,
                                      ext_spec,
                                      i,
                                      -1);
    if (GNUNET_SYSERR == res)
    {
      ret = MHD_NO; /* hard failure */
      goto CLEANUP;
    }
    if (GNUNET_NO == res)
    {
      ret = MHD_YES;
      goto CLEANUP;
    }

    /* 2. Make sure name refers to a supported extension */
    if (GNUNET_OK != TALER_extension_get_by_name (name,
                                                  (const struct
                                                   TALER_Extension **)
                                                  TEH_extensions,
                                                  &extension))
    {
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "invalid extension type");
      goto CLEANUP;
    }

    sec.extensions[i].type = extension->type;

    /* 3. Extract the signature out of the json array */
    {
      enum GNUNET_GenericReturnValue res;
      struct GNUNET_JSON_Specification sig_spec[] = {
        GNUNET_JSON_spec_fixed_auto (NULL,
                                     &sec.extensions_sigs[i]),
        GNUNET_JSON_spec_end ()
      };

      res = TALER_MHD_parse_json_array (connection,
                                        extensions_sigs,
                                        sig_spec,
                                        i,
                                        -1);
      if (GNUNET_SYSERR == res)
      {
        ret = MHD_NO; /* hard failure */
        goto CLEANUP;
      }
      if (GNUNET_NO == res)
      {
        ret = MHD_YES;
        goto CLEANUP;
      }
    }

    /* 4. Verify the signature of the config */
    if (GNUNET_OK != config_verify (
          sec.extensions[i].config,
          &TEH_master_public_key,
          &sec.extensions_sigs[i]))
    {
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "invalid signature for extension");
      goto CLEANUP;
    }

    /* 5. Make sure the config is sound */
    if (GNUNET_OK != extension->test_config (sec.extensions[i].config))
    {
      GNUNET_JSON_parse_free (ext_spec);
      ret = TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "invalid configuration for extension");
      goto CLEANUP;

    }

    /* We have a validly signed JSON object for the extension.
     * Increment its refcount and free the parser for the extension.
     */
    json_incref (sec.extensions[i].config);
    GNUNET_JSON_parse_free (ext_spec);

  } /* for-loop */

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received %u extensions\n",
              sec.num_extensions);

  // now run the transaction to persist the configurations
  {
    enum GNUNET_GenericReturnValue res;

    res = TEH_DB_run_transaction (connection,
                                  "set extensions",
                                  TEH_MT_OTHER,
                                  &ret,
                                  &set_extensions,
                                  &sec);

    if (GNUNET_SYSERR == res)
      goto CLEANUP;
  }

  ret = TALER_MHD_reply_static (
    connection,
    MHD_HTTP_NO_CONTENT,
    NULL,
    NULL,
    0);

CLEANUP:
  for (unsigned int i = 0; i < sec.num_extensions; i++)
  {
    if (NULL != sec.extensions[i].config)
    {
      json_decref (sec.extensions[i].config);
    }
  }
  GNUNET_free (sec.extensions);
  GNUNET_free (sec.extensions_sigs);
  GNUNET_JSON_parse_free (top_spec);
  return ret;
}


/* end of taler-exchange-httpd_management_management_post_extensions.c */
