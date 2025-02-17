/*
  This file is part of TALER
  Copyright (C) 2016-2024 Taler Systems SA

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
 * Macro to use to access progress point value @a name.
 */
#define TALER_ARL_USE_PP(name) TAC_ ## name

/**
 * Macro to use to declare progress point value @a name.
 */
#define TALER_ARL_DEF_PP(name)                  \
        uint64_t TALER_ARL_USE_PP (name) = 0

/**
 * Macro to use to GET progress point value @a name from DB.
 */
#define TALER_ARL_GET_PP(name)                  \
        TALER_S (name), &TALER_ARL_USE_PP (name)

/**
 * Macro to use to SET progress point value @a name in DB.
 */
#define TALER_ARL_SET_PP(name)                  \
        TALER_S (name), TALER_ARL_USE_PP (name)

/**
 * Macro to use to access amount balance @a name.
 */
#define TALER_ARL_USE_AB(name) TAC_ ## name

/**
 * Macro to use to declare amount balance @a name.
 */
#define TALER_ARL_DEF_AB(name)                  \
        struct TALER_Amount TALER_ARL_USE_AB (name)

/**
 * Macro to use to GET amount balance @a name from DB.
 */
#define TALER_ARL_GET_AB(name)                  \
        TALER_S (name), &TALER_ARL_USE_AB (name)

/**
 * Macro to use to SET amount balance @a name in DB.
 */
#define TALER_ARL_SET_AB(name)                  \
        TALER_S (name), &TALER_ARL_USE_AB (name)


/**
 * Command-line option "-r": restart audit from scratch
 */
extern int TALER_ARL_restart;

/**
 * Handle to access the exchange's database.
 */
extern struct TALER_EXCHANGEDB_Plugin *TALER_ARL_edb;

/**
 * Which currency are we doing the audit for?
 */
extern char *TALER_ARL_currency;

/**
 * How many fractional digits does the currency use?
 */
extern struct TALER_Amount TALER_ARL_currency_round_unit;

/**
 * Our configuration.
 */
extern const struct GNUNET_CONFIGURATION_Handle *TALER_ARL_cfg;

/**
 * Handle to access the auditor's database.
 */
extern struct TALER_AUDITORDB_Plugin *TALER_ARL_adb;

/**
 * Master public key of the exchange to audit.
 */
extern struct TALER_MasterPublicKeyP TALER_ARL_master_pub;

/**
 * Public key of the auditor.
 */
extern struct TALER_AuditorPublicKeyP TALER_ARL_auditor_pub;

/**
 * REST API endpoint of the auditor.
 */
extern char *TALER_ARL_auditor_url;

/**
 * REST API endpoint of the exchange.
 */
extern char *TALER_ARL_exchange_url;

/**
 * At what time did the auditor process start?
 */
extern struct GNUNET_TIME_Absolute start_time;


/**
 * Obtain information about a @a denom_pub.
 *
 * @param dh hash of the denomination public key to look up
 * @param[out] issuep set to detailed information about @a denom_pub, NULL if not found, must
 *                 NOT be freed by caller
 * @return transaction status code
 */
enum GNUNET_DB_QueryStatus
TALER_ARL_get_denomination_info_by_hash (
  const struct TALER_DenominationHashP *dh,
  const struct TALER_EXCHANGEDB_DenominationKeyInformation **issuep);


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
TALER_ARL_get_denomination_info (
  const struct TALER_DenominationPublicKey *denom_pub,
  const struct TALER_EXCHANGEDB_DenominationKeyInformation **issue,
  struct TALER_DenominationHashP *dh);


/**
 * Type of an analysis function.  Each analysis function runs in
 * its own transaction scope and must thus be internally consistent.
 *
 * @param cls closure
 * @return transaction status code
 */
typedef enum GNUNET_DB_QueryStatus
(*TALER_ARL_Analysis)(void *cls);


/**
 * Perform addition of amounts.  If the addition fails, logs
 * a detailed error and calls exit() to terminate the process (!).
 *
 * Do not call this function directly, use #TALER_ARL_amount_add().
 *
 * @param[out] sum where to store @a a1 + @a a2, set to "invalid" on overflow
 * @param a1 first amount to add
 * @param a2 second amount to add
 * @param filename where is the addition called
 * @param functionname name of the function where the addition is called
 * @param line line number of the addition
 */
void
TALER_ARL_amount_add_ (struct TALER_Amount *sum,
                       const struct TALER_Amount *a1,
                       const struct TALER_Amount *a2,
                       const char *filename,
                       const char *functionname,
                       unsigned int line);


/**
 * Perform addition of amounts.  If the addition fails, logs
 * a detailed error and calls exit() to terminate the process (!).
 *
 * @param[out] sum where to store @a a1 + @a a2, set to "invalid" on overflow
 * @param a1 first amount to add
 * @param a2 second amount to add
 */
