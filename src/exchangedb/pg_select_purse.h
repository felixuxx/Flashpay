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
 * @file pg_select_purse.h
 * @brief implementation of the select_purse function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_PURSE_H
#define PG_SELECT_PURSE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Function called to obtain information about a purse.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub public key of the new purse
 * @param[out] purse_creation set to time when the purse was created
 * @param[out] purse_expiration set to time when the purse will expire
 * @param[out] amount set to target amount (with fees) to be put into the purse
 * @param[out] deposited set to actual amount put into the purse so far
 * @param[out] h_contract_terms set to hash of the contract for the purse
 * @param[out] merge_timestamp set to time when the purse was merged, or NEVER if not
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_purse (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Timestamp *purse_creation,
  struct GNUNET_TIME_Timestamp *purse_expiration,
  struct TALER_Amount *amount,
  struct TALER_Amount *deposited,
  struct TALER_PrivateContractHashP *h_contract_terms,
  struct GNUNET_TIME_Timestamp *merge_timestamp);


#endif
