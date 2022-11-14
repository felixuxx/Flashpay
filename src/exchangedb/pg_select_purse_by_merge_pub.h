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
 * @file exchangedb/pg_select_purse_by_merge_pub.h
 * @brief implementation of the select_purse_by_merge_pub function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_PURSE_BY_MERGE_PUB_H
#define PG_SELECT_PURSE_BY_MERGE_PUB_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to return meta data about a purse by the
 * merge capability key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param merge_pub public key representing the merge capability
 * @param[out] purse_pub public key of the purse
 * @param[out] purse_expiration when would an unmerged purse expire
 * @param[out] h_contract_terms contract associated with the purse
 * @param[out] age_limit the age limit for deposits into the purse
 * @param[out] target_amount amount to be put into the purse
 * @param[out] balance amount put so far into the purse
 * @param[out] purse_sig signature of the purse over the initialization data
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_purse_by_merge_pub (
  void *cls,
  const struct TALER_PurseMergePublicKeyP *merge_pub,
  struct TALER_PurseContractPublicKeyP *purse_pub,
  struct GNUNET_TIME_Timestamp *purse_expiration,
  struct TALER_PrivateContractHashP *h_contract_terms,
  uint32_t *age_limit,
  struct TALER_Amount *target_amount,
  struct TALER_Amount *balance,
  struct TALER_PurseContractSignatureP *purse_sig);
#endif
