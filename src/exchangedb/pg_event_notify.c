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
 * @file exchangedb/pg_event_notify.c
 * @brief Implementation of the event_notify function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_event_notify.h"
#include "pg_helper.h"


void
TEH_PG_event_notify (void *cls,
                       const struct GNUNET_DB_EventHeaderP *es,
                       const void *extra,
                       size_t extra_size)
{
  struct PostgresClosure *pg = cls;

  GNUNET_PQ_event_notify (pg->conn,
                          es,
                          extra,
                          extra_size);
}
