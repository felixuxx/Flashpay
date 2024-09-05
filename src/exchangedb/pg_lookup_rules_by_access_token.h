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
 * @file exchangedb/pg_lookup_rules_by_access_token.h
 * @brief implementation of the lookup_rules_by_access_token function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_RULES_BY_ACCESS_TOKEN_H
#define PG_LOOKUP_RULES_BY_ACCESS_TOKEN_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Lookup KYC rules by account access token.
 *
 * @param cls closure
 * @param h_payto account hash to look under
 * @param[out] jnew_rules set to active LegitimizationRuleSet
 * @param[out] rowid set to outcome_serial_id of the row
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_rules_by_access_token (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  json_t **jnew_rules,
  uint64_t *rowid);

#endif
