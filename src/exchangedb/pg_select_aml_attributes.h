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
 * @file exchangedb/pg_select_aml_attributes.h
 * @brief implementation of the select_aml_attributes function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_AML_ATTRIBUTES_H
#define PG_SELECT_AML_ATTRIBUTES_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Lookup AML attributes of a particular account.
 *
 * @param cls closure
 * @param h_payto which account should we return attributes for
 * @param offset row to start from
 * @param limit how many records to return (negative
 *        to go back in time, positive to go forward)
 * @param cb callback to invoke on each match
 * @param cb_cls closure for @a cb
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_aml_attributes (
  void *cls,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  uint64_t offset,
  int64_t limit,
  TALER_EXCHANGEDB_AmlAttributeCallback cb,
  void *cb_cls);


#endif
