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
 * @file exchangedb/pg_select_purse_merge.h
 * @brief implementation of the select_purse_merge function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_PURSE_MERGE_H
#define PG_SELECT_PURSE_MERGE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to approve merging of a purse with
 * an account, made by the receiving account.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub public key of the purse
 * @param[out] merge_sig set to the signature confirming the merge
 * @param[out] merge_timestamp set to the time of the merge
 * @param[out] partner_url set to the URL of the target exchange, or NULL if the target exchange is us. To be freed by the caller.
 * @param[out] reserve_pub set to the public key of the reserve/account being credited
 * @param[out] refunded set to true if purse was refunded
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_purse_merge (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  struct TALER_PurseMergeSignatureP *merge_sig,
  struct GNUNET_TIME_Timestamp *merge_timestamp,
  char **partner_url,
  struct TALER_ReservePublicKeyP *reserve_pub,
  bool *refunded);

#endif
