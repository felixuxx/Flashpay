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
 * @file exchangedb/pg_clear_aml_lock.h
 * @brief implementation of the clear_aml_lock function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_CLEAR_AML_LOCK_H
#define PG_CLEAR_AML_LOCK_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Clear a lock on running AML programs for the @a h_payto
 * account. Returns 0 if @a h_payto is not known; does not
 * actually care if there was a lock. Also does not by
 * itself notify clients waiting for the lock, that
 * notification the caller must do separately after finishing
 * the database update.
 *
 * @param cls closure
 * @param h_payto account to clear the lock for
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_clear_aml_lock (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto);

#endif
