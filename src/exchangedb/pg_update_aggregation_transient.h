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
 * @file exchangedb/pg_update_aggregation_transient.h
 * @brief implementation of the update_aggregation_transient function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_UPDATE_AGGREGATION_TRANSIENT_H
#define PG_UPDATE_AGGREGATION_TRANSIENT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Update existing entry in the transient aggregation table.
 * @a h_payto is only needed for query performance.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto destination of the wire transfer
 * @param wtid the raw wire transfer identifier to update
 * @param kyc_requirement_row row in legitimization_requirements that need to be satisfied to continue, or 0 for none
 * @param total new total amount to be wired in the future
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_update_aggregation_transient (
  void *cls,
  const struct TALER_FullPaytoHashP *h_payto,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  uint64_t kyc_requirement_row,
  const struct TALER_Amount *total);

#endif
