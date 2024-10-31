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
 * @file exchangedb/pg_lookup_pending_legitimization.h
 * @brief implementation of the lookup_pending_legitimization function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_COMPLETED_LEGITIMIZATION_H
#define PG_LOOKUP_COMPLETED_LEGITIMIZATION_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Lookup measure data for a legitimization process.
 *
 * @param cls closure
 * @param legitimization_measure_serial_id
 *    row in legitimization_measures table to access
 * @param measure_index index of the measure to return
 *    attribute data for
 * @param[out] access_token
 *    set to token for access control that must match
 * @param[out] h_payto set to the the hash of the
 *    payto URI of the account undergoing legitimization
 * @param[out] jmeasures set to the legitimization
 *    measures that were put on the account
 * @param[out] is_finished set to true if the legitimization was
 *    already finished
 * @param[out] encrypted_attributes_len set to length of
 *    @a encrypted_attributes
 * @param[out] encrypted_attributes set to the attributes
 *    obtained for the legitimization process, if it
 *    succeeded, otherwise set to NULL
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_completed_legitimization (
  void *cls,
  uint64_t legitimization_measure_serial_id,
  uint32_t measure_index,
  struct TALER_AccountAccessTokenP *access_token,
  struct TALER_NormalizedPaytoHashP *h_payto,
  json_t **jmeasures,
  bool *is_finished,
  size_t *encrypted_attributes_len,
  void **encrypted_attributes);

#endif
