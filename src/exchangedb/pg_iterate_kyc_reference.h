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
 * @file pg_iterate_kyc_reference.h
 * @brief implementation of the iterate_kyc_reference function
 * @author Christian Grothoff
 */
#ifndef PG_ITERATE_KYC_REFERENCE_H
#define PG_ITERATE_KYC_REFERENCE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Call us on KYC legitimization processes satisfied and not expired for the
 * given account.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto account identifier
 * @param lpc function to call for each satisfied KYC legitimization process
 * @param lpc_cls closure for @a lpc
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_iterate_kyc_reference (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  TALER_EXCHANGEDB_LegitimizationProcessCallback lpc,
  void *lpc_cls);

#endif
