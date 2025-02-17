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
 * @file exchangedb/pg_persist_kyc_attributes.h
 * @brief implementation of the persist_kyc_attributes function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_PERSIST_KYC_ATTRIBUTES_H
#define PG_PERSIST_KYC_ATTRIBUTES_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Store KYC attribute data.
 *
 * @param cls closure
 * @param process_row KYC process row to update
 * @param h_payto account for which the attribute data is stored
 * @param provider_name name of the provider that provided the attributes
 * @param provider_account_id provider account ID
 * @param provider_legitimization_id provider legitimization ID
 * @param birthday birthdate of user, in days after 1990, or 0 if unknown or definitively adult
 * @param expiration_time when does the data expire
 * @param enc_attributes_size number of bytes in @a enc_attributes
 * @param enc_attributes encrypted attribute data
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_persist_kyc_attributes (
  void *cls,
  uint64_t process_row,
  const struct TALER_NormalizedPaytoHashP *h_payto,
  const char *provider_name,
  const char *provider_account_id,
  const char *provider_legitimization_id,
  uint32_t birthday,
  struct GNUNET_TIME_Absolute expiration_time,
  size_t enc_attributes_size,
  const void *enc_attributes);


#endif
