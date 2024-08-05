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
 * @param requirement_row identifies requirement to look up (in legitimization_measures table)
 * @param[out] account_pub set to public key of the account
 *    needed to authorize access, all zeros if not known
 * @param[out] reserve_pub set to last reserve public key
 *    used for a wire transfer from the account to the
 *    exchange; alternatively used to authorize access,
 *    all zeros if not known
 * @param[out] access_token set to the access token to begin
 *    work on KYC processes for this account
 * @param[out] jrules set to active ``LegitimizationRuleSet``
 *    of the account impacted by the requirement
 * @param[out] aml_review set to true if the account is under
 *    active review by AML staff
 * @param[out] kyc_required set to true if the user must pass
 *    some KYC check before some previous operation may continue
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_kyc_requirement_by_row (
  void *cls,
  uint64_t requirement_row,
  union TALER_AccountPublicKeyP *account_pub,
  struct TALER_ReservePublicKeyP *reserve_pub,
  struct TALER_AccountAccessTokenP *access_token,
  json_t **jrules,
  bool *aml_review,
  bool *kyc_required);


#endif
