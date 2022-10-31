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
 * @file pg_get_wire_auditor_account_progress.h
 * @brief implementation of the get_wire_auditor_account_progress function
 * @author Christian Grothoff
 */
#ifndef PG_GET_WIRE_AUDITOR_ACCOUNT_PROGRESS_H
#define PG_GET_WIRE_AUDITOR_ACCOUNT_PROGRESS_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Get information about the progress of the auditor.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param account_name name of the wire account we are auditing
 * @param[out] pp where is the auditor in processing
 * @param[out] bapp how far are we in the wire transaction histories
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_get_wire_auditor_account_progress (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const char *account_name,
  struct TALER_AUDITORDB_WireAccountProgressPoint *pp,
  struct TALER_AUDITORDB_BankAccountProgressPoint *bapp);


#endif
