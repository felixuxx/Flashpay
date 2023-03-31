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
 * @file exchangedb/pg_update_auditor.h
 * @brief implementation of the update_auditor function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_UPDATE_AUDITOR_H
#define PG_UPDATE_AUDITOR_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/**
 * Update information about an auditor that will audit this exchange.
 *
 * @param cls closure
 * @param auditor_pub key of the auditor (primary key for the existing record)
 * @param auditor_url base URL of the auditor's REST service, to be updated
 * @param auditor_name name of the auditor (for humans)
 * @param change_date date when the auditor status was last changed
 *                      (only to be used for replay detection)
 * @param enabled true to enable, false to disable
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_update_auditor (void *cls,
                       const struct TALER_AuditorPublicKeyP *auditor_pub,
                       const char *auditor_url,
                       const char *auditor_name,
                       struct GNUNET_TIME_Timestamp change_date,
                       bool enabled);

#endif
