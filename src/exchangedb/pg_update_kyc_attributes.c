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
 * @file exchangedb/pg_update_kyc_attributes.c
 * @brief Implementation of the update_kyc_attributes function for Postgres
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_error_codes.h"
#include "taler_dbevents.h"
#include "taler_pq_lib.h"
#include "pg_update_kyc_attributes.h"
#include "pg_helper.h"


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
  const void *enc_attributes)
{
  GNUNET_break (0); // FIXME: not implemeted!
  return GNUNET_DB_STATUS_HARD_ERROR;
}
