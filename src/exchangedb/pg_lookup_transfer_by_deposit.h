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
 * @file exchangedb/pg_lookup_transfer_by_deposit.h
 * @brief implementation of the lookup_transfer_by_deposit function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_TRANSFER_BY_DEPOSIT_H
#define PG_LOOKUP_TRANSFER_BY_DEPOSIT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Try to find the wire transfer details for a deposit operation.
 * If we did not execute the deposit yet, return when it is supposed
 * to be executed.
 *
 * @param cls closure
 * @param h_contract_terms hash of the proposal data
 * @param h_wire hash of merchant wire details
 * @param coin_pub public key of deposited coin
 * @param merchant_pub merchant public key
 * @param[out] pending set to true if the transaction is still pending
 * @param[out] wtid wire transfer identifier, only set if @a pending is false
 * @param[out] exec_time when was the transaction done, or
 *         when we expect it to be done (if @a pending is false)
 * @param[out] amount_with_fee set to the total deposited amount
 * @param[out] deposit_fee set to how much the exchange did charge for the deposit
 * @param[out] kyc set to the kyc status of the receiver (if @a pending)
 * @param[out] aml_decision set to the AML status of the receiver
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_transfer_by_deposit (
  void *cls,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantPublicKeyP *merchant_pub,
  bool *pending,
  struct TALER_WireTransferIdentifierRawP *wtid,
  struct GNUNET_TIME_Timestamp *exec_time,
  struct TALER_Amount *amount_with_fee,
  struct TALER_Amount *deposit_fee,
  struct TALER_EXCHANGEDB_KycStatus *kyc,
  enum TALER_AmlDecisionState *aml_decision);

#endif
