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
 * @file exchangedb/pg_insert_aml_decision.h
 * @brief implementation of the insert_aml_decision function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_AML_DECISION_H
#define PG_INSERT_AML_DECISION_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Insert an AML decision. Inserts into AML history and insert or updates AML
 * status.
 *
 * @param cls closure
 * @param h_payto account for which the attribute data is stored
 * @param new_threshold new monthly threshold that would trigger an AML check
 * @param new_status AML decision status
 * @param decision_time when was the decision made
 * @param justification human-readable text justifying the decision
 * @param decider_pub public key of the staff member
 * @param decider_sig signature of the staff member
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_aml_decision (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const struct TALER_Amount *new_threshold,
  enum TALER_AmlDecisionState new_status,
  struct GNUNET_TIME_Absolute decision_time,
  const char *justification,
  const struct TALER_AmlOfficerPublicKeyP *decider_pub,
  const struct TALER_AmlOfficerSignatureP *decider_sig);


#endif
