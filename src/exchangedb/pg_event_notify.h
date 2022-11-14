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
 * @file exchangedb/pg_event_notify.h
 * @brief implementation of the event_notify function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_EVENT_NOTIFY_H
#define PG_EVENT_NOTIFY_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Notify all that listen on @a es of an event.
 *
 * @param cls database context to use
 * @param es specification of the event to generate
 * @param extra additional event data provided
 * @param extra_size number of bytes in @a extra
 */
void
TEH_PG_event_notify (void *cls,
                       const struct GNUNET_DB_EventHeaderP *es,
                       const void *extra,
                     size_t extra_size);

#endif
