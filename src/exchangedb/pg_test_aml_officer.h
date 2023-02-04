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
 * @file exchangedb/pg_test_aml_officer.h
 * @brief implementation of the test_aml_officer function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_TEST_AML_OFFICER_H
#define PG_TEST_AML_OFFICER_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"


/**
 * Test if the given AML staff member is active
 * (at least read-only).
 *
 * @param cls closure
 * @param decider_pub public key of the staff member
 * @return database transaction status, if member is unknown or not active, 1 if member is active
 */
enum GNUNET_DB_QueryStatus
TEH_PG_test_aml_officer (
  void *cls,
  const struct TALER_AmlOfficerPublicKeyP *decider_pub);


#endif
