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
#ifndef PG_GET_BAD_SIG_LOSSES_H
#define PG_GET_BAD_SIG_LOSSES_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"

/**
 * Get information about bad signature losses from the database.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param limit number of records to return, negative for descending
 * @param offset table row to start from, exclusive, direction determined by @a limit
 * @param return_suppressed should suppressed rows be returned anyway?
 * @param op_spec_pub public key to filter by; FIXME: replace by pointer
 * @param op operation to filter by
 * @param cb function to call with results
 * @param cb_cls closure for @a cb
 * @return query result status
 */
enum GNUNET_DB_QueryStatus
TAH_PG_get_bad_sig_losses (
  void *cls,
  int64_t limit,
  uint64_t offset,
  bool return_suppressed,
  const struct GNUNET_CRYPTO_EddsaPublicKey *op_spec_pub,
  const char *op,
  TALER_AUDITORDB_BadSigLossesCallback cb,
  void *cb_cls);

#endif
