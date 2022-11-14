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
 * @file exchangedb/pg_lookup_auditor_timestamp.h
 * @brief implementation of the lookup_auditor_timestamp function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_LOOKUP_AUDITOR_TIMESTAMP_H
#define PG_LOOKUP_AUDITOR_TIMESTAMP_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Check the last date an auditor was modified.
 *
 * @param cls closure
 * @param auditor_pub key to look up information for
 * @param[out] last_date last modification date to auditor status
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_lookup_auditor_timestamp (
  void *cls,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  struct GNUNET_TIME_Timestamp *last_date);
#endif
