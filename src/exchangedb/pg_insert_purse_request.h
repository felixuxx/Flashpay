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
 * @file exchangedb/pg_insert_purse_request.h
 * @brief implementation of the insert_purse_request function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_PURSE_REQUEST_H
#define PG_INSERT_PURSE_REQUEST_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to create a new purse with certain meta data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub public key of the new purse
 * @param merge_pub public key providing the merge capability
 * @param purse_expiration time when the purse will expire
 * @param h_contract_terms hash of the contract for the purse
 * @param age_limit age limit to enforce for payments into the purse
 * @param flags flags for the operation
 * @param purse_fee fee we are allowed to charge to the reserve (depending on @a flags)
 * @param amount target amount (with fees) to be put into the purse
 * @param purse_sig signature with @a purse_pub's private key affirming the above
 * @param[out] in_conflict set to true if the meta data
 *             conflicts with an existing purse;
 *             in this case, the return value will be
 *             #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT despite the failure
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_purse_request (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  struct GNUNET_TIME_Timestamp purse_expiration,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  uint32_t age_limit,
  enum TALER_WalletAccountMergeFlags flags,
  const struct TALER_Amount *purse_fee,
  const struct TALER_Amount *amount,
  const struct TALER_PurseContractSignatureP *purse_sig,
  bool *in_conflict);

#endif
