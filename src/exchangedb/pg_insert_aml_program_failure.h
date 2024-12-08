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
 * @file exchangedb/pg_insert_aml_program_failure.h
 * @brief implementation of the insert_aml_program_failure function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_AML_PROGRAM_FAILURE_H
#define PG_INSERT_AML_PROGRAM_FAILURE_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Update AML program status to finished (and failed).
 *
 * @param cls closure
 * @param process_row KYC process row to update
 * @param h_payto account for which the attribute data is stored
 * @param error_message details about what went wrong
 * @param ec error code about the failure
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_aml_program_failure (
  void *cls,
  uint64_t process_row,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  const char *error_message,
  enum TALER_ErrorCode ec);


#endif
