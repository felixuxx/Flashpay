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
 * @file exchangedb/pg_event_listen.h
 * @brief implementation of the event_listen function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_EVENT_LISTEN_H
#define PG_EVENT_LISTEN_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Register callback to be invoked on events of type @a es.
 *
 * @param cls database context to use
 * @param timeout how long until to generate a timeout event
 * @param es specification of the event to listen for
 * @param cb function to call when the event happens, possibly
 *         multiple times (until cancel is invoked)
 * @param cb_cls closure for @a cb
 * @return handle useful to cancel the listener
 */
struct GNUNET_DB_EventHandler *
TEH_PG_event_listen (void *cls,
                       struct GNUNET_TIME_Relative timeout,
                       const struct GNUNET_DB_EventHeaderP *es,
                       GNUNET_DB_EventCallback cb,
                     void *cb_cls);

#endif
