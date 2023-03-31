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
 * @file exchangedb/pg_lookup_kyc_process_by_account.h
 * @brief implementation of the lookup_kyc_process_by_account function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_KYC_PROCESS_BY_ACCOUNT_H
#define PG_LOOKUP_KYC_PROCESS_BY_ACCOUNT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Lookup KYC provider meta data.
 *
 * @param cls closure
 * @param provider_section provider that must be checked
 * @param h_payto account that must be KYC'ed
 * @param[out] process_row row with the legitimization data
 * @param[out] expiration how long is this KYC check set to be valid (in the past if invalid)
 * @param[out] provider_account_id provider account ID
 * @param[out] provider_legitimization_id provider legitimization ID
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_kyc_process_by_account (
  void *cls,
  const char *provider_section,
  const struct TALER_PaytoHashP *h_payto,
  uint64_t *process_row,
  struct GNUNET_TIME_Absolute *expiration,
  char **provider_account_id,
  char **provider_legitimization_id);

#endif
