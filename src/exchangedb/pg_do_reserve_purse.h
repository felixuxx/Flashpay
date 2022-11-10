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
 * @file exchangedb/pg_do_reserve_purse.h
 * @brief implementation of the do_reserve_purse function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DO_RESERVE_PURSE_H
#define PG_DO_RESERVE_PURSE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Function called insert request to merge a purse into a reserve by the
 * respective purse merge key. The purse must not have been merged into a
 * different reserve.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub purse to merge
 * @param merge_sig signature affirming the merge
 * @param merge_timestamp time of the merge
 * @param reserve_sig signature of the reserve affirming the merge
 * @param purse_fee amount to charge the reserve for the purse creation, NULL to use the quota
 * @param reserve_pub public key of the reserve to credit
 * @param[out] in_conflict set to true if @a purse_pub was merged into a different reserve already
 * @param[out] no_reserve set to true if @a reserve_pub is not a known reserve
 * @param[out] insufficient_funds set to true if @a reserve_pub has insufficient capacity to create another purse
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_reserve_purse (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergeSignatureP *merge_sig,
  const struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_ReserveSignatureP *reserve_sig,
  const struct TALER_Amount *purse_fee,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  bool *in_conflict,
  bool *no_reserve,
  bool *insufficient_funds);

#endif
