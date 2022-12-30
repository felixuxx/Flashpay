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
 * @file exchangedb/pg_update_kyc_attributes.h
 * @brief implementation of the update_kyc_attributes function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_UPDATE_KYC_ATTRIBUTES_H
#define PG_UPDATE_KYC_ATTRIBUTES_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Update KYC attribute data.
 *
 * @param cls closure
 * @param h_payto account for which the attribute data is stored
 * @param kyc_prox key for similarity search
 * @param provider_section provider that must be checked
 * @param birthdate birthdate of user, in format YYYY-MM-DD; can be NULL;
 *        digits can be 0 if exact day, month or year are unknown
 * @param collection_time when was the data collected
 * @param expiration_time when does the data expire
 * @param enc_attributes_size number of bytes in @a enc_attributes
 * @param enc_attributes encrypted attribute data
 * @return database transaction status
 */
enum GNUNET_DB_QueryStatus
TEH_PG_update_kyc_attributes (
  void *cls,
  const struct TALER_PaytoHashP *h_payto,
  const struct GNUNET_ShortHashCode *kyc_prox,
  const char *provider_section,
  const char *birthdate,
  struct GNUNET_TIME_Timestamp collection_time,
  struct GNUNET_TIME_Timestamp expiration_time,
  size_t enc_attributes_size,
  const void *enc_attributes);


#endif
