/*
  This file is part of TALER
  Copyright (C) 2016-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero Public License for more details.

  You should have received a copy of the GNU Affero Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file auditor/report-lib.h
 * @brief helper library to facilitate generation of audit reports
 * @author Christian Grothoff
 */
#ifndef REPORT_LIB_H
#define REPORT_LIB_H

#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_lib.h"
#include "taler_json_lib.h"
#include "taler_bank_service.h"
#include "taler_signatures.h"


/**
 * Command-line option "-r": restart audit from scratch
 */
extern int restart;

/**
 * Handle to access the exchange's database.
 */
extern struct TALER_EXCHANGEDB_Plugin *edb;

/**
 * Which currency are we doing the audit for?
 */
extern char *currency;

/**
 * How many fractional digits does the currency use?
 */
extern struct TALER_Amount currency_round_unit;

/**
 * Our configuration.
 */
extern const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our session with the #edb.
 */
extern struct TALER_EXCHANGEDB_Session *esession;

/**
 * Handle to access the auditor's database.
 */
extern struct TALER_AUDITORDB_Plugin *adb;

/**
 * Our session with the #adb.
 */
extern struct TALER_AUDITORDB_Session *asession;

/**
 * Master public key of the exchange to audit.
 */
extern struct TALER_MasterPublicKeyP master_pub;

/**
 * At what time did the auditor process start?
 */
extern struct GNUNET_TIME_Absolute start_time;


/**
 * Convert absolute time to human-readable JSON string.
 *
 * @param at time to convert
 * @return human-readable string representing the time
 */
json_t *
json_from_time_abs_nbo (struct GNUNET_TIME_AbsoluteNBO at);


/**
 * Convert absolute time to human-readable JSON string.
 *
 * @param at time to convert
 * @return human-readable string representing the time
 */
json_t *
json_from_time_abs (struct GNUNET_TIME_Absolute at);


/**
 * Add @a object to the report @a array.  Fail hard if this fails.
 *
 * @param array report array to append @a object to
 * @param object object to append, should be check that it is not NULL
 */
void
report (json_t *array,
        json_t *object);


/**
 * Obtain information about a @a denom_pub.
 *
 * @param dh hash of the denomination public key to look up
 * @param[out] issue set to detailed information about @a denom_pub, NULL if not found, must
 *                 NOT be freed by caller
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
get_denomination_info_by_hash (
  const struct GNUNET_HashCode *dh,
  const struct TALER_DenominationKeyValidityPS **issue);


/**
 * Obtain information about a @a denom_pub.
 *
 * @param denom_pub key to look up
 * @param[out] issue set to detailed information about @a denom_pub, NULL if not found, must
 *                 NOT be freed by caller
 * @param[out] dh set to the hash of @a denom_pub, may be NULL
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
get_denomination_info (
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_DenominationKeyValidityPS **issue,
  struct GNUNET_HashCode *dh);

/**
 * Type of an analysis function.  Each analysis function runs in
 * its own transaction scope and must thus be internally consistent.
 *
 * @param cls closure
 * @return transaction status code
 */
typedef enum GNUNET_DB_QueryStatus
(*Analysis)(void *cls);


/**
 * Perform the given @a analysis within a transaction scope.
 * Commit on success.
 *
 * @param analysis analysis to run
 * @param analysis_cls closure for @a analysis
 * @return #GNUNET_OK if @a analysis succeessfully committed,
 *         #GNUNET_NO if we had an error on commit (retry may help)
 *         #GNUNET_SYSERR on hard errors
 */
int
transact (Analysis analysis,
          void *analysis_cls);


/**
 * Initialize DB sessions and run the analysis.
 *
 * @param ana analysis to run
 * @param ana_cls closure for @ana
 * @return #GNUNET_OK on success
 */
int
setup_sessions_and_run (Analysis ana,
                        void *ana_cls);


int
setup_globals (const struct GNUNET_CONFIGURATION_Handle *c);


void
finish_report (json_t *report);

#endif
