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
 * @file auditordb/pg_select_purse_expired.c
 * @brief Implementation of the select_purse_expired function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_select_purse_expired.h"
#include "pg_helper.h"

enum GNUNET_DB_QueryStatus
TAH_PG_select_purse_expired (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  TALER_AUDITORDB_ExpiredPurseCallback cb,
  void *cb_cls)
{
}
