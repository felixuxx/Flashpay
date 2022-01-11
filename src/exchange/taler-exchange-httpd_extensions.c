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
 * @brief implements the TALER_Extension.parse_and_set_config interface.
 */
static enum GNUNET_GenericReturnValue
age_restriction_parse_and_set_config (struct TALER_Extension *this,
                                      const json_t *config)
{
  enum GNUNET_GenericReturnValue ret;
  struct TALER_AgeMask mask = {0};

  ret = TALER_agemask_parse_json (config, &mask);
  if (GNUNET_OK != ret)
    return ret;

  if (this != NULL && TALER_Extension_AgeRestriction == this->type)
  {
    if (NULL != this->config)
    {
      GNUNET_free (this->config);
    }
    this->config = GNUNET_malloc (sizeof(struct TALER_AgeMask));
    GNUNET_memcpy (this->config, &mask, sizeof(struct TALER_AgeMask));
  }

  return GNUNET_OK;
}


/**
 * @brief implements the TALER_Extension.test_config interface.
 */
static enum GNUNET_GenericReturnValue
age_restriction_test_config (const json_t *config)
{
  return age_restriction_parse_and_set_config (NULL, config);
}


/**
 * @brief implements the TALER_Extension.config_to_json interface.
 */
static json_t *
age_restriction_config_to_json (const struct TALER_Extension *this)
{
  const struct TALER_AgeMask *mask;
  if (NULL == this || TALER_Extension_AgeRestriction != this->type)
    return NULL;

  mask = (struct TALER_AgeMask *) this->config;
  json_t *config =  GNUNET_JSON_PACK (
    GNUNET_JSON_pack_string ("extension", this->name),
    GNUNET_JSON_pack_string ("mask",
                             TALER_age_mask_to_string (mask))
    );

  return config;
}


/* The extension for age restriction */
static struct TALER_Extension extension_age_restriction = {
  .type = TALER_Extension_AgeRestriction,
  .name = "age_restriction",
  .critical = false,
  .config = NULL,   // disabled per default
  .test_config = &age_restriction_test_config,
  .parse_and_set_config = &age_restriction_parse_and_set_config,
  .config_to_json = &age_restriction_config_to_json,
};

/* TODO: The extension for peer2peer */
static struct TALER_Extension extension_peer2peer = {
  .type = TALER_Extension_Peer2Peer,
  .name = "peer2peer",
  .critical = false,
  .config = NULL,   // disabled per default
  .test_config = NULL, // TODO
  .parse_and_set_config = NULL, // TODO
  .config_to_json = NULL, // TODO
};


/**
 * Create a list with the extensions for Age Restriction and Peer2Peer
 */
static struct TALER_Extension **
get_known_extensions ()
{

  struct TALER_Extension **list = GNUNET_new_array (
    TALER_Extension_MaxPredefined + 1,
    struct TALER_Extension *);
  list[TALER_Extension_AgeRestriction] = &extension_age_restriction;
  list[TALER_Extension_Peer2Peer] = &extension_peer2peer;
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
    char *config_str;
    enum GNUNET_DB_QueryStatus qs;
    struct TALER_Extension *extension;
    json_error_t err;
    json_t *config;
    enum GNUNET_GenericReturnValue ret;

    // TODO: make this a safe lookup
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
  TEH_extensions = get_known_extensions ();

  {
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


/* end of taler-exchange-httpd_extensions.c */
