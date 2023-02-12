/*
   This file is part of TALER
   Copyright (C) 2023 Taler Systems SA

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
 * @file exchangedb/pg_select_aml_threshold.h
 * @brief implementation of the select_aml_threshold function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_AML_THRESHOLD_H
#define PG_SELECT_AML_THRESHOLD_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Obtain the current AML threshold set for an account.
 *
 * @param cls closure
 * @param h_payto account for which the AML threshold is stored
 * @param[out] decision set to current AML decision
 * @param[out] threshold set to the existing threshold
 * @return database transaction status, 0 if no threshold was set
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_aml_threshold (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  enum TALER_AmlDecisionState *decision,
  struct TALER_Amount *threshold);


#endif
