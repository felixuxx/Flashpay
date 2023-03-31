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
 * @file exchangedb/pg_get_denomination_revocation.h
 * @brief implementation of the get_denomination_revocation function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_DENOMINATION_REVOCATION_H
#define PG_GET_DENOMINATION_REVOCATION_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Obtain information about a denomination key's revocation from
 * the database.
 *
 * @param cls closure
 * @param denom_pub_hash hash of the revoked denomination key
 * @param[out] master_sig signature affirming the revocation
 * @param[out] rowid row where the information is stored
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_denomination_revocation (
  void *cls,
  const struct TALER_DenominationHashP *denom_pub_hash,
  struct TALER_MasterSignatureP *master_sig,
  uint64_t *rowid);

#endif
