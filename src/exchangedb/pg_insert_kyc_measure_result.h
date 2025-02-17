/*
   This file is part of TALER
   Copyright (C) 2022, 2023 Taler Systems SA

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
 * @file exchangedb/pg_insert_kyc_measure_result.h
 * @brief implementation of the insert_kyc_measure_result function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_KYC_ATTRIBUTES_H
#define PG_INSERT_KYC_ATTRIBUTES_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Update KYC process status and AML status for the given account based on AML
 * program result.
 *
 * @param cls closure
 * @param process_row KYC process row to update
 * @param h_payto account for which the attribute data is stored
 * @param expiration_time when do the @a new_rules expire
 * @param account_properties new account properties
 * @param new_rules new KYC rules to apply to the account
 * @param to_investigate true to flag account for investigation
 * @param num_events length of the @a events array
 * @param events array of KYC events to trigger
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_kyc_measure_result (
  void *cls,
  uint64_t process_row,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp expiration_time,
  const json_t *account_properties,
  const json_t *new_rules,
  bool to_investigate,
  unsigned int num_events,
  const char **events);


#endif
