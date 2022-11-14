/*
   This file is part of TALER
   Copyright (C) 2022 Taler Systems SA

   TALER is free software; you can redistribute it and/or modify it under the
   terms of the GNU General Public License as published by the Free Software
   Foundation; either version 3, or (at your option) any later version.

   TALER is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along with
   TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
 */
/**
 * @file exchangedb/pg_event_listen_cancel.h
 * @brief implementation of the event_listen_cancel function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_EVENT_LISTEN_CANCEL_H
#define PG_EVENT_LISTEN_CANCEL_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Stop notifications.
 *
 * @param cls the plugin's `struct PostgresClosure`
 * @param eh handle to unregister.
 */
void
TEH_PG_event_listen_cancel (void *cls,
                            struct GNUNET_DB_EventHandler *eh);
#endif
