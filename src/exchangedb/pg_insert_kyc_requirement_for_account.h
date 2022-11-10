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
 * @file exchangedb/pg_insert_kyc_requirement_for_account.h
 * @brief implementation of the insert_kyc_requirement_for_account function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_KYC_REQUIREMENT_FOR_ACCOUNT_H
#define PG_INSERT_KYC_REQUIREMENT_FOR_ACCOUNT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Insert KYC requirement for @a h_payto account into table.
 *
 * @param cls closure
 * @param provider_section provider that must be checked
 * @param h_payto account that must be KYC'ed
 * @param[out] requirement_row set to legitimization requirement row for this check
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_kyc_requirement_for_account (
  void *cls,
  const char *provider_section,
  const struct TALER_PaytoHashP *h_payto,
  uint64_t *requirement_row);
#endif
