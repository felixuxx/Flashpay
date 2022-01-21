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
 * @brief implements the TALER_Extension.disable interface.
 */
void
age_restriction_disable (struct TALER_Extension *this)
{
  if (NULL == this)
    return;

  this->config = NULL;

  if (NULL != this->config_json)
  {
    json_decref (this->config_json);
    this->config_json = NULL;
  }
}


/**
 * @brief implements the TALER_Extension.parse_and_set_config interface.
 * @param this if NULL, only tests the configuration
 * @param config the configuration as json
 */
static enum GNUNET_GenericReturnValue
age_restriction_parse_and_set_config (struct TALER_Extension *this,
                                      json_t *config)
{
  struct TALER_AgeMask mask = {0};
  enum GNUNET_GenericReturnValue ret;

  ret = TALER_agemask_parse_json (config, &mask);
  if (GNUNET_OK != ret)
    return ret;

  /* only testing the parser */
  if (this == NULL)
    return GNUNET_OK;

  if (TALER_Extension_AgeRestriction != this->type)
    return GNUNET_SYSERR;

  if (NULL != this->config)
    GNUNET_free (this->config);

  this->config = GNUNET_malloc (sizeof(struct TALER_AgeMask));
  GNUNET_memcpy (this->config, &mask, sizeof(struct TALER_AgeMask));

  if (NULL != this->config_json)
    json_decref (this->config_json);

  this->config_json = config;

  return GNUNET_OK;
}


/**
 * @brief implements the TALER_Extension.test_config interface.
 */
static enum GNUNET_GenericReturnValue
age_restriction_test_config (const json_t *config)
{
  struct TALER_AgeMask mask = {0};

  return TALER_agemask_parse_json (config, &mask);
}


/* The extension for age restriction */
static struct TALER_Extension extension_age_restriction = {
  .type = TALER_Extension_AgeRestriction,
  .name = "age_restriction",
  .critical = false,
  .version = "1",
  .config = NULL,   // disabled per default
  .config_json = NULL,
  .disable = &age_restriction_disable,
  .test_config = &age_restriction_test_config,
  .parse_and_set_config = &age_restriction_parse_and_set_config,
};

/**
 * Create a list with the extensions for Age Restriction (and later Peer2Peer,
 * ...)
 */
static struct TALER_Extension **
get_known_extensions ()
{

  struct TALER_Extension **list = GNUNET_new_array (
    TALER_Extension_MaxPredefined + 1,
    struct TALER_Extension *);
  list[TALER_Extension_AgeRestriction] = &extension_age_restriction;
  list[TALER_Extension_MaxPredefined] = NULL;

  return list;
}


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
  /* TODO: This check will not work once we have plugable extensions */
  if (type <0 || type >= TALER_Extension_MaxPredefined)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Oops, incorrect type for TALER_Extension_type\n");
    return;
  }

  // Get the config from the database as string
  {
    char *config_str = NULL;
    enum GNUNET_DB_QueryStatus qs;
    struct TALER_Extension *extension;
    json_error_t err;
    json_t *config;
    enum GNUNET_GenericReturnValue ret;

    extension  = TEH_extensions[type];

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

    // No config found -> extension is disabled
    if (NULL == config_str)
    {
      extension->disable (extension);
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
    ret = extension->parse_and_set_config (extension, config);
    if (GNUNET_OK != ret)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Couldn't parse configuration for extension %s from the database",
                  extension->name);
      GNUNET_break (0);
    }
  }
}


enum GNUNET_GenericReturnValue
TEH_extensions_init ()
{
  /* Populate the known extensions. */
  TEH_extensions = get_known_extensions ();

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

  /* Trigger the initial load of configuration from the db */
  for (struct TALER_Extension **it = TEH_extensions; NULL != *it; it++)
    extension_update_event_cb (NULL, &(*it)->type, sizeof((*it)->type));

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
