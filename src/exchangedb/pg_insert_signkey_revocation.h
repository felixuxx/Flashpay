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
 * @file exchangedb/pg_insert_signkey_revocation.h
 * @brief implementation of the insert_signkey_revocation function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_SIGNKEY_REVOCATION_H
#define PG_INSERT_SIGNKEY_REVOCATION_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Store information about a revoked online signing key.
 *
 * @param cls closure
 * @param exchange_pub exchange online signing key that was revoked
 * @param master_sig signature affirming the revocation
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_signkey_revocation (
  void *cls,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  const struct TALER_MasterSignatureP *master_sig);
#endif
