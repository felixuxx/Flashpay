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
 * @file exchangedb/pg_insert_auditor_denom_sig.h
 * @brief implementation of the insert_auditor_denom_sig function for Postgres
 * @author Christian Grothoff
 */
#ifndef PG_INSERT_AUDITOR_DENOM_SIG_H
#define PG_INSERT_AUDITOR_DENOM_SIG_H

#include "taler_util.h"
#include "taler_json_lib.h"
#include "taler_exchangedb_plugin.h"

/**
 * Insert information about an auditor auditing a denomination key.
 *
 * @param cls closure
 * @param h_denom_pub the audited denomination
 * @param auditor_pub the auditor's key
 * @param auditor_sig signature affirming the auditor's audit activity
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TEH_PG_insert_auditor_denom_sig (
  void *cls,
  const struct TALER_DenominationHashP *h_denom_pub,
  const struct TALER_AuditorPublicKeyP *auditor_pub,
  const struct TALER_AuditorSignatureP *auditor_sig);
#endif
