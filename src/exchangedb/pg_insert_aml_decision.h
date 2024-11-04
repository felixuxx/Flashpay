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
 * @param payto_uri full URI of the account, optional,
 *    can be NULL if the backend already knows the account
 * @param h_payto account for which the attribute data is stored
 * @param decision_time when was the decision made
 * @param expiration_time when does the decision expire
 * @param properties JSON object with properties to set for the account
 * @param new_rules JSON array with new AML/KYC rules
 * @param to_investigate true if AML staff should look more into this account
 * @param new_measure_name name of the @a jmeasures measure that was triggered, or NULL for none
 * @param jmeasures a JSON with LegitimizationMeasures to apply to the
 *    account, or NULL to not apply any measure right now
 * @param justification human-readable text justifying the decision
 * @param decider_pub public key of the staff member
 * @param decider_sig signature of the staff member
 * @param[out] invalid_officer set to TRUE if @a decider_pub is not allowed to make decisions right now
 * @param[out] unknown_account set to TRUE if @a h_payto does not refer to a known account and @a jmeasures was given
 * @param[out] last_date set to the previous decision time;
 *   the INSERT is not performed if @a last_date is not before @a decision_time
 * @param[out] legitimization_measure_serial_id serial ID of the legitimization measures
 *   of the decision
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_aml_decision (
  void *cls,
  const char *payto_uri,
  const struct TALER_PaytoHashP *h_payto,
  struct GNUNET_TIME_Timestamp decision_time,
  struct GNUNET_TIME_Timestamp expiration_time,
  const json_t *properties,
  const json_t *new_rules,
  bool to_investigate,
  const char *new_measure_name,
  const json_t *jmeasures,
  const char *justification,
  const struct TALER_AmlOfficerPublicKeyP *decider_pub,
  const struct TALER_AmlOfficerSignatureP *decider_sig,
  bool *invalid_officer,
  bool *unknown_account,
  struct GNUNET_TIME_Timestamp *last_date,
  uint64_t *legitimization_measure_serial_id);


#endif
