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
 * @file exchangedb/pg_insert_programmatic_legitimization_outcome.h
 * @brief implementation of the insert_programmatic_legitimization_outcome function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_PROGRAMMATIC_LEGITIMIZATION_OUTCOME_H
#define PG_INSERT_PROGRAMMATIC_LEGITIMIZATION_OUTCOME_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Store automated legitimization outcome.
 *
 * @param cls closure
 * @param h_payto account for which the attribute data is stored
 * @param decision_time when was the decision taken
 * @param expiration_time when does the data expire
 * @param account_properties new account properties
 * @param to_investigate true to flag account for investigation
 * @param new_rules new KYC rules to apply to the account
 * @param num_events length of the @a events array
 * @param events array of KYC events to trigger
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_programmatic_legitimization_outcome (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp decision_time,
  struct GNUNET_TIME_Absolute expiration_time,
  const json_t *account_properties,
  bool to_investigate,
  const json_t *new_rules,
  unsigned int num_events,
  const char **events);

#endif
