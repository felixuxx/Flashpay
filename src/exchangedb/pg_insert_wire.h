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
 * @file exchangedb/pg_insert_wire.h
 * @brief implementation of the insert_wire function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_WIRE_H
#define PG_INSERT_WIRE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Insert information about an wire account used by this exchange.
 *
 * @param cls closure
 * @param payto_uri wire account of the exchange
 * @param conversion_url URL of a conversion service, NULL if there is no conversion
 * @param debit_restrictions JSON array with debit restrictions on the account
 * @param credit_restrictions JSON array with credit restrictions on the account
 * @param start_date date when the account was added by the offline system
 *                      (only to be used for replay detection)
 * @param master_sig public signature affirming the existence of the account,
 *         must be of purpose #TALER_SIGNATURE_MASTER_WIRE_DETAILS
 * @param bank_label label to show this entry under in the UI, can be NULL
 * @param priority determines order in which entries are shown in the UI
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_wire (void *cls,
                    const char *payto_uri,
                    const char *conversion_url,
                    const json_t *debit_restrictions,
                    const json_t *credit_restrictions,
                    struct GNUNET_TIME_Timestamp start_date,
                    const struct TALER_MasterSignatureP *master_sig,
                    const char *bank_label,
                    int64_t priority);


#endif
