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
 * @file taler-exchange-httpd_extensions.c
 * @brief Handle extensions (age-restriction, policy extensions)
 * @author Özgür Kesim
 */
#include "platform.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_extensions.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler_extensions.h"
#include <jansson.h>

/**
 * Handler listening for extensions updates by other exchange
 * services.
 */
static struct GNUNET_DB_EventHandler *extensions_eh;

/**
 * Function called whenever another exchange process has updated
 * the extensions data in the database.
 *
 * @param cls NULL
 * @param extra type of the extension
 * @param extra_size number of bytes in @a extra
 */
static void
extension_update_event_cb (void *cls,
                           const void *extra,
                           size_t extra_size)
{
  (void) cls;
  uint32_t nbo_type;
  enum TALER_Extension_Type type;
  const struct TALER_Extension *extension;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received extensions update event\n");

  if (sizeof(nbo_type) != extra_size)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Oops, incorrect size of extra for TALER_Extension_type\n");
    return;
  }

  GNUNET_assert (NULL != extra);

  nbo_type = *(uint32_t *) extra;
  type = (enum TALER_Extension_Type) ntohl (nbo_type);

  /* Get the corresponding extension */
  extension = TALER_extensions_get_by_type (type);
  if (NULL == extension)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Oops, unknown extension type: %d\n", type);
    return;
  }

  // Get the manifest from the database as string
  {
    char *manifest_str = NULL;
    enum GNUNET_DB_QueryStatus qs;
    json_error_t err;
    json_t *manifest_js;
    enum GNUNET_GenericReturnValue ret;

    qs = TEH_plugin->get_extension_manifest (TEH_plugin->cls,
                                             extension->name,
                                             &manifest_str);

    if (qs < 0)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Couldn't get extension manifest\n");
      GNUNET_break (0);
      return;
    }

    // No config found -> disable extension
    if (NULL == manifest_str)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "No manifest found for extension %s, disabling it\n",
                  extension->name);
      extension->disable ((struct TALER_Extension *) extension);
      return;
    }

    // Parse the string as JSON
    manifest_js = json_loads (manifest_str, JSON_DECODE_ANY, &err);
    if (NULL == manifest_js)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to parse manifest for extension `%s' as JSON: %s (%s)\n",
                  extension->name,
                  err.text,
                  err.source);
      GNUNET_break (0);
      free (manifest_str);
      return;
    }

    // Call the parser for the extension
    ret = extension->load_config (
      json_object_get (manifest_js, "config"),
      (struct TALER_Extension *) extension);

    if (GNUNET_OK != ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Couldn't parse configuration for extension %s from the manifest in the database: %s\n",
                  extension->name,
                  manifest_str);
      GNUNET_break (0);
    }

    free (manifest_str);
    json_decref (manifest_js);
  }

  /* Special case age restriction: Update global flag and mask  */
  if (TALER_Extension_AgeRestriction == type)
  {
    const struct TALER_AgeRestrictionConfig *conf =
      TALER_extensions_get_age_restriction_config ();
    TEH_age_restriction_enabled = false;
    if (NULL != conf)
    {
      TEH_age_restriction_enabled = true;
      TEH_age_restriction_config = *conf;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "[age restriction] DB event has changed the config to %s with mask: %s\n",
                TEH_age_restriction_enabled ? "enabled": "DISABLED",
                TALER_age_mask_to_string (&conf->mask));

  }

  // Finally, call TEH_keys_update_states in order to refresh the cached
  // values.
  TEH_keys_update_states ();
}


enum GNUNET_GenericReturnValue
TEH_extensions_init ()
{
  /* Set the event handler for updates */
  struct GNUNET_DB_EventHeaderP ev = {
    .size = htons (sizeof (ev)),
    .type = htons (TALER_DBEVENT_EXCHANGE_EXTENSIONS_UPDATED),
  };

  /* Load the shared libraries first */
  if (GNUNET_OK !=
      TALER_extensions_init (TEH_cfg))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "failed to load extensions");
    return GNUNET_SYSERR;
  }

  /* Check for age restriction */
  {
    const struct TALER_AgeRestrictionConfig *arc;

    if (NULL !=
        (arc = TALER_extensions_get_age_restriction_config ()))
      TEH_age_restriction_config = *arc;
  }

  extensions_eh = TEH_plugin->event_listen (TEH_plugin->cls,
                                            GNUNET_TIME_UNIT_FOREVER_REL,
                                            &ev,
                                            &extension_update_event_cb,
                                            NULL);
  if (NULL == extensions_eh)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }

  /* Trigger the initial load of configuration from the db */
  for (const struct TALER_Extensions *it = TALER_extensions_get_head ();
       NULL != it && NULL != it->extension;
       it = it->next)
  {
    const struct TALER_Extension *ext = it->extension;
    uint32_t typ = htonl (ext->type);
    char *manifest = json_dumps (ext->manifest (ext), JSON_COMPACT);

    TEH_plugin->set_extension_manifest (TEH_plugin->cls,
                                        ext->name,
                                        manifest);

    extension_update_event_cb (NULL,
                               &typ,
                               sizeof(typ));
    free (manifest);
  }

  return GNUNET_OK;
}


void
TEH_extensions_done ()
{
  if (NULL != extensions_eh)
  {
    TEH_plugin->event_listen_cancel (TEH_plugin->cls,
                                     extensions_eh);
    extensions_eh = NULL;
  }
}


/*
 * @brief Execute database transactions for /extensions/policy_* POST requests.
 *
 * @param cls a `struct TALER_PolicyFulfillmentOutcome`
 * @param connection MHD request context
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
policy_fulfillment_transaction (
  void *cls,
  struct MHD_Connection *connection,
  MHD_RESULT *mhd_ret)
{
  struct TALER_PolicyFulfillmentTransactionData *fulfillment = cls;

  return TEH_plugin->add_policy_fulfillment_proof (TEH_plugin->cls,
                                                   fulfillment);
}


MHD_RESULT
TEH_extensions_post_handler (
  struct TEH_RequestContext *rc,
  const json_t *root,
  const char *const args[])
{
  const struct TALER_Extension *ext = NULL;
  json_t *output;
  struct TALER_PolicyDetails *policy_details = NULL;
  size_t policy_details_count = 0;


  if (NULL == args[0])
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_EXCHANGE_GENERIC_OPERATION_UNKNOWN,
                                       "/extensions/$EXTENSION");
  }

  ext = TALER_extensions_get_by_name (args[0]);
  if (NULL == ext)
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_EXCHANGE_GENERIC_OPERATION_UNKNOWN,
                                       "/extensions/$EXTENSION unknown");
  }

  if (NULL == ext->policy_post_handler)
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_IMPLEMENTED,
                                       TALER_EC_EXCHANGE_GENERIC_OPERATION_UNKNOWN,
                                       "POST /extensions/$EXTENSION not supported");

  /*  Extract hash_codes and retrieve related policy_details from the DB */
  {
    enum GNUNET_GenericReturnValue ret;
    enum GNUNET_DB_QueryStatus qs;
    const char *error_msg;
    struct GNUNET_HashCode *hcs;
    size_t len;
    json_t*val;
    size_t idx;
    json_t *jhash_codes = json_object_get (root,
                                           "policy_hash_codes");
    if (! json_is_array (jhash_codes))
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_GENERIC_OPERATION_UNKNOWN,
                                         "policy_hash_codes are missing");

    len = json_array_size (jhash_codes);
    hcs = GNUNET_new_array (len,
                            struct GNUNET_HashCode);
    policy_details = GNUNET_new_array (len,
                                       struct TALER_PolicyDetails);

    json_array_foreach (jhash_codes, idx, val)
    {
      struct GNUNET_JSON_Specification spec[] = {
        GNUNET_JSON_spec_fixed_auto (NULL, &hcs[idx]),
        GNUNET_JSON_spec_end ()
      };

      ret = GNUNET_JSON_parse (val,
                               spec,
                               &error_msg,
                               NULL);
      if (GNUNET_OK != ret)
        break;

      qs = TEH_plugin->get_policy_details (TEH_plugin->cls,
                                           &hcs[idx],
                                           &policy_details[idx]);
      if (qs < 0)
      {
        error_msg = "a policy_hash_code couldn't be found";
        break;
      }
    }

    GNUNET_free (hcs);
    if (GNUNET_OK != ret)
    {
      GNUNET_free (policy_details);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_GENERIC_OPERATION_UNKNOWN,
                                         error_msg);
    }
  }


  {
    enum GNUNET_GenericReturnValue ret;

    ret = ext->policy_post_handler (root,
                                    &args[1],
                                    policy_details,
                                    policy_details_count,
                                    &output);

    if (GNUNET_OK != ret)
    {
      TALER_MHD_reply_json_steal (
        rc->connection,
        output,
        MHD_HTTP_BAD_REQUEST);
    }

    /* execute fulfillment transaction */
    {
      MHD_RESULT mhd_ret;
      struct TALER_PolicyFulfillmentTransactionData fulfillment = {
        .proof = root,
        .timestamp = GNUNET_TIME_timestamp_get (),
        .details = policy_details,
        .details_count = policy_details_count
      };

      if (GNUNET_OK !=
          TEH_DB_run_transaction (rc->connection,
                                  "execute policy fulfillment",
                                  TEH_MT_REQUEST_POLICY_FULFILLMENT,
                                  &mhd_ret,
                                  &policy_fulfillment_transaction,
                                  &fulfillment))
      {
        json_decref (output);
        return mhd_ret;
      }
    }
  }

  return TALER_MHD_reply_json_steal (rc->connection,
                                     output,
                                     MHD_HTTP_OK);
}


/* end of taler-exchange-httpd_extensions.c */
