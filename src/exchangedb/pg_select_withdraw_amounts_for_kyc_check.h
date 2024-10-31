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
 * @file exchangedb/pg_select_withdraw_amounts_for_kyc_check.h
 * @brief implementation of the select_withdraw_amounts_for_kyc_check function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_WITHDRAW_AMOUNTS_FOR_KYC_CHECK_H
#define PG_SELECT_WITHDRAW_AMOUNTS_FOR_KYC_CHECK_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Call @a kac on withdrawn amounts after @a time_limit which are relevant
 * for a KYC trigger for a the (debited) account identified by @a h_payto.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto account identifier
 * @param time_limit oldest transaction that could be relevant
 * @param kac function to call for each applicable amount, in reverse chronological order (or until @a kac aborts by returning anything except #GNUNET_OK).
 * @param kac_cls closure for @a kac
 * @return transaction status code, @a kac aborting with #GNUNET_NO is not an error
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_withdraw_amounts_for_kyc_check (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  struct GNUNET_TIME_Absolute time_limit,
  TALER_EXCHANGEDB_KycAmountCallback kac,
  void *kac_cls);

#endif
