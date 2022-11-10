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
 * @file exchangedb/pg_select_satisfied_kyc_processes.h
 * @brief implementation of the select_satisfied_kyc_processes function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_SATISFIED_KYC_PROCESSES_H
#define PG_SELECT_SATISFIED_KYC_PROCESSES_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Call us on KYC processes satisfied for the given
 * account.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto account identifier
 * @param spc function to call for each satisfied KYC process
 * @param spc_cls closure for @a spc
 * @return transaction status code
 */


enum GNUNET_DB_QueryStatus
TEH_PG_select_satisfied_kyc_processes (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  TALER_EXCHANGEDB_SatisfiedProviderCallback spc,
  void *spc_cls);

#endif
