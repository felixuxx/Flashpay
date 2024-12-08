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
 * @file exchangedb/pg_set_aml_lock.h
 * @brief implementation of the set_aml_lock function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SET_AML_LOCK_H
#define PG_SET_AML_LOCK_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Set a lock for @a lock_duration on running AML programs for the @a h_payto
 * account. If a lock already exists, returns the timeout of the
 * @a existing_lock.  Returns 0 if @a h_payto is not known.
 *
 * @param cls closure
 * @param h_payto account to lock
 * @param lock_duration how long to lock the account
 * @param[out] existing_lock set to timeout of existing lock, or
 *         to zero if there is no existing lock
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_set_aml_lock (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  struct GNUNET_TIME_Relative lock_duration,
  struct GNUNET_TIME_Absolute *existing_lock);


#endif
