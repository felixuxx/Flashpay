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
 * @file pg_insert_auditor_progress_coin.h
 * @brief implementation of the insert_auditor_progress_coin function
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_AUDITOR_PROGRESS_COIN_H
#define PG_INSERT_AUDITOR_PROGRESS_COIN_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_auditordb_plugin.h"


/**
 * Insert information about the auditor's progress with an exchange's
 * data.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub master key of the exchange
 * @param ppc where is the auditor in processing
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TAH_PG_insert_auditor_progress_coin (
  void *cls,
  const struct TALER_MasterPublicKeyP *master_pub,
  const struct TALER_AUDITORDB_ProgressPointCoin *ppc);

#endif
