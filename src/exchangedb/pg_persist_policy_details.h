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
 * @file exchangedb/pg_persist_policy_details.h
 * @brief implementation of the persist_policy_details function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_PERSIST_POLICY_DETAILS_H
#define PG_PERSIST_POLICY_DETAILS_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"
/* Persist the details to a policy in the policy_details table.  If there
 * already exists a policy, update the fields accordingly.
 *
 * @param details The policy details that should be persisted.  If an entry for
 *        the given details->hash_code exists, the values will be updated.
 * @param[out] policy_details_serial_id The row ID of the policy details
 * @param[out] accumulated_total The total amount accumulated in that policy
 * @param[out] fulfillment_state The state of policy.  If the state was Insufficient prior to the call and the provided deposit raises the accumulated_total above the commitment, it will be set to Ready.
 * @return query execution status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_persist_policy_details (
  void *cls,
  const struct TALER_PolicyDetails *details,
  uint64_t *policy_details_serial_id,
  struct TALER_Amount *accumulated_total,
  enum TALER_PolicyFulfillmentState *fulfillment_state);

#endif
