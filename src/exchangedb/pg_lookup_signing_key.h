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
 * @file exchangedb/pg_lookup_signing_key.h
 * @brief implementation of the lookup_signing_key function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_SIGNING_KEY_H
#define PG_LOOKUP_SIGNING_KEY_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Lookup signing key meta data.
 *
 * @param cls closure
 * @param exchange_pub the exchange online signing public key
 * @param[out] meta meta data about @a exchange_pub
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_signing_key (
  void *cls,
  const struct TALER_ExchangePublicKeyP *exchange_pub,
  struct TALER_EXCHANGEDB_SignkeyMetaData *meta);
#endif
