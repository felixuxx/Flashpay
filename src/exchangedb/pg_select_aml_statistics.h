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
 * @file exchangedb/pg_select_aml_statistics.h
 * @brief implementation of the select_aml_statistics function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_AML_STATISTICS_H
#define PG_SELECT_AML_STATISTICS_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Obtain the AML statistics for a given key and
 * timeframe.
 *
 * @param cls closure
 * @param name name of the statistic
 * @param start_date start of time range
 * @param end_date end of time range
 * @param[out] cnt number of events in this time range
 * @return database transaction status, 0 if no threshold was set
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_aml_statistics (
  void *cls,
  const char *name,
  struct GNUNET_TIME_Timestamp start_date,
  struct GNUNET_TIME_Timestamp end_date,
  uint64_t *cnt);

#endif
