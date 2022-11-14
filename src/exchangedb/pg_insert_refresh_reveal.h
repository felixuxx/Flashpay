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
 * @file exchangedb/pg_insert_refresh_reveal.h
 * @brief implementation of the insert_refresh_reveal function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_REFRESH_REVEAL_H
#define PG_INSERT_REFRESH_REVEAL_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Store in the database which coin(s) the wallet wanted to create
 * in a given refresh operation and all of the other information
 * we learned or created in the /refresh/reveal step.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param melt_serial_id row ID of the commitment / melt operation in refresh_commitments
 * @param num_rrcs number of coins to generate, size of the @a rrcs array
 * @param rrcs information about the new coins
 * @param num_tprivs number of entries in @a tprivs, should be #TALER_CNC_KAPPA - 1
 * @param tprivs transfer private keys to store
 * @param tp public key to store
 * @return query status for the transaction
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_refresh_reveal (
  void *cls,
  uint64_t melt_serial_id,
  uint32_t num_rrcs,
  const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs,
  unsigned int num_tprivs,
  const struct TALER_TransferPrivateKeyP *tprivs,
  const struct TALER_TransferPublicKeyP *tp);

#endif
