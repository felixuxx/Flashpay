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
 * @file exchangedb/pg_select_similar_kyc_attributes.h
 * @brief implementation of the select_similar_kyc_attributes function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_SELECT_SIMILAR_KYC_ATTRIBUTES_H
#define PG_SELECT_SIMILAR_KYC_ATTRIBUTES_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Lookup similar KYC attribute data.
 *
 * @param cls closure
 * @param h_payto account for which the attribute data is stored
 * @param kyc_prox key for similarity search
 * @param cb callback to invoke on each match
 * @param cb_cls closure for @a cb
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_select_similar_kyc_attributes (
  void *cls,
  const struct GNUNET_ShortHashCode *kyc_prox,
  TALER_EXCHANGEDB_AttributeCallback cb,
  void *cb_cls);

#endif
