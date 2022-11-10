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
 * @file exchangedb/pg_do_purse_merge.h
 * @brief implementation of the do_purse_merge function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DO_PURSE_MERGE_H
#define PG_DO_PURSE_MERGE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Function called to approve merging a purse into a
 * reserve by the respective purse merge key.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub purse to merge
 * @param merge_sig signature affirming the merge
 * @param merge_timestamp time of the merge
 * @param reserve_sig signature of the reserve affirming the merge
 * @param partner_url URL of the partner exchange, can be NULL if the reserves lives with us
 * @param reserve_pub public key of the reserve to credit
 * @param[out] no_partner set to true if @a partner_url is unknown
 * @param[out] no_balance set to true if the @a purse_pub is not paid up yet
 * @param[out] in_conflict set to true if @a purse_pub was merged into a different reserve already
  * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_purse_merge (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseMergeSignatureP *merge_sig,
  const struct GNUNET_TIME_Timestamp merge_timestamp,
  const struct TALER_ReserveSignatureP *reserve_sig,
  const char *partner_url,
  const struct TALER_ReservePublicKeyP *reserve_pub,
  bool *no_partner,
  bool *no_balance,
  bool *in_conflict);

#endif
