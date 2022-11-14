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
 * @file exchangedb/pg_insert_partner.h
 * @brief implementation of the insert_partner function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_PARTNER_H
#define PG_INSERT_PARTNER_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Function called to store configuration data about a partner
 * exchange that we are federated with.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param master_pub public offline signing key of the partner exchange
 * @param start_date when does the following data start to be valid
 * @param end_date when does the validity end (exclusive)
 * @param wad_frequency how often do we do exchange-to-exchange settlements?
 * @param wad_fee how much do we charge for transfers to the partner
 * @param partner_base_url base URL of the partner exchange
 * @param master_sig signature with our offline signing key affirming the above
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_partner (void *cls,
                         const struct TALER_MasterPublicKeyP *master_pub,
                         struct GNUNET_TIME_Timestamp start_date,
                         struct GNUNET_TIME_Timestamp end_date,
                         struct GNUNET_TIME_Relative wad_frequency,
                         const struct TALER_Amount *wad_fee,
                         const char *partner_base_url,
                       const struct TALER_MasterSignatureP *master_sig);

#endif
