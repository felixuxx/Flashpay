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
 * @file exchangedb/pg_get_link_data.h
 * @brief implementation of the get_link_data function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_LINK_DATA_H
#define PG_GET_LINK_DATA_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Obtain the link data of a coin, that is the encrypted link
 * information, the denomination keys and the signatures.
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param coin_pub public key of the coin
 * @param ldc function to call for each session the coin was melted into
 * @param ldc_cls closure for @a tdc
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_get_link_data (void *cls,
                      const struct TALER_CoinSpendPublicKeyP *coin_pub,
                      TALER_EXCHANGEDB_LinkCallback ldc,
                      void *ldc_cls);

#endif
