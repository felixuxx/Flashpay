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
 * @file exchangedb/pg_update_kyc_process_by_row.h
 * @brief implementation of the update_kyc_process_by_row function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_UPDATE_KYC_PROCESS_BY_ROW_H
#define PG_UPDATE_KYC_PROCESS_BY_ROW_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Update KYC requirement check with provider-linkage and/or
 * expiration data.
 *
 * @param cls closure
 * @param process_row row to select by
 * @param provider_name provider that must be checked (technically redundant)
 * @param h_payto account that must be KYC'ed (helps access by shard, otherwise also redundant)
 * @param provider_account_id provider account ID
 * @param provider_legitimization_id provider legitimization ID
 * @param redirect_url where the user should be redirected to start the KYC process
 * @param expiration how long is this KYC check set to be valid (in the past if invalid)
 * @param ec error code, #TALER_EC_NONE on success
 * @param error_message_hint human-readable error message details (in addition to @a ec, NULL on success)
 * @param finished true to mark the process as done
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_update_kyc_process_by_row (
  void *cls,
  uint64_t process_row,
  const char *provider_name,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  const char *provider_account_id,
  const char *provider_legitimization_id,
  const char *redirect_url,
  struct GNUNET_TIME_Absolute expiration,
  enum TALER_ErrorCode ec,
  const char *error_message_hint,
  bool finished);

#endif
