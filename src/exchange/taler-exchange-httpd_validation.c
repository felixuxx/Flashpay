/*
  This file is part of TALER
  Copyright (C) 2016 GNUnet e.V.

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
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
#include "taler_wire_lib.h"
#include "taler_wire_plugin.h"


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
 * Initialize validation subsystem.
 *
 * @param cfg configuration to use
 * @return #GNUNET_OK on success
 */
int
TMH_VALIDATION_init (const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct Plugin *p;
  char *wireformats;
  const char *token;

  /* Find out list of supported wire formats */
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "exchange",
                                             "wireformat",
                                             &wireformats))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "wireformat");
    return GNUNET_SYSERR;
  }
  for (token = strtok (wireformats,
                       " ");
       NULL != token;
       token = strtok (NULL,
                       " "))
  {
    p = GNUNET_new (struct Plugin);
    p->type = GNUNET_strdup (token);
    p->plugin = TALER_WIRE_plugin_load (cfg,
                                        token);
    if (NULL == p->plugin)
    {
      GNUNET_free (p);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to load plugin %s\n",
                  token);
      TMH_VALIDATION_done ();
      return GNUNET_SYSERR;
    }
    GNUNET_CONTAINER_DLL_insert (wire_head,
                                 wire_tail,
                                 p);
  }
  GNUNET_free (wireformats);
  return GNUNET_OK;
}


/**
 * Shutdown validation subsystem.
 */
void
TMH_VALIDATION_done ()
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
 * @return #GNUNET_YES if correctly formatted; #GNUNET_NO if not
 */
int
TMH_json_validate_wireformat (const json_t *wire,
                              int ours)
{
  const char *stype;
  json_error_t error;
  struct Plugin *p;

  if (0 != json_unpack_ex ((json_t *) wire,
                           &error, 0,
                           "{s:s}",
                           "type", &stype))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  for (p=wire_head; NULL != p; p = p->next)
    if (0 == strcasecmp (p->type,
                         stype))
      return p->plugin->wire_validate (p->plugin->cls,
                                       wire,
                                       (GNUNET_YES == ours)
                                       ? &TMH_master_public_key
                                       : NULL);
  return GNUNET_NO;
}


/**
 * Check if we support the given wire method.
 *
 * @param type type of wire method to check
 * @return #GNUNET_YES if the method is supported
 */
int
TMH_VALIDATION_test_method (const char *type)
{
  struct Plugin *p;

  for (p=wire_head;NULL != p;p = p->next)
    if (0 == strcasecmp (type,
                         p->type))
      return GNUNET_YES;
  return GNUNET_NO;
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
TMH_VALIDATION_get_wire_methods (const char *prefix)
{
  json_t *methods;
  json_t *method;
  struct Plugin *p;
  struct TALER_WIRE_Plugin *plugin;
  char *account_name;

  methods = json_object ();
  for (p=wire_head;NULL != p;p = p->next)
  {
    plugin = p->plugin;
    GNUNET_asprintf (&account_name,
                     "%s-%s",
                     prefix,
                     p->type);
    method = plugin->get_wire_details (plugin->cls,
                                       cfg,
                                       account_name);
    if (GNUNET_YES !=
        TMH_json_validate_wireformat (method,
                                      GNUNET_YES))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Account details for method `%s' ill-formed. Disabling method\n",
                  p->type);
      json_decref (method);
      method = NULL;
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
