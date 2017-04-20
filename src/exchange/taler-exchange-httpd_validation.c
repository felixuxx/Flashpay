/*
  This file is part of TALER
  Copyright (C) 2016, 2017 GNUnet e.V.

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
   * Type of the wireformat.
   */
  char *type;

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
 * Load plugin @a name.
 *
 * @param cls pointer to `int` to set to #GNUNET_SYSERR on errors
 * @param name name of the plugin to load
 */
static void
load_plugin (void *cls,
             const char *name)
{
  int *ret = cls;
  struct Plugin *p;
  json_t *fees;

  p = GNUNET_new (struct Plugin);
  p->type = GNUNET_strdup (name);
  p->plugin = TALER_WIRE_plugin_load (cfg,
                                      name);
  if (NULL == p->plugin)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to load plugin %s\n",
                name);
    GNUNET_free (p->type);
    GNUNET_free (p);
    *ret = GNUNET_SYSERR;
    return;
  }
  fees = TEH_WIRE_get_fees (name);
  if (NULL == fees)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Disabling method `%s' as wire transfer fees are not given correctly\n",
                name);
    GNUNET_free (p->type);
    GNUNET_free (p);
    *ret = GNUNET_SYSERR;
    return;
  }
  json_decref (fees);
  GNUNET_CONTAINER_DLL_insert (wire_head,
                               wire_tail,
                               p);
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
  TALER_WIRE_find_enabled (cfg,
                           &load_plugin,
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
    GNUNET_free (p->type);
    GNUNET_free (p);
  }
}


/**
 * Check if the given wire format JSON object is correctly formatted as
 * a wire address.
 *
 * @param wire the JSON wire format object
 * @param ours #GNUNET_YES if the signature should match our master key
 * @param[out] emsg set to error message if we return an error code
 * @return #TALER_EC_NONE if correctly formatted; otherwise error code
 */
enum TALER_ErrorCode
TEH_json_validate_wireformat (const json_t *wire,
                              int ours,
                              char **emsg)
{
  const char *stype;
  json_error_t error;
  struct Plugin *p;

  *emsg = NULL;
  if (0 != json_unpack_ex ((json_t *) wire,
                           &error, 0,
                           "{s:s}",
                           "type", &stype))
  {
    GNUNET_asprintf (emsg,
                     "No `type' specified in the wire details\n");
    return TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_TYPE_MISSING;
  }
  for (p=wire_head; NULL != p; p = p->next)
    if (0 == strcasecmp (p->type,
                         stype))
      return p->plugin->wire_validate (p->plugin->cls,
                                       wire,
                                       (GNUNET_YES == ours)
                                       ? &TEH_master_public_key
                                       : NULL,
                                       emsg);
  GNUNET_asprintf (emsg,
                   "Wire format type `%s' is not supported by this exchange\n",
                   stype);
  return TALER_EC_DEPOSIT_INVALID_WIRE_FORMAT_TYPE_UNSUPPORTED;
}


/**
 * Obtain JSON of the supported wire methods for a given
 * account name prefix.
 *
 * @param prefix prefix for the account, the suffix will
 *        be determined by the name of the plugin
 * @return JSON array with the supported validation methods
 */
json_t *
TEH_VALIDATION_get_wire_methods (const char *prefix)
{
  json_t *methods;
  char *account_name;
  char *emsg;
  enum TALER_ErrorCode ec;

  methods = json_object ();
  for (struct Plugin *p=wire_head;NULL != p;p = p->next)
  {
    struct TALER_WIRE_Plugin *plugin = p->plugin;
    json_t *method;
    json_t *fees;

    GNUNET_asprintf (&account_name,
                     "%s-%s",
                     prefix,
                     p->type);
    method = plugin->get_wire_details (plugin->cls,
                                       cfg,
                                       account_name);
    if (TALER_EC_NONE !=
        (ec = TEH_json_validate_wireformat (method,
                                            GNUNET_YES,
                                            &emsg)))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Disabling method `%s' as details are ill-formed: %s (%d)\n",
                  p->type,
                  emsg,
                  ec);
      GNUNET_free (emsg);
      json_decref (method);
      method = NULL;
    }
    fees = TEH_WIRE_get_fees (p->type);
    if (NULL == fees)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Disabling method `%s' as wire transfer fees are not given correctly\n",
                  p->type);
      json_decref (method);
      method = NULL;
    }
    else
    {
      json_object_set_new (method,
                           "fees",
                           fees);
    }

    if (NULL != method)
      json_object_set_new (methods,
                           p->type,
                           method);
    GNUNET_free (account_name);
  }
  return methods;
}


/* end of taler-exchange-httpd_validation.c */
