/*
   This file is part of TALER
   Copyright (C) 2024 Taler Systems SA

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
 * @file exchangedb/pg_lookup_aml_history.h
 * @brief implementation of the lookup_aml_history function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_AML_HISTORY_H
#define PG_LOOKUP_AML_HISTORY_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Lookup AML history for an account identified via
 * @a h_payto.
 *
 * @param cls closure
 * @param h_payto hash of account to lookup history for
 * @param cb function to call on results
 * @param cb_cls closure for @a cb
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_aml_history (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  TALER_EXCHANGEDB_AmlHistoryCallback cb,
  void *cb_cls);


#endif
