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
 * @file exchangedb/pg_drain_kyc_alert.h
 * @brief implementation of the drain_kyc_alert function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_DRAIN_KYC_ALERT_H
#define PG_DRAIN_KYC_ALERT_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Extract next KYC alert.  Deletes the alert.
 *
 * @param cls the @e cls of this struct with the plugin-specific state
 * @param trigger_type which type of alert to drain
 * @param[out] h_payto set to hash of payto-URI where KYC status changed
 * @return transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_drain_kyc_alert (void *cls,
                        uint32_t trigger_type,
                        struct TALER_PaytoHashP *h_payto);

#endif
