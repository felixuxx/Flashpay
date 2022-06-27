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
  struct TALER_MasterSignatureP extensions_sig;
};

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
    const struct TALER_Extension *taler_ext;
    enum GNUNET_DB_QueryStatus qs;
    char *config;

    taler_ext = TALER_extensions_get_by_type (ext->type);
    if (NULL == taler_ext)
    {
      /* No such extension found */
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }

    GNUNET_assert (NULL != ext->config);

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
      taler_ext->name,
      config);

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
      uint32_t nbo_type = htonl (sec->extensions[i].type);
      struct GNUNET_DB_EventHeaderP ev = {
        .size = htons (sizeof (ev)),
        .type = htons (TALER_DBEVENT_EXCHANGE_EXTENSIONS_UPDATED)
      };

      TEH_plugin->event_notify (TEH_plugin->cls,
                                &ev,
                                &nbo_type,
                                sizeof(nbo_type));
    }

  }

  /* All extensions configured, update the signature */
  TEH_extensions_sig = sec->extensions_sig;

  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT; /* only 'success', so >=0, matters here */
}


static enum GNUNET_GenericReturnValue
verify_extensions_from_json (
  json_t *extensions,
  struct SetExtensionsContext *sec)
{
  const char*name;
  const struct TALER_Extension *extension;
  size_t i = 0;
  json_t *blob;

  GNUNET_assert (NULL != extensions);
  GNUNET_assert (json_is_object (extensions));

  sec->num_extensions = json_object_size (extensions);
  sec->extensions = GNUNET_new_array (sec->num_extensions,
                                      struct Extension);

  json_object_foreach (extensions, name, blob)
  {
    int critical = 0;
    json_t *config;
    const char *version = NULL;

    /* load and verify criticality, version, etc. */
    extension = TALER_extensions_get_by_name (name);
    if (NULL == extension)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "no such extension: %s\n", name);
      return GNUNET_SYSERR;
    }

    if (GNUNET_OK !=
        TALER_extensions_is_json_config (
          blob, &critical, &version, &config))
      return GNUNET_SYSERR;

    if (critical != extension->critical
        || 0 != strcmp (version, extension->version) // TODO: libtool compare?
        || NULL == config
        || GNUNET_OK != extension->test_json_config (config))
      return GNUNET_SYSERR;

    sec->extensions[i].type = extension->type;
    sec->extensions[i].config = config;
  }

  return GNUNET_OK;
}


MHD_RESULT
TEH_handler_management_post_extensions (
  struct MHD_Connection *connection,
  const json_t *root)
{
  MHD_RESULT ret;
  json_t *extensions;
  struct SetExtensionsContext sec = {0};
  struct GNUNET_JSON_Specification top_spec[] = {
    GNUNET_JSON_spec_json ("extensions",
                           &extensions),
    GNUNET_JSON_spec_fixed_auto ("extensions_sig",
                                 &sec.extensions_sig),
    GNUNET_JSON_spec_end ()
  };

  /* Parse the top level json structure */
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

  /* Ensure we have an object */
  if (! json_is_object (extensions))
  {
    GNUNET_JSON_parse_free (top_spec);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      "invalid object");
  }

  /* Verify the signature */
  {
    struct TALER_ExtensionConfigHashP h_config;

    if (GNUNET_OK !=
        TALER_JSON_extensions_config_hash (extensions, &h_config) ||
        GNUNET_OK !=
        TALER_exchange_offline_extension_config_hash_verify (
          &h_config,
          &TEH_master_public_key,
          &sec.extensions_sig))
    {
      GNUNET_JSON_parse_free (top_spec);
      return TALER_MHD_reply_with_error (
        connection,
        MHD_HTTP_BAD_REQUEST,
        TALER_EC_GENERIC_PARAMETER_MALFORMED,
        "invalid signuture");
    }
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received /management/extensions\n");

  /* Now parse individual extensions and signatures from those objects. */
  if (GNUNET_OK !=
      verify_extensions_from_json (extensions, &sec))
  {
    GNUNET_JSON_parse_free (top_spec);
    return TALER_MHD_reply_with_error (
      connection,
      MHD_HTTP_BAD_REQUEST,
      TALER_EC_GENERIC_PARAMETER_MALFORMED,
      "invalid object");
  }

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received %u extensions\n",
              sec.num_extensions);

  /* now run the transaction to persist the configurations */
  {
    enum GNUNET_GenericReturnValue res;

    res = TEH_DB_run_transaction (connection,
                                  "set extensions",
                                  TEH_MT_REQUEST_OTHER,
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
  GNUNET_JSON_parse_free (top_spec);
  return ret;
}


/* end of taler-exchange-httpd_management_management_post_extensions.c */