#define TALER_ARL_amount_add(sum,a1,a2) \
        TALER_ARL_amount_add_ (sum, a1, a2, __FILE__, __FUNCTION__, __LINE__)


/**
 * Perform subtraction of amounts where the result "cannot" be negative. If the
 * subtraction fails, logs a detailed error and calls exit() to terminate the
 * process (!).
 *
 * Do not call this function directly, use #TALER_ARL_amount_subtract().
 *
 * @param[out] diff where to store (@a a1 - @a a2)
 * @param a1 amount to subtract from
 * @param a2 amount to subtract
 * @param filename where is the addition called
 * @param functionname name of the function where the addition is called
 * @param line line number of the addition
 */
void
TALER_ARL_amount_subtract_ (struct TALER_Amount *diff,
                            const struct TALER_Amount *a1,
                            const struct TALER_Amount *a2,
                            const char *filename,
                            const char *functionname,
                            unsigned int line);


/**
 * Perform subtraction of amounts where the result "cannot" be negative. If
 * the subtraction fails, logs a detailed error and calls exit() to terminate
 * the process (!).
 *
 * @param[out] diff where to store (@a a1 - @a a2)
 * @param a1 amount to subtract from
 * @param a2 amount to subtract
 */
#define TALER_ARL_amount_subtract(diff,a1,a2) \
        TALER_ARL_amount_subtract_ (diff, a1, a2, __FILE__, __FUNCTION__, \
                                    __LINE__)


/**
 * Possible outcomes of #TALER_ARL_amount_subtract_neg().
 */
enum TALER_ARL_SubtractionResult
{
  /**
   * Note that in this case no actual result was computed.
   */
  TALER_ARL_SR_INVALID_NEGATIVE = -1,

  /**
   * The result of the subtraction is exactly zero.
   */
  TALER_ARL_SR_ZERO = 0,

  /**
   * The result of the subtraction is a positive value.
   */
  TALER_ARL_SR_POSITIVE = 1
};


/**
 * Perform subtraction of amounts. Negative results should be signalled by the
 * return value (leaving @a diff set to 'invalid'). If the subtraction fails
 * for other reasons (currency mismatch, normalization failure), logs a
 * detailed error and calls exit() to terminate the process (!).
 *
 * Do not call this function directly, use #TALER_ARL_amount_subtract_neg().
 *
 * @param[out] diff where to store (@a a1 - @a a2)
 * @param a1 amount to subtract from
 * @param a2 amount to subtract
 * @param filename where is the addition called
 * @param functionname name of the function where the addition is called
 * @param line line number of the addition
 * @return #TALER_ARL_SR_INVALID_NEGATIVE if the result was negative (and @a diff is now invalid),
 *         #TALER_ARL_SR_ZERO if the result was zero,
 *         #TALER_ARL_SR_POSITIVE if the result is positive
 */
enum TALER_ARL_SubtractionResult
TALER_ARL_amount_subtract_neg_ (struct TALER_Amount *diff,
                                const struct TALER_Amount *a1,
                                const struct TALER_Amount *a2,
                                const char *filename,
                                const char *functionname,
                                unsigned int line);


/**
 * Perform subtraction of amounts.  Negative results should be signalled by
 * the return value (leaving @a diff set to 'invalid'). If the subtraction
 * fails for other reasons (currency mismatch, normalization failure), logs a
 * detailed error and calls exit() to terminate the process (!).
 *
 * @param[out] diff where to store (@a a1 - @a a2)
 * @param a1 amount to subtract from
 * @param a2 amount to subtract
 * @return #TALER_ARL_SR_INVALID_NEGATIVE if the result was negative (and @a diff is now invalid),
 *         #TALER_ARL_SR_ZERO if the result was zero,
 *         #TALER_ARL_SR_POSITIVE if the result is positive
 */
#define TALER_ARL_amount_subtract_neg(diff,a1,a2) \
        TALER_ARL_amount_subtract_neg_ (diff, a1, a2, __FILE__, __FUNCTION__, \
                                        __LINE__)


/**
 * Initialize DB sessions and run the analysis.
 *
 * @param ana analysis to run
 * @param ana_cls closure for @a ana
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_ARL_setup_sessions_and_run (TALER_ARL_Analysis ana,
                                  void *ana_cls);


/**
 * Setup global variables based on configuration.
 *
 * @param c configuration to use
 * @return #GNUNET_OK on success
 */
enum GNUNET_GenericReturnValue
TALER_ARL_init (const struct GNUNET_CONFIGURATION_Handle *c);


/**
 * Close connections to the database.
 */
void
TALER_ARL_done (void);

#endif
