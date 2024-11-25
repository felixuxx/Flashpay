/*
   This file is part of TALER
   Copyright (C) 2022-2024 Taler Systems SA

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
 * @file exchangedb/pg_get_kyc_rules.h
 * @brief implementation of the get_kyc_rules function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_KYC_RULES_H
#define PG_GET_KYC_RULES_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Return KYC rules that apply to the given account.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto account identifier
 * @param[out] no_account_pub set to true if no @a account_pub is available
 * @param[out] account_pub set to account public key the rules
 *   apply to (because this key was used in KYC auth)
 * @param[out] no_reserve_pub set to true if no @a reserve_pub is available
 * @param[out] reserve_pub set to last incoming reserve public key
 *   of a wire transfer to the exchange from the given @a h_payto
 *   apply to (because this key was used in KYC auth)
 * @param[out] jrules set to the active KYC rules for the
 *    given account, set to NULL if no custom rules are active
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_kyc_rules (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  bool *no_account_pub,
  union TALER_AccountPublicKeyP *account_pub,
  bool *no_reserve_pub,
  struct TALER_ReservePublicKeyP *reserve_pub,
  json_t **jrules);


/**
 * Return only the KYC rules that apply to the given account.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param h_payto account identifier
 * @param[out] jrules set to the active KYC rules for the
 *    given account, set to NULL if no custom rules are active
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_kyc_rules2 (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  json_t **jrules);

#endif
