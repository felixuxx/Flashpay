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
 * @brief Handle extensions (age-restriction, peer2peer)
 * @author Özgür Kesim
 */
#include "platform.h"
#include <gnunet/gnunet_json_lib.h>
#include "taler_dbevents.h"
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
 * @param extra unused
 * @param extra_size number of bytes in @a extra unused
 */
static void
extension_update_event_cb (void *cls,
                           const void *extra,
                           size_t extra_size)
{
  (void) cls;
  enum TALER_Extension_Type type;
  const struct TALER_Extension *extension;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received extensions update event\n");

  if (sizeof(enum TALER_Extension_Type) != extra_size)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Oops, incorrect size of extra for TALER_Extension_type\n");
    return;
  }

  type = *(enum TALER_Extension_Type *) extra;


  /* Get the corresponding extension */
  extension = TALER_extensions_get_by_type (type);
  if (NULL == extension)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Oops, unknown extension type: %d\n", type);
    return;
  }

  // Get the config from the database as string
  {
    char *config_str = NULL;
    enum GNUNET_DB_QueryStatus qs;
    json_error_t err;
    json_t *config;
    enum GNUNET_GenericReturnValue ret;

    qs = TEH_plugin->get_extension_config (TEH_plugin->cls,
                                           extension->name,
                                           &config_str);

    if (qs < 0)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Couldn't get extension config\n");
      GNUNET_break (0);
      return;
    }

    // No config found -> disable extension
    if (NULL == config_str)
    {
      extension->disable ((struct TALER_Extension *) extension);
      return;
    }

    // Parse the string as JSON
    config = json_loads (config_str, JSON_DECODE_ANY, &err);
    if (NULL == config)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to parse config for extension `%s' as JSON: %s (%s)\n",
                  extension->name,
                  err.text,
                  err.source);
      GNUNET_break (0);
      return;
    }

    // Call the parser for the extension
    ret = extension->load_json_config (
      (struct TALER_Extension *) extension,
      config);

    if (GNUNET_OK != ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Couldn't parse configuration for extension %s from the database",
                  extension->name);
      GNUNET_break (0);
    }
  }

  /* Special case age restriction: Update global flag and mask  */
  if (TALER_Extension_AgeRestriction == type)
  {
    TEH_age_mask.bits = 0;
    TEH_age_restriction_enabled =
      TALER_extensions_age_restriction_is_enabled ();
    if (TEH_age_restriction_enabled)
      TEH_age_mask = TALER_extensions_age_restriction_ageMask ();
  }
}


enum GNUNET_GenericReturnValue
TEH_extensions_init ()
{
  GNUNET_assert (GNUNET_OK ==
                 TALER_extension_age_restriction_register ());

  /* Set the event handler for updates */
  struct GNUNET_DB_EventHeaderP ev = {
    .size = htons (sizeof (ev)),
    .type = htons (TALER_DBEVENT_EXCHANGE_EXTENSIONS_UPDATED),
  };
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

  /* FIXME: shall we load the extensions from the config right away?
   * We do have to for now, as otherwise denominations with age restriction
   * will not have the age mask set right upon initial generation.
   */
  TALER_extensions_load_taler_config (TEH_cfg);

  /* Trigger the initial load of configuration from the db */
  for (const struct TALER_Extension *it = TALER_extensions_get_head ();
       NULL != it->next;
       it = it->next)
    extension_update_event_cb (NULL, &it->type, sizeof(it->type));

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


/* end of taler-exchange-httpd_extensions.c */
