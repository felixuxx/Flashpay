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
/**
 * @file exchangedb/pg_kycauth_in_insert.h
 * @brief implementation of the kycauth_in_insert function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_KYCAUTH_IN_INSERT_H
#define PG_KYCAUTH_IN_INSERT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Insert an incoming KCYAUTH wire transfer into
 * the database and update the authentication key
 * for the origin account.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param account_pub public key of the account
 * @param credit_amount amount we were credited
 * @param execution_date when was the transfer made
 * @param debit_account_uri URI of the debit account
 * @param section_name section of the exchange bank account that received the transfer
 * @param serial_id bank-specific row identifying the transfer
 */
enum GNUNET_DB_QueryStatus
TEH_PG_kycauth_in_insert (
  void *cls,
  const union TALER_AccountPublicKeyP *account_pub,
  const struct TALER_Amount *credit_amount,
  struct GNUNET_TIME_Timestamp execution_date,
  const char *debit_account_uri,
  const char *section_name,
  uint64_t serial_id);


#endif
