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
 * @file exchangedb/pg_get_policy_details.h
 * @brief implementation of the get_policy_details function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_GET_POLICY_DETAILS_H
#define PG_GET_POLICY_DETAILS_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/* Get the details of a policy, referenced by its hash code
 *
 * @param cls the `struct PostgresClosure` with the plugin-specific state
 * @param hc The hash code under which the details to a particular policy should be found
 * @param[out] details The found details
 * @return query execution status
 * */
enum GNUNET_DB_QueryStatus
TEH_PG_get_policy_details (
  void *cls,
  const struct GNUNET_HashCode *hc,
  struct TALER_PolicyDetails *details);

#endif
