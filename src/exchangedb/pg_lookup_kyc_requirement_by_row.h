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
 * @file exchangedb/pg_lookup_kyc_requirement_by_row.h
 * @brief implementation of the lookup_kyc_requirement_by_row function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_KYC_REQUIREMENT_BY_ROW_H
#define PG_LOOKUP_KYC_REQUIREMENT_BY_ROW_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Lookup KYC requirement.
 *
 * @param cls closure
 * @param requirement_row identifies requirement to look up
 * @param[out] requirements provider that must be checked
 * @param[out] h_payto account that must be KYC'ed
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_kyc_requirement_by_row (
  void *cls,
  uint64_t requirement_row,
  char **requirements,
  struct TALER_PaytoHashP *h_payto);
#endif
