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
 * @file exchangedb/pg_select_justification_for_missing_wire.h
 * @brief implementation of the select_justification_for_missing_wire function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_JUSTIFICATION_FOR_MISSING_WIRE_H
#define PG_SELECT_JUSTIFICATION_FOR_MISSING_WIRE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Select all of those justifications for why we might not have
 * done a wire transfer from in the database for a particular target account.
 *
 * @param cls closure
 * @param wire_target_h_payto effected target account
 * @param[out] payto_uri target account URI, set to NULL if unknown
 * @param[out] kyc_pending set to string describing missing KYC data
 * @param[out] status set to AML status
 * @param[out] aml_limit set to AML limit, or invalid amount for none
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_justification_for_missing_wire (
  void *cls,
  const struct TALER_PaytoHashP *wire_target_h_payto,
  char **payto_uri,
  char **kyc_pending,
  enum TALER_AmlDecisionState *status,
  struct TALER_Amount *aml_limit);

#endif
