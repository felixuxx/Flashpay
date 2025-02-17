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
 * @file exchangedb/pg_insert_aml_officer.h
 * @brief implementation of the insert_aml_officer function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_AML_OFFICER_H
#define PG_INSERT_AML_OFFICER_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Insert AML staff record.  If the time given in
 * @a last_change is before the previous change in the
 * database, only @e previous_change is returned and
 * no actual change is committed to the database.
 *
 * @param cls closure
 * @param decider_pub public key of the staff member
 * @param master_sig offline signature affirming the AML officer
 * @param decider_name full name of the staff member
 * @param is_active true to enable, false to set as inactive
 * @param read_only true to set read-only access
 * @param last_change when was the change made effective
 * @param[out] previous_change set to the time of the previous change
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_aml_officer (
  void *cls,
  const struct TALER_AmlOfficerPublicKeyP *decider_pub,
  const struct TALER_MasterSignatureP *master_sig,
  const char *decider_name,
  bool is_active,
  bool read_only,
  struct GNUNET_TIME_Timestamp last_change,
  struct GNUNET_TIME_Timestamp *previous_change);

#endif
