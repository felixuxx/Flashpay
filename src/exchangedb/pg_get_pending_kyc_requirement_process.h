/*
   This file is part of TALER
   Copyright (C) 2023 Taler Systems SA

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
 * @file exchangedb/pg_get_pending_kyc_requirement_process.h
 * @brief implementation of the get_pending_kyc_requirement_process function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_PENDING_KYC_REQUIREMENT_PROCESS_H
#define PG_GET_PENDING_KYC_REQUIREMENT_PROCESS_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Fetch information about pending KYC requirement process.
 *
 * @param cls closure
 * @param h_payto account that must be KYC'ed
 * @param provider_section provider that must be checked
 * @param[out] redirect_url set to redirect URL for the process
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_pending_kyc_requirement_process (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const char *provider_section,
  char **redirect_url);

#endif
