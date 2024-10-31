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
 * @file exchangedb/pg_kyc_provider_account_lookup.h
 * @brief implementation of the kyc_provider_account_lookup function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_KYC_PROVIDER_ACCOUNT_LOOKUP_H
#define PG_KYC_PROVIDER_ACCOUNT_LOOKUP_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Lookup an
 * @a h_payto by @a provider_legitimization_id.
 *
 * @param cls closure
 * @param provider_name
 * @param provider_legitimization_id legi to look up
 * @param[out] h_payto where to write the result
 * @param[out] process_row where to write the row of the entry
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_kyc_provider_account_lookup (
  void *cls,
  const char *provider_name,
  const char *provider_legitimization_id,
  struct TALER_NormalizedPaytoHashP *h_payto,
  uint64_t *process_row);

#endif
