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
 * @file exchangedb/pg_insert_auditor.h
 * @brief implementation of the insert_auditor function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_AUDITOR_H
#define PG_INSERT_AUDITOR_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Insert information about an auditor that will audit this exchange.
 *
 * @param cls closure
 * @param auditor_pub key of the auditor
 * @param auditor_url base URL of the auditor's REST service
 * @param auditor_name name of the auditor (for humans)
 * @param start_date date when the auditor was added by the offline system
 *                      (only to be used for replay detection)
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_auditor (void *cls,
                         const struct TALER_AuditorPublicKeyP *auditor_pub,
                         const char *auditor_url,
                         const char *auditor_name,
                       struct GNUNET_TIME_Timestamp start_date);
#endif
