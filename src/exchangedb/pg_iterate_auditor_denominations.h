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
 * @file exchangedb/pg_iterate_auditor_denominations.h
 * @brief implementation of the iterate_auditor_denominations function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_ITERATE_AUDITOR_DENOMINATIONS_H
#define PG_ITERATE_AUDITOR_DENOMINATIONS_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Function called to invoke @a cb on every denomination with an active
 * auditor. Disabled auditors and denominations without auditor are
 * skipped. Runs in its own read-only transaction.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param cb function to call on each active auditor
 * @param cb_cls closure for @a cb
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_iterate_auditor_denominations (
  void *cls,
  TALER_EXCHANGEDB_AuditorDenominationsCallback cb,
  void *cb_cls);

#endif
