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
 * @file exchangedb/pg_do_purse_delete.h
 * @brief implementation of the do_purse_delete function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DO_PURSE_DELETE_H
#define PG_DO_PURSE_DELETE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Function called to explicitly delete a purse.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param purse_pub purse to delete
 * @param purse_sig signature affirming the deletion
 * @param[out] decided set to true if the purse was
 *        already decided and thus could not be deleted
 * @param[out] found set to true if the purse was found
 *        (if false, purse could not be deleted)
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_do_purse_delete (
  void *cls,
  const struct TALER_PurseContractPublicKeyP *purse_pub,
  const struct TALER_PurseContractSignatureP *purse_sig,
  bool *decided,
  bool *found);

#endif
