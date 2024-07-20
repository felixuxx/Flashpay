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
 * @file exchangedb/pg_trigger_kyc_rule_for_account.h
 * @brief implementation of the trigger_kyc_rule_for_account function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_TRIGGER_KYC_RULE_FOR_ACCOUNT_H
#define PG_TRIGGER_KYC_RULE_FOR_ACCOUNT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Insert KYC requirement for @a h_payto account into table.
 *
 * @param cls closure
 * @param payto_uri account that must be KYC'ed
 * @param h_payto hash of @a payto_uri
 * @param jmeasures serialized MeasureSet to put in place
 * @param display_priority priority of the rule
 * @param[out] requirement_row set to legitimization requirement row for this check
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_trigger_kyc_rule_for_account (
  void *cls,
  const char *payto_uri,
  const struct TALER_PaytoHashP *h_payto,
  const json_t *jmeasures,
  uint32_t display_priority,
  uint64_t *requirement_row);

#endif
