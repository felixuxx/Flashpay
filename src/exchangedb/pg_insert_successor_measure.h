/*
   This file is part of TALER
   Copyright (C) 2022, 2023 Taler Systems SA

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
 * @file exchangedb/pg_insert_successor_measure.h
 * @brief implementation of the insert_successor_measure function for Postgres
 * @author Florian Dold
 */
#ifndef PG_INSERT_SUCCESSOR_MEASURE_H
#define PG_INSERT_SUCCESSOR_MEASURE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

enum GNUNET_DB_QueryStatus
TEH_PG_insert_successor_measure (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp decision_time,
  const char *new_measure_name,
  const json_t *jmeasures,
  bool *unknown_account,
  struct GNUNET_TIME_Timestamp *last_date);


#endif
