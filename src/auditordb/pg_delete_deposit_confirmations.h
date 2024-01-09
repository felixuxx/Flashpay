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
 * @file auditordb/pg_delete_deposit_confirmations.h
 * @brief implementation of the delete_deposit_confirmations function for Postgres
 * @author Nicola Eigel
 */
#ifndef PG_DELETE_DEPOSIT_CONFIRMATIONS_H
#define PG_DELETE_DEPOSIT_CONFIRMATIONS_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"

/**
 * Delete a row from the deposit confirmations table.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_contract_terms private contract hash
 * @param h_wire merchant wire hash
 * @param merchant_pub master key of the merchant
 * @param exchange_sig signature of the exchange
 * @param exchange_pub master key of the exchange
 * @param master_sig master signature of the exchange
 * @return
 */
enum GNUNET_DB_QueryStatus
TAH_PG_delete_deposit_confirmations (
  void *cls,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  const struct TALER_ExchangeSignatureP *exchange_sig,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_MasterSignatureP *master_sig);


#endif
