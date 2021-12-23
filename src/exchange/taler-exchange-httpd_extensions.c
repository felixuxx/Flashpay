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
  (void) extra;
  (void) extra_size;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Received /management/extensions update event\n");
}


enum GNUNET_GenericReturnValue
TEH_extensions_init ()
{
  struct GNUNET_DB_EventHeaderP es = {
    .size = htons (sizeof (es)),
    .type = htons (TALER_DBEVENT_EXCHANGE_EXTENSIONS_UPDATED),
  };

  extensions_eh = TEH_plugin->event_listen (TEH_plugin->cls,
                                            GNUNET_TIME_UNIT_FOREVER_REL,
                                            &es,
                                            &extension_update_event_cb,
                                            NULL);
  if (NULL == extensions_eh)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
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


void
TEH_extensions_update_state (void)
{
  /* TODO */
#if 0
  struct GNUNET_DB_EventHeaderP es = {
    .size = htons (sizeof (es)),
    .type = htons (TALER_DBEVENT_EXCHANGE_WIRE_UPDATED),
  };

  TEH_plugin->event_notify (TEH_plugin->cls,
                            &es,
                            NULL,
                            0);
#endif
}


/* end of taler-exchange-httpd_extensions.c */
