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
 * @file exchangedb/pg_create_aggregation_transient.h
 * @brief implementation of the create_aggregation_transient function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_CREATE_AGGREGATION_TRANSIENT_H
#define PG_CREATE_AGGREGATION_TRANSIENT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Create a new entry in the transient aggregation table.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto destination of the wire transfer
 * @param exchange_account_section exchange account to use
 * @param merchant_pub public key of the merchant receiving the transfer
 * @param wtid the raw wire transfer identifier to be used
 * @param kyc_requirement_row row in legitimization_requirements that need to be satisfied to continue, or 0 for none
 * @param total amount to be wired in the future
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_create_aggregation_transient (
  void *cls,
  const struct TALER_FullPaytoHashP *h_payto,
  const char *exchange_account_section,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  uint64_t kyc_requirement_row,
  const struct TALER_Amount *total);

#endif
