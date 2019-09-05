/*
  This file is part of TALER
  Copyright (C) 2016, 2017, 2018, 2019 Taler Systems SA

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
 * @file auditor/taler-auditor.c
 * @brief audits an exchange database.
 * @author Christian Grothoff
 *
 * NOTE:
 * - This auditor does not verify that 'reserves_in' actually matches
 *   the wire transfers from the bank. This needs to be checked separately!
 * - Similarly, we do not check that the outgoing wire transfers match those
 *   given in the 'wire_out' table. This needs to be checked separately!
 *
 * TODO:
 * - reorganize: different passes are combined in one tool and one
 *   file here, we should split this up!
 * - likely should do an iteration over known_coins instead of checking
 *   those signatures again and again
 * - might want to bite the bullet and do asynchronous signature
 *   verification to improve parallelism / speed -- we'll need to scale
 *   this eventually anyway!
 *
 * KNOWN BUGS:
 * - error handling if denomination keys are used that are not known to the
 *   auditor is, eh, awful / non-existent. We just throw the DB's constraint
 *   violation back at the user. Great UX.
 *
 * UNDECIDED:
 * - do we care about checking the 'done' flag in deposit_cb?
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include "taler_auditordb_plugin.h"
#include "taler_exchangedb_plugin.h"
#include "taler_json_lib.h"
#include "taler_wire_lib.h"
#include "taler_signatures.h"


/**
 * How many coin histories do we keep in RAM at any given point in
 * time? Used bound memory consumption of the auditor. Larger values
 * reduce database accesses.
 *
 * Set to a VERY low value here for testing. Practical values may be
 * in the millions.
 */
#define MAX_COIN_SUMMARIES 4

/**
 * Use a 1 day grace period to deal with clocks not being perfectly synchronized.
 */
#define DEPOSIT_GRACE_PERIOD GNUNET_TIME_UNIT_DAYS

/**
 * Use a 1 day grace period to deal with clocks not being perfectly synchronized.
 */
#define CLOSING_GRACE_PERIOD GNUNET_TIME_UNIT_DAYS

/**
 * Return value from main().
 */
static int global_ret;

/**
 * Command-line option "-r": restart audit from scratch
 */
static int restart;

/**
 * Handle to access the exchange's database.
 */
static struct TALER_EXCHANGEDB_Plugin *edb;

/**
 * Which currency are we doing the audit for?
 */
static char *currency;

/**
 * Our configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Our session with the #edb.
 */
static struct TALER_EXCHANGEDB_Session *esession;

/**
 * Handle to access the auditor's database.
 */
static struct TALER_AUDITORDB_Plugin *adb;

/**
 * Our session with the #adb.
 */
static struct TALER_AUDITORDB_Session *asession;

/**
 * After how long should idle reserves be closed?
 */
static struct GNUNET_TIME_Relative idle_reserve_expiration_time;

/**
 * Master public key of the exchange to audit.
 */
static struct TALER_MasterPublicKeyP master_pub;

/**
 * Checkpointing our progress for reserves.
 */
static struct TALER_AUDITORDB_ProgressPointReserve ppr;

/**
 * Checkpointing our progress for aggregations.
 */
static struct TALER_AUDITORDB_ProgressPointAggregation ppa;

/**
 * Checkpointing our progress for coins.
 */
static struct TALER_AUDITORDB_ProgressPointCoin ppc;

/**
 * Array of reports about denomination keys with an
 * emergency (more value deposited than withdrawn)
 */
static json_t *report_emergencies;

/**
 * Array of reports about denomination keys with an
 * emergency (more coins deposited than withdrawn)
 */
static json_t *report_emergencies_by_count;

/**
 * Array of reports about row inconsitencies.
 */
static json_t *report_row_inconsistencies;

/**
 * Array of reports about the denomination key not being
 * valid at the time of withdrawal.
 */
static json_t *denomination_key_validity_withdraw_inconsistencies;

/**
 * Array of reports about reserve balance insufficient inconsitencies.
 */
static json_t *report_reserve_balance_insufficient_inconsistencies;

/**
 * Total amount reserves were charged beyond their balance.
 */
static struct TALER_Amount total_balance_insufficient_loss;

/**
 * Array of reports about reserve balance summary wrong in database.
 */
static json_t *report_reserve_balance_summary_wrong_inconsistencies;

/**
 * Total delta between expected and stored reserve balance summaries,
 * for positive deltas.
 */
static struct TALER_Amount total_balance_summary_delta_plus;

/**
 * Total delta between expected and stored reserve balance summaries,
 * for negative deltas.
 */
static struct TALER_Amount total_balance_summary_delta_minus;

/**
 * Array of reports about reserve's not being closed inconsitencies.
 */
static json_t *report_reserve_not_closed_inconsistencies;

/**
 * Total amount affected by reserves not having been closed on time.
 */
static struct TALER_Amount total_balance_reserve_not_closed;

/**
 * Array of reports about irregular wire out entries.
 */
static json_t *report_wire_out_inconsistencies;

/**
 * Array of reports about missing deposit confirmations.
 */
static json_t *report_deposit_confirmation_inconsistencies;

/**
 * Total delta between calculated and stored wire out transfers,
 * for positive deltas.
 */
static struct TALER_Amount total_wire_out_delta_plus;

/**
 * Total delta between calculated and stored wire out transfers
 * for negative deltas.
 */
static struct TALER_Amount total_wire_out_delta_minus;

/**
 * Array of reports about inconsistencies about coins.
 */
static json_t *report_coin_inconsistencies;

/**
 * Profits the exchange made by bad amount calculations on coins.
 */
static struct TALER_Amount total_coin_delta_plus;

/**
 * Losses the exchange made by bad amount calculations on coins.
 */
static struct TALER_Amount total_coin_delta_minus;

/**
 * Report about aggregate wire transfer fee profits.
 */
static json_t *report_aggregation_fee_balances;

/**
 * Report about amount calculation differences (causing profit
 * or loss at the exchange).
 */
static json_t *report_amount_arithmetic_inconsistencies;

/**
 * Array of reports about wire fees being ambiguous in terms of validity periods.
 */
static json_t *report_fee_time_inconsistencies;

/**
 * Profits the exchange made by bad amount calculations.
 */
static struct TALER_Amount total_arithmetic_delta_plus;

/**
 * Losses the exchange made by bad amount calculations.
 */
static struct TALER_Amount total_arithmetic_delta_minus;

/**
 * Total number of deposit confirmations that we did not get.
 */
static json_int_t number_missed_deposit_confirmations;

/**
 * Total amount involved in deposit confirmations that we did not get.
 */
static struct TALER_Amount total_missed_deposit_confirmations;

/**
 * Total amount reported in all calls to #report_emergency().
 */
static struct TALER_Amount reported_emergency_sum;

/**
 * Expected balance in the escrow account.
 */
static struct TALER_Amount total_escrow_balance;

/**
 * Active risk exposure.
 */
static struct TALER_Amount total_risk;

/**
 * Actualized risk (= loss) from paybacks.
 */
static struct TALER_Amount total_payback_loss;

/**
 * Total withdraw fees earned.
 */
static struct TALER_Amount total_withdraw_fee_income;

/**
 * Total deposit fees earned.
 */
static struct TALER_Amount total_deposit_fee_income;

/**
 * Total melt fees earned.
 */
static struct TALER_Amount total_melt_fee_income;

/**
 * Total refund fees earned.
 */
static struct TALER_Amount total_refund_fee_income;

/**
 * Total aggregation fees earned.
 */
static struct TALER_Amount total_aggregation_fee_income;

/**
 * Array of reports about coin operations with bad signatures.
 */
static json_t *report_bad_sig_losses;

/**
 * Total amount lost by operations for which signatures were invalid.
 */
static struct TALER_Amount total_bad_sig_loss;

/**
 * Array of refresh transactions where the /refresh/reveal has not yet
 * happened (and may of course never happen).
 */
static json_t *report_refreshs_hanging;

/**
 * Total amount lost by operations for which signatures were invalid.
 */
static struct TALER_Amount total_refresh_hanging;


/* ********************************* helpers *************************** */

/**
 * Convert absolute time to human-readable JSON string.
 *
 * @param at time to convert
 * @return human-readable string representing the time
 */
static json_t *
json_from_time_abs_nbo (struct GNUNET_TIME_AbsoluteNBO at)
{
  return json_string
           (GNUNET_STRINGS_absolute_time_to_string
             (GNUNET_TIME_absolute_ntoh (at)));
}


/**
 * Convert absolute time to human-readable JSON string.
 *
 * @param at time to convert
 * @return human-readable string representing the time
 */
static json_t *
json_from_time_abs (struct GNUNET_TIME_Absolute at)
{
  return json_string
           (GNUNET_STRINGS_absolute_time_to_string (at));
}


/* ***************************** Report logic **************************** */


/**
 * Add @a object to the report @a array.  Fail hard if this fails.
 *
 * @param array report array to append @a object to
 * @param object object to append, should be check that it is not NULL
 */
static void
report (json_t *array,
        json_t *object)
{
  GNUNET_assert (NULL != object);
  GNUNET_assert (0 ==
                 json_array_append_new (array,
                                        object));
}


/**
 * Called in case we detect an emergency situation where the exchange
 * is paying out a larger amount on a denomination than we issued in
 * that denomination.  This means that the exchange's private keys
 * might have gotten compromised, and that we need to trigger an
 * emergency request to all wallets to deposit pending coins for the
 * denomination (and as an exchange suffer a huge financial loss).
 *
 * @param dki denomination key where the loss was detected
 * @param risk maximum risk that might have just become real (coins created by this @a dki)
 * @param loss actual losses already (actualized before denomination was revoked)
 */
static void
report_emergency_by_amount (const struct
                            TALER_EXCHANGEDB_DenominationKeyInformationP *dki,
                            const struct TALER_Amount *risk,
                            const struct TALER_Amount *loss)
{
  report (report_emergencies,
          json_pack ("{s:o, s:o, s:o, s:o, s:o, s:o}",
                     "denompub_hash",
                     GNUNET_JSON_from_data_auto (&dki->properties.denom_hash),
                     "denom_risk",
                     TALER_JSON_from_amount (risk),
                     "denom_loss",
                     TALER_JSON_from_amount (loss),
                     "start",
                     json_from_time_abs_nbo (dki->properties.start),
                     "deposit_end",
                     json_from_time_abs_nbo (dki->properties.expire_deposit),
                     "value",
                     TALER_JSON_from_amount_nbo (&dki->properties.value)));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_add (&reported_emergency_sum,
                                   &reported_emergency_sum,
                                   risk));
}


/**
 * Called in case we detect an emergency situation where the exchange
 * is paying out a larger NUMBER of coins of a denomination than we
 * issued in that denomination.  This means that the exchange's
 * private keys might have gotten compromised, and that we need to
 * trigger an emergency request to all wallets to deposit pending
 * coins for the denomination (and as an exchange suffer a huge
 * financial loss).
 *
 * @param dki denomination key where the loss was detected
 * @param num_issued number of coins that were issued
 * @param num_known number of coins that have been deposited
 * @param risk amount that is at risk
 */
static void
report_emergency_by_count (const struct
                           TALER_EXCHANGEDB_DenominationKeyInformationP *dki,
                           uint64_t num_issued,
                           uint64_t num_known,
                           const struct TALER_Amount *risk)
{
  report (report_emergencies_by_count,
          json_pack ("{s:o, s:I, s:I, s:o, s:o, s:o, s:o}",
                     "denompub_hash",
                     GNUNET_JSON_from_data_auto (&dki->properties.denom_hash),
                     "num_issued",
                     (json_int_t) num_issued,
                     "num_known",
                     (json_int_t) num_known,
                     "denom_risk",
                     TALER_JSON_from_amount (risk),
                     "start",
                     json_from_time_abs_nbo (dki->properties.start),
                     "deposit_end",
                     json_from_time_abs_nbo (dki->properties.expire_deposit),
                     "value",
                     TALER_JSON_from_amount_nbo (&dki->properties.value)));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_add (&reported_emergency_sum,
                                   &reported_emergency_sum,
                                   risk));
}


/**
 * Report a (serious) inconsistency in the exchange's database with
 * respect to calculations involving amounts.
 *
 * @param operation what operation had the inconsistency
 * @param rowid affected row, UINT64_MAX if row is missing
 * @param exchange amount calculated by exchange
 * @param auditor amount calculated by auditor
 * @param proftable 1 if @a exchange being larger than @a auditor is
 *           profitable for the exchange for this operation,
 *           -1 if @a exchange being smaller than @a auditor is
 *           profitable for the exchange, and 0 if it is unclear
 */
static void
report_amount_arithmetic_inconsistency (const char *operation,
                                        uint64_t rowid,
                                        const struct TALER_Amount *exchange,
                                        const struct TALER_Amount *auditor,
                                        int profitable)
{
  struct TALER_Amount delta;
  struct TALER_Amount *target;

  if (0 < TALER_amount_cmp (exchange,
                            auditor))
  {
    /* exchange > auditor */
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_subtract (&delta,
                                         exchange,
                                         auditor));
  }
  else
  {
    /* auditor < exchange */
    profitable = -profitable;
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_subtract (&delta,
                                         auditor,
                                         exchange));
  }
  report (report_amount_arithmetic_inconsistencies,
          json_pack ("{s:s, s:I, s:o, s:o, s:I}",
                     "operation", operation,
                     "rowid", (json_int_t) rowid,
                     "exchange", TALER_JSON_from_amount (exchange),
                     "auditor", TALER_JSON_from_amount (auditor),
                     "profitable", (json_int_t) profitable));
  if (0 != profitable)
  {
    target = (1 == profitable)
             ? &total_arithmetic_delta_plus
             : &total_arithmetic_delta_minus;
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (target,
                                    target,
                                    &delta));
  }
}


/**
 * Report a (serious) inconsistency in the exchange's database with
 * respect to calculations involving amounts of a coin.
 *
 * @param operation what operation had the inconsistency
 * @param coin_pub affected coin
 * @param exchange amount calculated by exchange
 * @param auditor amount calculated by auditor
 * @param proftable 1 if @a exchange being larger than @a auditor is
 *           profitable for the exchange for this operation,
 *           -1 if @a exchange being smaller than @a auditor is
 *           profitable for the exchange, and 0 if it is unclear
 */
static void
report_coin_arithmetic_inconsistency (const char *operation,
                                      const struct
                                      TALER_CoinSpendPublicKeyP *coin_pub,
                                      const struct TALER_Amount *exchange,
                                      const struct TALER_Amount *auditor,
                                      int profitable)
{
  struct TALER_Amount delta;
  struct TALER_Amount *target;

  if (0 < TALER_amount_cmp (exchange,
                            auditor))
  {
    /* exchange > auditor */
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_subtract (&delta,
                                         exchange,
                                         auditor));
  }
  else
  {
    /* auditor < exchange */
    profitable = -profitable;
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_subtract (&delta,
                                         auditor,
                                         exchange));
  }
  report (report_coin_inconsistencies,
          json_pack ("{s:s, s:o, s:o, s:o, s:I}",
                     "operation", operation,
                     "coin_pub", GNUNET_JSON_from_data_auto (coin_pub),
                     "exchange", TALER_JSON_from_amount (exchange),
                     "auditor", TALER_JSON_from_amount (auditor),
                     "profitable", (json_int_t) profitable));
  if (0 != profitable)
  {
    target = (1 == profitable)
             ? &total_coin_delta_plus
             : &total_coin_delta_minus;
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (target,
                                    target,
                                    &delta));
  }
}


/**
 * Report a (serious) inconsistency in the exchange's database.
 *
 * @param table affected table
 * @param rowid affected row, UINT64_MAX if row is missing
 * @param diagnostic message explaining the problem
 */
static void
report_row_inconsistency (const char *table,
                          uint64_t rowid,
                          const char *diagnostic)
{
  report (report_row_inconsistencies,
          json_pack ("{s:s, s:I, s:s}",
                     "table", table,
                     "row", (json_int_t) rowid,
                     "diagnostic", diagnostic));
}


/* ************************* Transaction-global state ************************ */

/**
 * Results about denominations, cached per-transaction.
 */
static struct GNUNET_CONTAINER_MultiHashMap *denominations;


/**
 * Obtain information about a @a denom_pub.
 *
 * @param dh hash of the denomination public key to look up
 * @param[out] dki set to detailed information about @a denom_pub, NULL if not found, must
 *                 NOT be freed by caller
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
get_denomination_info_by_hash (const struct GNUNET_HashCode *dh,
                               const struct
                               TALER_EXCHANGEDB_DenominationKeyInformationP **
                               dki)
{
  struct TALER_EXCHANGEDB_DenominationKeyInformationP *dkip;
  enum GNUNET_DB_QueryStatus qs;

  if (NULL == denominations)
    denominations = GNUNET_CONTAINER_multihashmap_create (256,
                                                          GNUNET_NO);
  dkip = GNUNET_CONTAINER_multihashmap_get (denominations,
                                            dh);
  if (NULL != dkip)
  {
    /* cache hit */
    *dki = dkip;
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
  dkip = GNUNET_new (struct TALER_EXCHANGEDB_DenominationKeyInformationP);
  qs = edb->get_denomination_info (edb->cls,
                                   esession,
                                   dh,
                                   dkip);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_free (dkip);
    *dki = NULL;
    return qs;
  }
  {
    struct TALER_Amount value;

    TALER_amount_ntoh (&value,
                       &dkip->properties.value);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Tracking denomination `%s' (%s)\n",
                GNUNET_h2s (dh),
                TALER_amount2s (&value));
    TALER_amount_ntoh (&value,
                       &dkip->properties.fee_withdraw);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Withdraw fee is %s\n",
                TALER_amount2s (&value));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Start time is %s\n",
                GNUNET_STRINGS_absolute_time_to_string
                  (GNUNET_TIME_absolute_ntoh (dkip->properties.start)));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Expire deposit time is %s\n",
                GNUNET_STRINGS_absolute_time_to_string
                  (GNUNET_TIME_absolute_ntoh (
                    dkip->properties.expire_deposit)));
  }
  *dki = dkip;
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_put (denominations,
                                                    dh,
                                                    dkip,
                                                    GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Obtain information about a @a denom_pub.
 *
 * @param denom_pub key to look up
 * @param[out] dki set to detailed information about @a denom_pub, NULL if not found, must
 *                 NOT be freed by caller
 * @param[out] dh set to the hash of @a denom_pub, may be NULL
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
get_denomination_info (const struct TALER_DenominationPublicKey *denom_pub,
                       const struct
                       TALER_EXCHANGEDB_DenominationKeyInformationP **dki,
                       struct GNUNET_HashCode *dh)
{
  struct GNUNET_HashCode hc;

  if (NULL == dh)
    dh = &hc;
  GNUNET_CRYPTO_rsa_public_key_hash (denom_pub->rsa_public_key,
                                     dh);
  return get_denomination_info_by_hash (dh,
                                        dki);
}


/**
 * Free denomination key information.
 *
 * @param cls NULL
 * @param key unused
 * @param value the `struct TALER_EXCHANGEDB_DenominationKeyInformationP *` to free
 * @return #GNUNET_OK (continue to iterate)
 */
static int
free_dk_info (void *cls,
              const struct GNUNET_HashCode *key,
              void *value)
{
  struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki = value;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Done with denomination `%s'\n",
              GNUNET_h2s (key));
  GNUNET_free (dki);
  return GNUNET_OK;
}


/**
 * Purge transaction global state cache, the transaction is
 * done and we do not want to have the state cross over to
 * the next transaction.
 */
static void
clear_transaction_state_cache ()
{
  if (NULL == denominations)
    return;
  GNUNET_CONTAINER_multihashmap_iterate (denominations,
                                         &free_dk_info,
                                         NULL);
  GNUNET_CONTAINER_multihashmap_destroy (denominations);
  denominations = NULL;
}


/* ***************************** Analyze reserves ************************ */
/* This logic checks the reserves_in, reserves_out and reserves-tables */

/**
 * Summary data we keep per reserve.
 */
struct ReserveSummary
{
  /**
   * Public key of the reserve.
   * Always set when the struct is first initialized.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Sum of all incoming transfers during this transaction.
   * Updated only in #handle_reserve_in().
   */
  struct TALER_Amount total_in;

  /**
   * Sum of all outgoing transfers during this transaction (includes fees).
   * Updated only in #handle_reserve_out().
   */
  struct TALER_Amount total_out;

  /**
   * Sum of withdraw fees encountered during this transaction.
   */
  struct TALER_Amount total_fee;

  /**
   * Previous balance of the reserve as remembered by the auditor.
   * (updated based on @e total_in and @e total_out at the end).
   */
  struct TALER_Amount a_balance;

  /**
   * Previous withdraw fee balance of the reserve, as remembered by the auditor.
   * (updated based on @e total_fee at the end).
   */
  struct TALER_Amount a_withdraw_fee_balance;

  /**
   * Previous reserve expiration data, as remembered by the auditor.
   * (updated on-the-fly in #handle_reserve_in()).
   */
  struct GNUNET_TIME_Absolute a_expiration_date;

  /**
   * Did we have a previous reserve info?  Used to decide between
   * UPDATE and INSERT later.  Initialized in
   * #load_auditor_reserve_summary() together with the a-* values
   * (if available).
   */
  int had_ri;

};


/**
 * Load the auditor's remembered state about the reserve into @a rs.
 * The "total_in" and "total_out" amounts of @a rs must already be
 * initialized (so we can determine the currency).
 *
 * @param[in,out] rs reserve summary to (fully) initialize
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
load_auditor_reserve_summary (struct ReserveSummary *rs)
{
  enum GNUNET_DB_QueryStatus qs;
  uint64_t rowid;

  qs = adb->get_reserve_info (adb->cls,
                              asession,
                              &rs->reserve_pub,
                              &master_pub,
                              &rowid,
                              &rs->a_balance,
                              &rs->a_withdraw_fee_balance,
                              &rs->a_expiration_date);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    rs->had_ri = GNUNET_NO;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (rs->total_in.currency,
                                          &rs->a_balance));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (rs->total_in.currency,
                                          &rs->a_withdraw_fee_balance));
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Creating fresh reserve `%s' with starting balance %s\n",
                TALER_B2S (&rs->reserve_pub),
                TALER_amount2s (&rs->a_balance));
    return GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
  }
  rs->had_ri = GNUNET_YES;
  if ( (GNUNET_YES !=
        TALER_amount_cmp_currency (&rs->a_balance,
                                   &rs->a_withdraw_fee_balance)) ||
       (GNUNET_YES !=
        TALER_amount_cmp_currency (&rs->total_in,
                                   &rs->a_balance)) )
  {
    GNUNET_break (0);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Auditor remembers reserve `%s' has balance %s\n",
              TALER_B2S (&rs->reserve_pub),
              TALER_amount2s (&rs->a_balance));
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Closure to the various callbacks we make while checking a reserve.
 */
struct ReserveContext
{
  /**
   * Map from hash of reserve's public key to a `struct ReserveSummary`.
   */
  struct GNUNET_CONTAINER_MultiHashMap *reserves;

  /**
   * Map from hash of denomination's public key to a
   * static string "revoked" for keys that have been revoked,
   * or "master signature invalid" in case the revocation is
   * there but bogus.
   */
  struct GNUNET_CONTAINER_MultiHashMap *revoked;

  /**
   * Transaction status code, set to error codes if applicable.
   */
  enum GNUNET_DB_QueryStatus qs;

};


/**
 * Function called with details about incoming wire transfers.
 *
 * @param cls our `struct ReserveContext`
 * @param rowid unique serial ID for the refresh session in our DB
 * @param reserve_pub public key of the reserve (also the WTID)
 * @param credit amount that was received
 * @param sender_account_details information about the sender's bank account
 * @param wire_reference unique reference identifying the wire transfer (binary blob)
 * @param wire_reference_size number of bytes in @a wire_reference
 * @param execution_date when did we receive the funds
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
handle_reserve_in (void *cls,
                   uint64_t rowid,
                   const struct TALER_ReservePublicKeyP *reserve_pub,
                   const struct TALER_Amount *credit,
                   const char *sender_account_details,
                   const void *wire_reference,
                   size_t wire_reference_size,
                   struct GNUNET_TIME_Absolute execution_date)
{
  struct ReserveContext *rc = cls;
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;
  struct GNUNET_TIME_Absolute expiry;
  enum GNUNET_DB_QueryStatus qs;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppr.last_reserve_in_serial_id);
  ppr.last_reserve_in_serial_id = rowid + 1;

  GNUNET_CRYPTO_hash (reserve_pub,
                      sizeof (*reserve_pub),
                      &key);
  rs = GNUNET_CONTAINER_multihashmap_get (rc->reserves,
                                          &key);
  if (NULL == rs)
  {
    rs = GNUNET_new (struct ReserveSummary);
    rs->reserve_pub = *reserve_pub;
    rs->total_in = *credit;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (credit->currency,
                                          &rs->total_out));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (credit->currency,
                                          &rs->total_fee));
    if (0 > (qs = load_auditor_reserve_summary (rs)))
    {
      GNUNET_break (0);
      GNUNET_free (rs);
      rc->qs = qs;
      return GNUNET_SYSERR;
    }
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_put (rc->reserves,
                                                      &key,
                                                      rs,
                                                      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  }
  else
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&rs->total_in,
                                     &rs->total_in,
                                     credit));
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Additional incoming wire transfer for reserve `%s' of %s\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (credit));
  expiry = GNUNET_TIME_absolute_add (execution_date,
                                     idle_reserve_expiration_time);
  rs->a_expiration_date = GNUNET_TIME_absolute_max (rs->a_expiration_date,
                                                    expiry);
  return GNUNET_OK;
}


/**
 * Function called with details about withdraw operations.  Verifies
 * the signature and updates the reserve's balance.
 *
 * @param cls our `struct ReserveContext`
 * @param rowid unique serial ID for the refresh session in our DB
 * @param h_blind_ev blinded hash of the coin's public key
 * @param denom_pub public denomination key of the deposited coin
 * @param denom_sig signature over the deposited coin
 * @param reserve_pub public key of the reserve
 * @param reserve_sig signature over the withdraw operation
 * @param execution_date when did the wallet withdraw the coin
 * @param amount_with_fee amount that was withdrawn
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
handle_reserve_out (void *cls,
                    uint64_t rowid,
                    const struct GNUNET_HashCode *h_blind_ev,
                    const struct TALER_DenominationPublicKey *denom_pub,
                    const struct TALER_DenominationSignature *denom_sig,
                    const struct TALER_ReservePublicKeyP *reserve_pub,
                    const struct TALER_ReserveSignatureP *reserve_sig,
                    struct GNUNET_TIME_Absolute execution_date,
                    const struct TALER_Amount *amount_with_fee)
{
  struct ReserveContext *rc = cls;
  struct TALER_WithdrawRequestPS wsrd;
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct TALER_Amount withdraw_fee;
  struct GNUNET_TIME_Absolute valid_start;
  struct GNUNET_TIME_Absolute expire_withdraw;
  enum GNUNET_DB_QueryStatus qs;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppr.last_reserve_out_serial_id);
  ppr.last_reserve_out_serial_id = rowid + 1;

  /* lookup denomination pub data (make sure denom_pub is valid, establish fees) */
  qs = get_denomination_info (denom_pub,
                              &dki,
                              &wsrd.h_denomination_pub);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    rc->qs = qs;
    return GNUNET_SYSERR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    report_row_inconsistency ("withdraw",
                              rowid,
                              "denomination key not found (foreign key constraint violated)");
    rc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_OK;
  }

  /* check that execution date is within withdraw range for denom_pub  */
  valid_start = GNUNET_TIME_absolute_ntoh (dki->properties.start);
  expire_withdraw = GNUNET_TIME_absolute_ntoh (dki->properties.expire_withdraw);
  if ( (valid_start.abs_value_us > execution_date.abs_value_us) ||
       (expire_withdraw.abs_value_us < execution_date.abs_value_us) )
  {
    report (denomination_key_validity_withdraw_inconsistencies,
            json_pack ("{s:I, s:o, s:o, s:o}",
                       "row", (json_int_t) rowid,
                       "execution_date",
                       json_from_time_abs (execution_date),
                       "reserve_pub", GNUNET_JSON_from_data_auto (reserve_pub),
                       "denompub_h", GNUNET_JSON_from_data_auto (
                         &wsrd.h_denomination_pub)));
  }

  /* check reserve_sig */
  wsrd.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW);
  wsrd.purpose.size = htonl (sizeof (wsrd));
  wsrd.reserve_pub = *reserve_pub;
  TALER_amount_hton (&wsrd.amount_with_fee,
                     amount_with_fee);
  wsrd.withdraw_fee = dki->properties.fee_withdraw;
  wsrd.h_coin_envelope = *h_blind_ev;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_RESERVE_WITHDRAW,
                                  &wsrd.purpose,
                                  &reserve_sig->eddsa_signature,
                                  &reserve_pub->eddsa_pub))
  {
    report (report_bad_sig_losses,
            json_pack ("{s:s, s:I, s:o, s:o}",
                       "operation", "withdraw",
                       "row", (json_int_t) rowid,
                       "loss", TALER_JSON_from_amount (amount_with_fee),
                       "key_pub", GNUNET_JSON_from_data_auto (reserve_pub)));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_sig_loss,
                                    &total_bad_sig_loss,
                                    amount_with_fee));
    return GNUNET_OK;
  }

  GNUNET_CRYPTO_hash (reserve_pub,
                      sizeof (*reserve_pub),
                      &key);
  rs = GNUNET_CONTAINER_multihashmap_get (rc->reserves,
                                          &key);
  if (NULL == rs)
  {
    rs = GNUNET_new (struct ReserveSummary);
    rs->reserve_pub = *reserve_pub;
    rs->total_out = *amount_with_fee;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount_with_fee->currency,
                                          &rs->total_in));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount_with_fee->currency,
                                          &rs->total_fee));
    qs = load_auditor_reserve_summary (rs);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_free (rs);
      rc->qs = qs;
      return GNUNET_SYSERR;
    }
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_put (rc->reserves,
                                                      &key,
                                                      rs,
                                                      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  }
  else
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&rs->total_out,
                                     &rs->total_out,
                                     amount_with_fee));
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Reserve `%s' reduced by %s from withdraw\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (amount_with_fee));
  TALER_amount_ntoh (&withdraw_fee,
                     &dki->properties.fee_withdraw);
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Increasing withdraw profits by fee %s\n",
              TALER_amount2s (&withdraw_fee));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_add (&rs->total_fee,
                                   &rs->total_fee,
                                   &withdraw_fee));

  return GNUNET_OK;
}


/**
 * Function called with details about withdraw operations.  Verifies
 * the signature and updates the reserve's balance.
 *
 * @param cls our `struct ReserveContext`
 * @param rowid unique serial ID for the refresh session in our DB
 * @param timestamp when did we receive the payback request
 * @param amount how much should be added back to the reserve
 * @param reserve_pub public key of the reserve
 * @param coin public information about the coin, denomination signature is
 *        already verified in #check_payback()
 * @param denom_pub public key of the denomionation of @a coin
 * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_COIN_PAYBACK
 * @param coin_blind blinding factor used to blind the coin
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
handle_payback_by_reserve (void *cls,
                           uint64_t rowid,
                           struct GNUNET_TIME_Absolute timestamp,
                           const struct TALER_Amount *amount,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           const struct TALER_CoinPublicInfo *coin,
                           const struct TALER_DenominationPublicKey *denom_pub,
                           const struct TALER_CoinSpendSignatureP *coin_sig,
                           const struct
                           TALER_DenominationBlindingKeyP *coin_blind)
{
  struct ReserveContext *rc = cls;
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;
  struct GNUNET_TIME_Absolute expiry;
  struct TALER_PaybackRequestPS pr;
  struct TALER_MasterSignatureP msig;
  uint64_t rev_rowid;
  enum GNUNET_DB_QueryStatus qs;
  const char *rev;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppr.last_reserve_payback_serial_id);
  ppr.last_reserve_payback_serial_id = rowid + 1;
  // FIXME: should probably check that denom_pub hashes to this hash code!
  pr.h_denom_pub = coin->denom_pub_hash;
  pr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_PAYBACK);
  pr.purpose.size = htonl (sizeof (pr));
  pr.coin_pub = coin->coin_pub;
  pr.coin_blind = *coin_blind;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_PAYBACK,
                                  &pr.purpose,
                                  &coin_sig->eddsa_signature,
                                  &coin->coin_pub.eddsa_pub))
  {
    report (report_bad_sig_losses,
            json_pack ("{s:s, s:I, s:o, s:o}",
                       "operation", "payback",
                       "row", (json_int_t) rowid,
                       "loss", TALER_JSON_from_amount (amount),
                       "key_pub", GNUNET_JSON_from_data_auto (
                         &coin->coin_pub)));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_sig_loss,
                                    &total_bad_sig_loss,
                                    amount));
  }

  /* check that the coin was eligible for payback!*/
  rev = GNUNET_CONTAINER_multihashmap_get (rc->revoked,
                                           &pr.h_denom_pub);
  if (NULL == rev)
  {
    qs = edb->get_denomination_revocation (edb->cls,
                                           esession,
                                           &pr.h_denom_pub,
                                           &msig,
                                           &rev_rowid);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      rc->qs = qs;
      return GNUNET_SYSERR;
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      report_row_inconsistency ("payback",
                                rowid,
                                "denomination key not in revocation set");
      /* FIXME: add amount involved to some loss statistic!?
         It's kind-of not a loss (we just paid back), OTOH, it is
         certainly irregular and involves some amount.  */
    }
    else
    {
      /* verify msig */
      struct TALER_MasterDenominationKeyRevocationPS kr;

      kr.purpose.purpose = htonl (
        TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED);
      kr.purpose.size = htonl (sizeof (kr));
      kr.h_denom_pub = pr.h_denom_pub;
      if (GNUNET_OK !=
          GNUNET_CRYPTO_eddsa_verify (
            TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED,
            &kr.purpose,
            &msig.eddsa_signature,
            &master_pub.eddsa_pub))
      {
        rev = "master signature invalid";
      }
      else
      {
        rev = "revoked";
      }
      GNUNET_assert (GNUNET_OK ==
                     GNUNET_CONTAINER_multihashmap_put (rc->revoked,
                                                        &pr.h_denom_pub,
                                                        (void *) rev,
                                                        GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
    }
  }
  else
  {
    rev_rowid = 0; /* reported elsewhere */
  }
  if ( (NULL != rev) &&
       (0 == strcmp (rev, "master signature invalid")) )
  {
    report (report_bad_sig_losses,
            json_pack ("{s:s, s:I, s:o, s:o}",
                       "operation", "payback-master",
                       "row", (json_int_t) rev_rowid,
                       "loss", TALER_JSON_from_amount (amount),
                       "key_pub", GNUNET_JSON_from_data_auto (&master_pub)));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_sig_loss,
                                    &total_bad_sig_loss,
                                    amount));
  }

  GNUNET_CRYPTO_hash (reserve_pub,
                      sizeof (*reserve_pub),
                      &key);
  rs = GNUNET_CONTAINER_multihashmap_get (rc->reserves,
                                          &key);
  if (NULL == rs)
  {
    rs = GNUNET_new (struct ReserveSummary);
    rs->reserve_pub = *reserve_pub;
    rs->total_in = *amount;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount->currency,
                                          &rs->total_out));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount->currency,
                                          &rs->total_fee));
    qs = load_auditor_reserve_summary (rs);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_free (rs);
      rc->qs = qs;
      return GNUNET_SYSERR;
    }
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_put (rc->reserves,
                                                      &key,
                                                      rs,
                                                      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  }
  else
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&rs->total_in,
                                     &rs->total_in,
                                     amount));
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Additional /payback value to for reserve `%s' of %s\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (amount));
  expiry = GNUNET_TIME_absolute_add (timestamp,
                                     idle_reserve_expiration_time);
  rs->a_expiration_date = GNUNET_TIME_absolute_max (rs->a_expiration_date,
                                                    expiry);
  return GNUNET_OK;
}


/**
 * Function called about reserve closing operations
 * the aggregator triggered.
 *
 * @param cls closure
 * @param rowid row identifier used to uniquely identify the reserve closing operation
 * @param execution_date when did we execute the close operation
 * @param amount_with_fee how much did we debit the reserve
 * @param closing_fee how much did we charge for closing the reserve
 * @param reserve_pub public key of the reserve
 * @param receiver_account where did we send the funds
 * @param transfer_details details about the wire transfer
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
handle_reserve_closed (void *cls,
                       uint64_t rowid,
                       struct GNUNET_TIME_Absolute execution_date,
                       const struct TALER_Amount *amount_with_fee,
                       const struct TALER_Amount *closing_fee,
                       const struct TALER_ReservePublicKeyP *reserve_pub,
                       const char *receiver_account,
                       const struct
                       TALER_WireTransferIdentifierRawP *transfer_details)
{
  struct ReserveContext *rc = cls;
  struct GNUNET_HashCode key;
  struct ReserveSummary *rs;
  enum GNUNET_DB_QueryStatus qs;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppr.last_reserve_close_serial_id);
  ppr.last_reserve_close_serial_id = rowid + 1;

  GNUNET_CRYPTO_hash (reserve_pub,
                      sizeof (*reserve_pub),
                      &key);
  rs = GNUNET_CONTAINER_multihashmap_get (rc->reserves,
                                          &key);
  if (NULL == rs)
  {
    rs = GNUNET_new (struct ReserveSummary);
    rs->reserve_pub = *reserve_pub;
    rs->total_out = *amount_with_fee;
    rs->total_fee = *closing_fee;
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount_with_fee->currency,
                                          &rs->total_in));
    qs = load_auditor_reserve_summary (rs);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_free (rs);
      rc->qs = qs;
      return GNUNET_SYSERR;
    }
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CONTAINER_multihashmap_put (rc->reserves,
                                                      &key,
                                                      rs,
                                                      GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  }
  else
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&rs->total_out,
                                     &rs->total_out,
                                     amount_with_fee));
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&rs->total_fee,
                                     &rs->total_fee,
                                     closing_fee));
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Additional closing operation for reserve `%s' of %s\n",
              TALER_B2S (reserve_pub),
              TALER_amount2s (amount_with_fee));
  return GNUNET_OK;
}


/**
 * Check that the reserve summary matches what the exchange database
 * thinks about the reserve, and update our own state of the reserve.
 *
 * Remove all reserves that we are happy with from the DB.
 *
 * @param cls our `struct ReserveContext`
 * @param key hash of the reserve public key
 * @param value a `struct ReserveSummary`
 * @return #GNUNET_OK to process more entries
 */
static int
verify_reserve_balance (void *cls,
                        const struct GNUNET_HashCode *key,
                        void *value)
{
  struct ReserveContext *rc = cls;
  struct ReserveSummary *rs = value;
  struct TALER_EXCHANGEDB_Reserve reserve;
  struct TALER_Amount balance;
  struct TALER_Amount nbalance;
  enum GNUNET_DB_QueryStatus qs;
  int ret;

  ret = GNUNET_OK;
  reserve.pub = rs->reserve_pub;
  qs = edb->reserve_get (edb->cls,
                         esession,
                         &reserve);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    char *diag;

    GNUNET_asprintf (&diag,
                     "Failed to find summary for reserve `%s'\n",
                     TALER_B2S (&rs->reserve_pub));
    report_row_inconsistency ("reserve-summary",
                              UINT64_MAX,
                              diag);
    GNUNET_free (diag);
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      GNUNET_break (0);
      qs = GNUNET_DB_STATUS_HARD_ERROR;
    }
    rc->qs = qs;
    return GNUNET_OK;
  }

  if (GNUNET_OK !=
      TALER_amount_add (&balance,
                        &rs->total_in,
                        &rs->a_balance))
  {
    GNUNET_break (0);
    goto cleanup;
  }

  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&nbalance,
                             &balance,
                             &rs->total_out))
  {
    struct TALER_Amount loss;

    GNUNET_break (GNUNET_SYSERR !=
                  TALER_amount_subtract (&loss,
                                         &rs->total_out,
                                         &balance));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_balance_insufficient_loss,
                                    &total_balance_insufficient_loss,
                                    &loss));
    report (report_reserve_balance_insufficient_inconsistencies,
            json_pack ("{s:o, s:o}",
                       "reserve_pub",
                       GNUNET_JSON_from_data_auto (&rs->reserve_pub),
                       "loss",
                       TALER_JSON_from_amount (&loss)));
    goto cleanup;
  }
  if (0 != TALER_amount_cmp (&nbalance,
                             &reserve.balance))
  {
    struct TALER_Amount delta;

    if (0 < TALER_amount_cmp (&nbalance,
                              &reserve.balance))
    {
      /* balance > reserve.balance */
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_subtract (&delta,
                                            &nbalance,
                                            &reserve.balance));
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_add (&total_balance_summary_delta_plus,
                                       &total_balance_summary_delta_plus,
                                       &delta));
    }
    else
    {
      /* balance < reserve.balance */
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_subtract (&delta,
                                            &reserve.balance,
                                            &nbalance));
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_add (&total_balance_summary_delta_minus,
                                       &total_balance_summary_delta_minus,
                                       &delta));
    }
    report (report_reserve_balance_summary_wrong_inconsistencies,
            json_pack ("{s:o, s:o, s:o}",
                       "reserve_pub",
                       GNUNET_JSON_from_data_auto (&rs->reserve_pub),
                       "exchange",
                       TALER_JSON_from_amount (&reserve.balance),
                       "auditor",
                       TALER_JSON_from_amount (&nbalance)));
    goto cleanup;
  }

  /* Check that reserve is being closed if it is past its expiration date */
  if ( (CLOSING_GRACE_PERIOD.rel_value_us >
        GNUNET_TIME_absolute_get_duration (
          rs->a_expiration_date).rel_value_us) &&
       ( (0 != nbalance.value) ||
         (0 != nbalance.fraction) ) )
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&total_balance_reserve_not_closed,
                                     &total_balance_reserve_not_closed,
                                     &nbalance));
    report (report_reserve_not_closed_inconsistencies,
            json_pack ("{s:o, s:o, s:o}",
                       "reserve_pub",
                       GNUNET_JSON_from_data_auto (&rs->reserve_pub),
                       "balance",
                       TALER_JSON_from_amount (&nbalance),
                       "expiration_time",
                       json_from_time_abs (rs->a_expiration_date)));
  }

  /* Add withdraw fees we encountered to totals */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Reserve reserve `%s' made %s in withdraw fees\n",
              TALER_B2S (&rs->reserve_pub),
              TALER_amount2s (&rs->total_fee));
  if (GNUNET_YES !=
      TALER_amount_add (&rs->a_withdraw_fee_balance,
                        &rs->a_withdraw_fee_balance,
                        &rs->total_fee))
  {
    GNUNET_break (0);
    ret = GNUNET_SYSERR;
    goto cleanup;
  }
  if ( (GNUNET_YES !=
        TALER_amount_add (&total_escrow_balance,
                          &total_escrow_balance,
                          &rs->total_in)) ||
       (GNUNET_SYSERR ==
        TALER_amount_subtract (&total_escrow_balance,
                               &total_escrow_balance,
                               &rs->total_out)) ||
       (GNUNET_YES !=
        TALER_amount_add (&total_withdraw_fee_income,
                          &total_withdraw_fee_income,
                          &rs->total_fee)) )
  {
    GNUNET_break (0);
    ret = GNUNET_SYSERR;
    goto cleanup;
  }

  if ( (0ULL == balance.value) &&
       (0U == balance.fraction) )
  {
    /* TODO: balance is zero, drop reserve details (and then do not update/insert) */
    if (rs->had_ri)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Final balance of reserve `%s' is %s, dropping it\n",
                  TALER_B2S (&rs->reserve_pub),
                  TALER_amount2s (&nbalance));
      qs = adb->del_reserve_info (adb->cls,
                                  asession,
                                  &rs->reserve_pub,
                                  &master_pub);
      if (0 >= qs)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        ret = GNUNET_SYSERR;
        rc->qs = qs;
        goto cleanup;
      }
    }
    else
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Final balance of reserve `%s' is %s, no need to remember it\n",
                  TALER_B2S (&rs->reserve_pub),
                  TALER_amount2s (&nbalance));
    }
    ret = GNUNET_OK;
    goto cleanup;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Remembering final balance of reserve `%s' as %s\n",
              TALER_B2S (&rs->reserve_pub),
              TALER_amount2s (&nbalance));

  if (rs->had_ri)
    qs = adb->update_reserve_info (adb->cls,
                                   asession,
                                   &rs->reserve_pub,
                                   &master_pub,
                                   &nbalance,
                                   &rs->a_withdraw_fee_balance,
                                   rs->a_expiration_date);
  else
    qs = adb->insert_reserve_info (adb->cls,
                                   asession,
                                   &rs->reserve_pub,
                                   &master_pub,
                                   &nbalance,
                                   &rs->a_withdraw_fee_balance,
                                   rs->a_expiration_date);
  if (0 >= qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    ret = GNUNET_SYSERR;
    rc->qs = qs;
  }
  cleanup:
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (rc->reserves,
                                                       key,
                                                       rs));
  GNUNET_free (rs);
  return ret;
}


/**
 * Analyze reserves for being well-formed.
 *
 * @param cls NULL
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
analyze_reserves (void *cls)
{
  struct ReserveContext rc;
  enum GNUNET_DB_QueryStatus qsx;
  enum GNUNET_DB_QueryStatus qs;
  enum GNUNET_DB_QueryStatus qsp;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing reserves\n");
  qsp = adb->get_auditor_progress_reserve (adb->cls,
                                           asession,
                                           &master_pub,
                                           &ppr);
  if (0 > qsp)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsp);
    return qsp;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsp)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                _ (
                  "First analysis using this auditor, starting audit from scratch\n"));
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                _ ("Resuming reserve audit at %llu/%llu/%llu/%llu\n"),
                (unsigned long long) ppr.last_reserve_in_serial_id,
                (unsigned long long) ppr.last_reserve_out_serial_id,
                (unsigned long long) ppr.last_reserve_payback_serial_id,
                (unsigned long long) ppr.last_reserve_close_serial_id);
  }
  rc.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  qsx = adb->get_reserve_summary (adb->cls,
                                  asession,
                                  &master_pub,
                                  &total_escrow_balance,
                                  &total_withdraw_fee_income);
  if (qsx < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx);
    return qsx;
  }
  rc.reserves = GNUNET_CONTAINER_multihashmap_create (512,
                                                      GNUNET_NO);
  rc.revoked = GNUNET_CONTAINER_multihashmap_create (4,
                                                     GNUNET_NO);

  qs = edb->select_reserves_in_above_serial_id (edb->cls,
                                                esession,
                                                ppr.last_reserve_in_serial_id,
                                                &handle_reserve_in,
                                                &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = edb->select_reserves_out_above_serial_id (edb->cls,
                                                 esession,
                                                 ppr.last_reserve_out_serial_id,
                                                 &handle_reserve_out,
                                                 &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = edb->select_payback_above_serial_id (edb->cls,
                                            esession,
                                            ppr.last_reserve_payback_serial_id,
                                            &handle_payback_by_reserve,
                                            &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  qs = edb->select_reserve_closed_above_serial_id (edb->cls,
                                                   esession,
                                                   ppr.
                                                   last_reserve_close_serial_id,
                                                   &handle_reserve_closed,
                                                   &rc);
  if (qs < 0)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  GNUNET_CONTAINER_multihashmap_iterate (rc.reserves,
                                         &verify_reserve_balance,
                                         &rc);
  GNUNET_break (0 ==
                GNUNET_CONTAINER_multihashmap_size (rc.reserves));
  GNUNET_CONTAINER_multihashmap_destroy (rc.reserves);
  GNUNET_CONTAINER_multihashmap_destroy (rc.revoked);

  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != rc.qs)
    return qs;

  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsx)
  {
    qs = adb->insert_reserve_summary (adb->cls,
                                      asession,
                                      &master_pub,
                                      &total_escrow_balance,
                                      &total_withdraw_fee_income);
  }
  else
  {
    qs = adb->update_reserve_summary (adb->cls,
                                      asession,
                                      &master_pub,
                                      &total_escrow_balance,
                                      &total_withdraw_fee_income);
  }
  if (0 >= qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsp)
    qs = adb->update_auditor_progress_reserve (adb->cls,
                                               asession,
                                               &master_pub,
                                               &ppr);
  else
    qs = adb->insert_auditor_progress_reserve (adb->cls,
                                               asession,
                                               &master_pub,
                                               &ppr);
  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              _ ("Concluded reserve audit step at %llu/%llu/%llu/%llu\n"),
              (unsigned long long) ppr.last_reserve_in_serial_id,
              (unsigned long long) ppr.last_reserve_out_serial_id,
              (unsigned long long) ppr.last_reserve_payback_serial_id,
              (unsigned long long) ppr.last_reserve_close_serial_id);
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/* *********************** Analyze aggregations ******************** */
/* This logic checks that the aggregator did the right thing
   paying each merchant what they were due (and on time). */


/**
 * Information we keep per loaded wire plugin.
 */
struct WirePlugin
{

  /**
   * Kept in a DLL.
   */
  struct WirePlugin *next;

  /**
   * Kept in a DLL.
   */
  struct WirePlugin *prev;

  /**
   * Name of the wire method.
   */
  char *type;

  /**
   * Handle to the wire plugin.
   */
  struct TALER_WIRE_Plugin *plugin;

};


/**
 * Information about wire fees charged by the exchange.
 */
struct WireFeeInfo
{

  /**
   * Kept in a DLL.
   */
  struct WireFeeInfo *next;

  /**
   * Kept in a DLL.
   */
  struct WireFeeInfo *prev;

  /**
   * When does the fee go into effect (inclusive).
   */
  struct GNUNET_TIME_Absolute start_date;

  /**
   * When does the fee stop being in effect (exclusive).
   */
  struct GNUNET_TIME_Absolute end_date;

  /**
   * How high is the wire fee.
   */
  struct TALER_Amount wire_fee;

  /**
   * How high is the closing fee.
   */
  struct TALER_Amount closing_fee;

};


/**
 * Closure for callbacks during #analyze_merchants().
 */
struct AggregationContext
{

  /**
   * DLL of wire plugins encountered.
   */
  struct WirePlugin *wire_head;

  /**
   * DLL of wire plugins encountered.
   */
  struct WirePlugin *wire_tail;

  /**
   * DLL of wire fees charged by the exchange.
   */
  struct WireFeeInfo *fee_head;

  /**
   * DLL of wire fees charged by the exchange.
   */
  struct WireFeeInfo *fee_tail;

  /**
   * Final result status.
   */
  enum GNUNET_DB_QueryStatus qs;
};


/**
 * Find the relevant wire plugin.
 *
 * @param ac context to search
 * @param type type of the wire plugin to load; it
 *  will be used _as is_ from the dynamic loader.
 * @return NULL on error
 */
static struct TALER_WIRE_Plugin *
get_wire_plugin (struct AggregationContext *ac,
                 const char *type)
{
  struct WirePlugin *wp;
  struct TALER_WIRE_Plugin *plugin;

  for (wp = ac->wire_head; NULL != wp; wp = wp->next)
    if (0 == strcmp (type,
                     wp->type))
      return wp->plugin;

  /* Wants the exact *plugin name* (!= method)  */
  plugin = TALER_WIRE_plugin_load (cfg,
                                   type);
  if (NULL == plugin)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to locate wire plugin for `%s'\n",
                type);
    return NULL;
  }
  wp = GNUNET_new (struct WirePlugin);
  wp->type = GNUNET_strdup (type);
  wp->plugin = plugin;
  GNUNET_CONTAINER_DLL_insert (ac->wire_head,
                               ac->wire_tail,
                               wp);
  return plugin;
}


/**
 * Closure for #wire_transfer_information_cb.
 */
struct WireCheckContext
{

  /**
   * Corresponding merchant context.
   */
  struct AggregationContext *ac;

  /**
   * Total deposits claimed by all transactions that were aggregated
   * under the given @e wtid.
   */
  struct TALER_Amount total_deposits;

  /**
   * Hash of the wire transfer details of the receiver.
   */
  struct GNUNET_HashCode h_wire;

  /**
   * Execution time of the wire transfer.
   */
  struct GNUNET_TIME_Absolute date;

  /**
   * Database transaction status.
   */
  enum GNUNET_DB_QueryStatus qs;

};


/**
 * Check coin's transaction history for plausibility.  Does NOT check
 * the signatures (those are checked independently), but does calculate
 * the amounts for the aggregation table and checks that the total
 * claimed coin value is within the value of the coin's denomination.
 *
 * @param coin_pub public key of the coin (for reporting)
 * @param h_contract_terms hash of the proposal for which we calculate the amount
 * @param merchant_pub public key of the merchant (who is allowed to issue refunds)
 * @param dki denomination information about the coin
 * @param tl_head head of transaction history to verify
 * @param[out] merchant_gain amount the coin contributes to the wire transfer to the merchant
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on error
 */
static int
check_transaction_history_for_deposit (const struct
                                       TALER_CoinSpendPublicKeyP *coin_pub,
                                       const struct
                                       GNUNET_HashCode *h_contract_terms,
                                       const struct
                                       TALER_MerchantPublicKeyP *merchant_pub,
                                       const struct
                                       TALER_EXCHANGEDB_DenominationKeyInformationP
                                       *dki,
                                       const struct
                                       TALER_EXCHANGEDB_TransactionList *tl_head,
                                       struct TALER_Amount *merchant_gain)
{
  struct TALER_Amount expenditures;
  struct TALER_Amount refunds;
  struct TALER_Amount spent;
  struct TALER_Amount value;
  struct TALER_Amount merchant_loss;
  struct TALER_Amount merchant_delta;
  const struct TALER_Amount *deposit_fee;
  int refund_deposit_fee;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Checking transaction history of coin %s\n",
              TALER_B2S (coin_pub));

  GNUNET_assert (NULL != tl_head);
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &expenditures));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &refunds));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        merchant_gain));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &merchant_loss));
  /* Go over transaction history to compute totals; note that we do not
     know the order, so instead of subtracting we compute positive
     (deposit, melt) and negative (refund) values separately here,
     and then subtract the negative from the positive after the loop. */
  refund_deposit_fee = GNUNET_NO;
  deposit_fee = NULL;
  for (const struct TALER_EXCHANGEDB_TransactionList *tl = tl_head;
       NULL != tl;
       tl = tl->next)
  {
    const struct TALER_Amount *amount_with_fee;
    const struct TALER_Amount *fee;
    const struct TALER_AmountNBO *fee_dki;
    struct TALER_Amount tmp;

    switch (tl->type)
    {
    case TALER_EXCHANGEDB_TT_DEPOSIT:
      /* check wire and h_wire are consistent */
      {
        struct GNUNET_HashCode hw;

        if (GNUNET_OK !=
            TALER_JSON_merchant_wire_signature_hash (
              tl->details.deposit->receiver_wire_account,
              &hw))
        {
          report_row_inconsistency ("deposits",
                                    tl->serial_id,
                                    "wire value malformed");
        }
        else if (0 !=
                 GNUNET_memcmp (&hw,
                                &tl->details.deposit->h_wire))
        {
          report_row_inconsistency ("deposits",
                                    tl->serial_id,
                                    "h_wire does not match wire");
        }
      }
      amount_with_fee = &tl->details.deposit->amount_with_fee;
      fee = &tl->details.deposit->deposit_fee;
      fee_dki = &dki->properties.fee_deposit;
      if (GNUNET_OK !=
          TALER_amount_add (&expenditures,
                            &expenditures,
                            amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      /* Check if this deposit is within the remit of the aggregation
         we are investigating, if so, include it in the totals. */
      if ( (0 == GNUNET_memcmp (merchant_pub,
                                &tl->details.deposit->merchant_pub)) &&
           (0 == GNUNET_memcmp (h_contract_terms,
                                &tl->details.deposit->h_contract_terms)) )
      {
        struct TALER_Amount amount_without_fee;

        if (GNUNET_OK !=
            TALER_amount_subtract (&amount_without_fee,
                                   amount_with_fee,
                                   fee))
        {
          GNUNET_break (0);
          return GNUNET_SYSERR;
        }
        if (GNUNET_OK !=
            TALER_amount_add (merchant_gain,
                              merchant_gain,
                              &amount_without_fee))
        {
          GNUNET_break (0);
          return GNUNET_SYSERR;
        }
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Detected applicable deposit of %s\n",
                    TALER_amount2s (&amount_without_fee));
        deposit_fee = fee;
      }
      /* Check that the fees given in the transaction list and in dki match */
      TALER_amount_ntoh (&tmp,
                         fee_dki);
      if (0 !=
          TALER_amount_cmp (&tmp,
                            fee))
      {
        /* Disagreement in fee structure within DB, should be impossible! */
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    case TALER_EXCHANGEDB_TT_REFRESH_MELT:
      amount_with_fee = &tl->details.melt->session.amount_with_fee;
      fee = &tl->details.melt->melt_fee;
      fee_dki = &dki->properties.fee_refresh;
      if (GNUNET_OK !=
          TALER_amount_add (&expenditures,
                            &expenditures,
                            amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      /* Check that the fees given in the transaction list and in dki match */
      TALER_amount_ntoh (&tmp,
                         fee_dki);
      if (0 !=
          TALER_amount_cmp (&tmp,
                            fee))
      {
        /* Disagreement in fee structure within DB, should be impossible! */
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    case TALER_EXCHANGEDB_TT_REFUND:
      amount_with_fee = &tl->details.refund->refund_amount;
      fee = &tl->details.refund->refund_fee;
      fee_dki = &dki->properties.fee_refund;
      if (GNUNET_OK !=
          TALER_amount_add (&refunds,
                            &refunds,
                            amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      if (GNUNET_OK !=
          TALER_amount_add (&expenditures,
                            &expenditures,
                            fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      /* Check if this refund is within the remit of the aggregation
         we are investigating, if so, include it in the totals. */
      if ( (0 == GNUNET_memcmp (merchant_pub,
                                &tl->details.refund->merchant_pub)) &&
           (0 == GNUNET_memcmp (h_contract_terms,
                                &tl->details.refund->h_contract_terms)) )
      {
        if (GNUNET_OK !=
            TALER_amount_add (&merchant_loss,
                              &merchant_loss,
                              amount_with_fee))
        {
          GNUNET_break (0);
          return GNUNET_SYSERR;
        }
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Detected applicable refund of %s\n",
                    TALER_amount2s (amount_with_fee));
        refund_deposit_fee = GNUNET_YES;
      }
      /* Check that the fees given in the transaction list and in dki match */
      TALER_amount_ntoh (&tmp,
                         fee_dki);
      if (0 !=
          TALER_amount_cmp (&tmp,
                            fee))
      {
        /* Disagreement in fee structure within DB, should be impossible! */
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    case TALER_EXCHANGEDB_TT_OLD_COIN_PAYBACK:
      amount_with_fee = &tl->details.old_coin_payback->value;
      if (GNUNET_OK !=
          TALER_amount_add (&refunds,
                            &refunds,
                            amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    case TALER_EXCHANGEDB_TT_PAYBACK:
      amount_with_fee = &tl->details.payback->value;
      if (GNUNET_OK !=
          TALER_amount_add (&expenditures,
                            &expenditures,
                            amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    case TALER_EXCHANGEDB_TT_PAYBACK_REFRESH:
      amount_with_fee = &tl->details.payback_refresh->value;
      if (GNUNET_OK !=
          TALER_amount_add (&expenditures,
                            &expenditures,
                            amount_with_fee))
      {
        GNUNET_break (0);
        return GNUNET_SYSERR;
      }
      break;
    }
  } /* for 'tl' */

  if ( (GNUNET_YES == refund_deposit_fee) &&
       (NULL != deposit_fee) )
  {
    /* We had a /deposit operation AND a /refund operation,
       and should thus not charge the merchant the /deposit fee */
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (merchant_gain,
                                     merchant_gain,
                                     deposit_fee));
  }

  /* Calculate total balance change, i.e. expenditures (payback, deposit, refresh)
     minus refunds (refunds, payback-to-old) */
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&spent,
                             &expenditures,
                             &refunds))
  {
    /* refunds above expenditures? Bad! */
    report_coin_arithmetic_inconsistency ("refund (balance)",
                                          coin_pub,
                                          &expenditures,
                                          &refunds,
                                          1);
    return GNUNET_SYSERR;
  }

  /* Now check that 'spent' is less or equal than total coin value */
  TALER_amount_ntoh (&value,
                     &dki->properties.value);
  if (1 == TALER_amount_cmp (&spent,
                             &value))
  {
    /* spent > value */
    report_coin_arithmetic_inconsistency ("spend",
                                          coin_pub,
                                          &spent,
                                          &value,
                                          -1);
    return GNUNET_SYSERR;
  }

  /* Finally, update @a merchant_gain by subtracting what he "lost"
     from refunds */
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&merchant_delta,
                             merchant_gain,
                             &merchant_loss))
  {
    /* refunds above deposits? Bad! */
    report_coin_arithmetic_inconsistency ("refund (merchant)",
                                          coin_pub,
                                          merchant_gain,
                                          &merchant_loss,
                                          1);
    return GNUNET_SYSERR;
  }
  *merchant_gain = merchant_delta;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Coin %s contributes %s to contract %s\n",
              TALER_B2S (coin_pub),
              TALER_amount2s (merchant_gain),
              GNUNET_h2s (h_contract_terms));
  return GNUNET_OK;
}


/**
 * Function called with the results of the lookup of the
 * transaction data associated with a wire transfer identifier.
 *
 * @param cls a `struct WireCheckContext`
 * @param rowid which row in the table is the information from (for diagnostics)
 * @param merchant_pub public key of the merchant (should be same for all callbacks with the same @e cls)
 * @param h_wire hash of wire transfer details of the merchant (should be same for all callbacks with the same @e cls)
 * @param account_details where did we transfer the funds?
 * @param exec_time execution time of the wire transfer (should be same for all callbacks with the same @e cls)
 * @param h_contract_terms which proposal was this payment about
 * @param denom_pub denomination of @a coin_pub
 * @param coin_pub which public key was this payment about
 * @param coin_value amount contributed by this coin in total (with fee)
 * @param deposit_fee applicable deposit fee for this coin, actual
 *        fees charged may differ if coin was refunded
 */
static void
wire_transfer_information_cb (void *cls,
                              uint64_t rowid,
                              const struct
                              TALER_MerchantPublicKeyP *merchant_pub,
                              const struct GNUNET_HashCode *h_wire,
                              const json_t *account_details,
                              struct GNUNET_TIME_Absolute exec_time,
                              const struct GNUNET_HashCode *h_contract_terms,
                              const struct
                              TALER_DenominationPublicKey *denom_pub,
                              const struct TALER_CoinSpendPublicKeyP *coin_pub,
                              const struct TALER_Amount *coin_value,
                              const struct TALER_Amount *deposit_fee)
{
  struct WireCheckContext *wcc = cls;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct TALER_Amount computed_value;
  struct TALER_Amount coin_value_without_fee;
  struct TALER_EXCHANGEDB_TransactionList *tl;
  const struct TALER_CoinPublicInfo *coin;
  enum GNUNET_DB_QueryStatus qs;
  struct GNUNET_HashCode hw;

  if (GNUNET_OK !=
      TALER_JSON_merchant_wire_signature_hash (account_details,
                                               &hw))
  {
    wcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "failed to compute hash of given wire data");
    return;
  }
  if (0 !=
      GNUNET_memcmp (&hw,
                     h_wire))
  {
    wcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "database contains wrong hash code for wire details");
    return;
  }

  /* Obtain coin's transaction history */
  qs = edb->get_coin_transactions (edb->cls,
                                   esession,
                                   coin_pub,
                                   GNUNET_YES,
                                   &tl);
  if ( (qs < 0) ||
       (NULL == tl) )
  {
    wcc->qs = qs;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "no transaction history for coin claimed in aggregation");
    return;
  }

  /* Obtain general denomination information about the coin */
  coin = NULL;
  switch (tl->type)
  {
  case TALER_EXCHANGEDB_TT_DEPOSIT:
    coin = &tl->details.deposit->coin;
    break;
  case TALER_EXCHANGEDB_TT_REFRESH_MELT:
    coin = &tl->details.melt->session.coin;
    break;
  case TALER_EXCHANGEDB_TT_REFUND:
    coin = &tl->details.refund->coin;
    break;
  case TALER_EXCHANGEDB_TT_OLD_COIN_PAYBACK:
    coin = &tl->details.payback_refresh->coin;
    break;
  case TALER_EXCHANGEDB_TT_PAYBACK:
    coin = &tl->details.payback->coin;
    break;
  case TALER_EXCHANGEDB_TT_PAYBACK_REFRESH:
    coin = &tl->details.payback_refresh->coin;
    break;
  }
  GNUNET_assert (NULL != coin); /* hard check that switch worked */
  qs = get_denomination_info_by_hash (&coin->denom_pub_hash,
                                      &dki);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    edb->free_coin_transaction_list (edb->cls,
                                     tl);
    wcc->qs = qs;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "could not find denomination key for coin claimed in aggregation");
    return;
  }
  if (GNUNET_OK !=
      TALER_test_coin_valid (coin,
                             denom_pub))
  {
    report (report_bad_sig_losses,
            json_pack ("{s:s, s:I, s:o, s:o}",
                       "operation", "wire",
                       "row", (json_int_t) rowid,
                       "loss", TALER_JSON_from_amount (coin_value),
                       "key_pub", GNUNET_JSON_from_data_auto (
                         &dki->properties.denom_hash)));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_sig_loss,
                                    &total_bad_sig_loss,
                                    coin_value));

    edb->free_coin_transaction_list (edb->cls,
                                     tl);
    wcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    report_row_inconsistency ("deposit",
                              rowid,
                              "coin denomination signature invalid");
    return;
  }

  GNUNET_assert (NULL != dki); /* mostly to help static analysis */
  /* Check transaction history to see if it supports aggregate
     valuation */
  if (GNUNET_OK !=
      check_transaction_history_for_deposit (coin_pub,
                                             h_contract_terms,
                                             merchant_pub,
                                             dki,
                                             tl,
                                             &computed_value))
  {
    wcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    report_row_inconsistency ("coin history",
                              rowid,
                              "failed to verify coin history (for deposit)");
    return;
  }
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&coin_value_without_fee,
                             coin_value,
                             deposit_fee))
  {
    wcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    report_amount_arithmetic_inconsistency ("aggregation (fee structure)",
                                            rowid,
                                            coin_value,
                                            deposit_fee,
                                            -1);
    return;
  }
  if (0 !=
      TALER_amount_cmp (&computed_value,
                        &coin_value_without_fee))
  {
    wcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    report_amount_arithmetic_inconsistency ("aggregation (contribution)",
                                            rowid,
                                            &coin_value_without_fee,
                                            &computed_value,
                                            -1);
  }
  edb->free_coin_transaction_list (edb->cls,
                                   tl);

  /* Check other details of wire transfer match */
  if (0 != GNUNET_memcmp (h_wire,
                          &wcc->h_wire))
  {
    wcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "wire method of aggregate do not match wire transfer");
  }
  if (0 != GNUNET_memcmp (h_wire,
                          &wcc->h_wire))
  {
    wcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "account details of aggregate do not match account details of wire transfer");
    return;
  }
  if (exec_time.abs_value_us != wcc->date.abs_value_us)
  {
    /* This should be impossible from database constraints */
    GNUNET_break (0);
    wcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    report_row_inconsistency ("aggregation",
                              rowid,
                              "date given in aggregate does not match wire transfer date");
    return;
  }

  /* Add coin's contribution to total aggregate value */
  if (GNUNET_OK !=
      TALER_amount_add (&wcc->total_deposits,
                        &wcc->total_deposits,
                        &coin_value_without_fee))
  {
    GNUNET_break (0);
    wcc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return;
  }
}


/**
 * Lookup the wire fee that the exchange charges at @a timestamp.
 *
 * @param ac context for caching the result
 * @param method method of the wire plugin
 * @param timestamp time for which we need the fee
 * @return NULL on error (fee unknown)
 */
static const struct TALER_Amount *
get_wire_fee (struct AggregationContext *ac,
              const char *method,
              struct GNUNET_TIME_Absolute timestamp)
{
  struct WireFeeInfo *wfi;
  struct WireFeeInfo *pos;
  struct TALER_MasterSignatureP master_sig;

  /* Check if fee is already loaded in cache */
  for (pos = ac->fee_head; NULL != pos; pos = pos->next)
  {
    if ( (pos->start_date.abs_value_us <= timestamp.abs_value_us) &&
         (pos->end_date.abs_value_us > timestamp.abs_value_us) )
      return &pos->wire_fee;
    if (pos->start_date.abs_value_us > timestamp.abs_value_us)
      break;
  }

  /* Lookup fee in exchange database */
  wfi = GNUNET_new (struct WireFeeInfo);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      edb->get_wire_fee (edb->cls,
                         esession,
                         method,
                         timestamp,
                         &wfi->start_date,
                         &wfi->end_date,
                         &wfi->wire_fee,
                         &wfi->closing_fee,
                         &master_sig))
  {
    GNUNET_break (0);
    GNUNET_free (wfi);
    return NULL;
  }

  /* Check signature. (This is not terribly meaningful as the exchange can
     easily make this one up, but it means that we have proof that the master
     key was used for inconsistent wire fees if a merchant complains.) */
  {
    struct TALER_MasterWireFeePS wf;

    wf.purpose.purpose = htonl (TALER_SIGNATURE_MASTER_WIRE_FEES);
    wf.purpose.size = htonl (sizeof (wf));
    GNUNET_CRYPTO_hash (method,
                        strlen (method) + 1,
                        &wf.h_wire_method);
    wf.start_date = GNUNET_TIME_absolute_hton (wfi->start_date);
    wf.end_date = GNUNET_TIME_absolute_hton (wfi->end_date);
    TALER_amount_hton (&wf.wire_fee,
                       &wfi->wire_fee);
    TALER_amount_hton (&wf.closing_fee,
                       &wfi->closing_fee);
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_WIRE_FEES,
                                    &wf.purpose,
                                    &master_sig.eddsa_signature,
                                    &master_pub.eddsa_pub))
    {
      report_row_inconsistency ("wire-fee",
                                timestamp.abs_value_us,
                                "wire fee signature invalid at given time");
    }
  }

  /* Established fee, keep in sorted list */
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Wire fee is %s starting at %s\n",
              TALER_amount2s (&wfi->wire_fee),
              GNUNET_STRINGS_absolute_time_to_string (wfi->start_date));
  if ( (NULL == pos) ||
       (NULL == pos->prev) )
    GNUNET_CONTAINER_DLL_insert (ac->fee_head,
                                 ac->fee_tail,
                                 wfi);
  else
    GNUNET_CONTAINER_DLL_insert_after (ac->fee_head,
                                       ac->fee_tail,
                                       pos->prev,
                                       wfi);
  /* Check non-overlaping fee invariant */
  if ( (NULL != wfi->prev) &&
       (wfi->prev->end_date.abs_value_us > wfi->start_date.abs_value_us) )
  {
    report (report_fee_time_inconsistencies,
            json_pack ("{s:s, s:s, s:o}",
                       "type", method,
                       "diagnostic", "start date before previous end date",
                       "time", json_from_time_abs (wfi->start_date)));
  }
  if ( (NULL != wfi->next) &&
       (wfi->next->start_date.abs_value_us >= wfi->end_date.abs_value_us) )
  {
    report (report_fee_time_inconsistencies,
            json_pack ("{s:s, s:s, s:o}",
                       "type", method,
                       "diagnostic", "end date date after next start date",
                       "time", json_from_time_abs (wfi->end_date)));
  }
  return &wfi->wire_fee;
}


/**
 * Check that a wire transfer made by the exchange is valid
 * (has matching deposits).
 *
 * @param cls a `struct AggregationContext`
 * @param rowid identifier of the respective row in the database
 * @param date timestamp of the wire transfer (roughly)
 * @param wtid wire transfer subject
 * @param wire wire transfer details of the receiver
 * @param amount amount that was wired
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to stop iteration
 */
static int
check_wire_out_cb
  (void *cls,
  uint64_t rowid,
  struct GNUNET_TIME_Absolute date,
  const struct TALER_WireTransferIdentifierRawP *wtid,
  const json_t *wire,
  const struct TALER_Amount *amount)
{
  struct AggregationContext *ac = cls;
  struct WireCheckContext wcc;
  struct TALER_WIRE_Plugin *plugin;
  struct TALER_Amount final_amount;
  struct TALER_Amount exchange_gain;
  enum GNUNET_DB_QueryStatus qs;
  char *method;

  /* should be monotonically increasing */
  GNUNET_assert (rowid >= ppa.last_wire_out_serial_id);
  ppa.last_wire_out_serial_id = rowid + 1;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Checking wire transfer %s over %s performed on %s\n",
              TALER_B2S (wtid),
              TALER_amount2s (amount),
              GNUNET_STRINGS_absolute_time_to_string (date));
  if (NULL == (method = TALER_JSON_wire_to_method (wire)))
  {
    report_row_inconsistency ("wire_out",
                              rowid,
                              "specified wire address lacks method");
    return GNUNET_OK;
  }

  wcc.ac = ac;
  wcc.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  wcc.date = date;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (amount->currency,
                                        &wcc.total_deposits));
  if (GNUNET_OK !=
      TALER_JSON_merchant_wire_signature_hash (wire,
                                               &wcc.h_wire))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  qs = edb->lookup_wire_transfer (edb->cls,
                                  esession,
                                  wtid,
                                  &wire_transfer_information_cb,
                                  &wcc);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    ac->qs = qs;
    GNUNET_free (method);
    return GNUNET_SYSERR;
  }

  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != wcc.qs)
  {
    /* FIXME: can we provide a more detailed error report? */
    report_row_inconsistency ("wire_out",
                              rowid,
                              "audit of associated transactions failed");
    GNUNET_free (method);
    return GNUNET_OK;
  }

  /* Subtract aggregation fee from total (if possible) */
  {
    const struct TALER_Amount *wire_fee;

    wire_fee = get_wire_fee (ac,
                             method,
                             date);
    if (NULL == wire_fee)
    {
      report_row_inconsistency ("wire-fee",
                                date.abs_value_us,
                                "wire fee unavailable for given time");
      /* If fee is unknown, we just assume the fee is zero */
      final_amount = wcc.total_deposits;
    }
    else if (GNUNET_SYSERR ==
             TALER_amount_subtract (&final_amount,
                                    &wcc.total_deposits,
                                    wire_fee))
    {
      report_amount_arithmetic_inconsistency
        ("wire out (fee structure)",
        rowid,
        &wcc.total_deposits,
        wire_fee,
        -1);
      /* If fee arithmetic fails, we just assume the fee is zero */
      final_amount = wcc.total_deposits;
    }
  }

  /* Round down to amount supported by wire method */
  plugin = get_wire_plugin
             (ac,
             TALER_WIRE_get_plugin_from_method (method));
  if (NULL == plugin)
  {
    GNUNET_break (0);
    GNUNET_free (method);
    return GNUNET_SYSERR;
  }
  GNUNET_free (method);
  GNUNET_break (GNUNET_SYSERR !=
                plugin->amount_round (plugin->cls,
                                      &final_amount));

  /* Calculate the exchange's gain as the fees plus rounding differences! */
  if (GNUNET_OK !=
      TALER_amount_subtract (&exchange_gain,
                             &wcc.total_deposits,
                             &final_amount))
  {
    GNUNET_break (0);
    ac->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }

  /* Sum up aggregation fees (we simply include the rounding gains) */
  if (GNUNET_OK !=
      TALER_amount_add (&total_aggregation_fee_income,
                        &total_aggregation_fee_income,
                        &exchange_gain))
  {
    GNUNET_break (0);
    ac->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }

  /* Check that calculated amount matches actual amount */
  if (0 != TALER_amount_cmp (amount,
                             &final_amount))
  {
    struct TALER_Amount delta;

    if (0 < TALER_amount_cmp (amount,
                              &final_amount))
    {
      /* amount > final_amount */
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_subtract (&delta,
                                            amount,
                                            &final_amount));
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_add (&total_wire_out_delta_plus,
                                       &total_wire_out_delta_plus,
                                       &delta));
    }
    else
    {
      /* amount < final_amount */
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_subtract (&delta,
                                            &final_amount,
                                            amount));
      GNUNET_assert (GNUNET_OK ==
                     TALER_amount_add (&total_wire_out_delta_minus,
                                       &total_wire_out_delta_minus,
                                       &delta));
    }

    report (report_wire_out_inconsistencies,
            json_pack ("{s:O, s:I, s:o, s:o}",
                       "destination_account", wire,
                       "rowid", (json_int_t) rowid,
                       "expected",
                       TALER_JSON_from_amount (&final_amount),
                       "claimed",
                       TALER_JSON_from_amount (amount)));
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Wire transfer %s is OK\n",
              TALER_B2S (wtid));
  return GNUNET_OK;
}


/**
 * Analyze the exchange aggregator's payment processing.
 *
 * @param cls closure
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
analyze_aggregations (void *cls)
{
  struct AggregationContext ac;
  struct WirePlugin *wc;
  struct WireFeeInfo *wfi;
  enum GNUNET_DB_QueryStatus qsx;
  enum GNUNET_DB_QueryStatus qs;
  enum GNUNET_DB_QueryStatus qsp;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing aggregations\n");
  qsp = adb->get_auditor_progress_aggregation (adb->cls,
                                               asession,
                                               &master_pub,
                                               &ppa);
  if (0 > qsp)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsp);
    return qsp;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsp)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                _ (
                  "First analysis using this auditor, starting audit from scratch\n"));
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                _ ("Resuming aggregation audit at %llu\n"),
                (unsigned long long) ppa.last_wire_out_serial_id);
  }

  memset (&ac,
          0,
          sizeof (ac));
  qsx = adb->get_wire_fee_summary (adb->cls,
                                   asession,
                                   &master_pub,
                                   &total_aggregation_fee_income);
  if (0 > qsx)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx);
    return qsx;
  }
  ac.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  qs = edb->select_wire_out_above_serial_id (edb->cls,
                                             esession,
                                             ppa.last_wire_out_serial_id,
                                             &check_wire_out_cb,
                                             &ac);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    ac.qs = qs;
  }
  while (NULL != (wc = ac.wire_head))
  {
    GNUNET_CONTAINER_DLL_remove (ac.wire_head,
                                 ac.wire_tail,
                                 wc);
    TALER_WIRE_plugin_unload (wc->plugin);
    GNUNET_free (wc->type);
    GNUNET_free (wc);
  }
  while (NULL != (wfi = ac.fee_head))
  {
    GNUNET_CONTAINER_DLL_remove (ac.fee_head,
                                 ac.fee_tail,
                                 wfi);
    GNUNET_free (wfi);
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != ac.qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == ac.qs);
    return ac.qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsx)
    ac.qs = adb->insert_wire_fee_summary (adb->cls,
                                          asession,
                                          &master_pub,
                                          &total_aggregation_fee_income);
  else
    ac.qs = adb->update_wire_fee_summary (adb->cls,
                                          asession,
                                          &master_pub,
                                          &total_aggregation_fee_income);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != ac.qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == ac.qs);
    return ac.qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsp)
    qs = adb->update_auditor_progress_aggregation (adb->cls,
                                                   asession,
                                                   &master_pub,
                                                   &ppa);
  else
    qs = adb->insert_auditor_progress_aggregation (adb->cls,
                                                   asession,
                                                   &master_pub,
                                                   &ppa);
  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              _ ("Concluded aggregation audit step at %llu\n"),
              (unsigned long long) ppa.last_wire_out_serial_id);

  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/* ************************* Analyze coins ******************** */
/* This logic checks that the exchange did the right thing for each
   coin, checking deposits, refunds, refresh* and known_coins
   tables */


/**
 * Summary data we keep per denomination.
 */
struct DenominationSummary
{
  /**
   * Total value of outstanding (not deposited) coins issued with this
   * denomination key.
   */
  struct TALER_Amount denom_balance;

  /**
   * Total losses made (once coins deposited exceed
   * coins withdrawn and thus the @e denom_balance is
   * effectively negative).
   */
  struct TALER_Amount denom_loss;

  /**
   * Total value of coins issued with this denomination key.
   */
  struct TALER_Amount denom_risk;

  /**
   * Total value of coins subjected to payback with this denomination key.
   */
  struct TALER_Amount denom_payback;

  /**
   * How many coins (not their amount!) of this denomination
   * did the exchange issue overall?
   */
  uint64_t num_issued;

  /**
   * Denomination key information for this denomination.
   */
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;

  /**
   * #GNUNET_YES if this record already existed in the DB.
   * Used to decide between insert/update in
   * #sync_denomination().
   */
  int in_db;

  /**
   * Should we report an emergency for this denomination?
   */
  int report_emergency;

  /**
   * #GNUNET_YES if this denomination was revoked.
   */
  int was_revoked;
};


/**
 * Closure for callbacks during #analyze_coins().
 */
struct CoinContext
{

  /**
   * Map for tracking information about denominations.
   */
  struct GNUNET_CONTAINER_MultiHashMap *denom_summaries;

  /**
   * Current write/replace offset in the circular @e summaries buffer.
   */
  unsigned int summaries_off;

  /**
   * Transaction status code.
   */
  enum GNUNET_DB_QueryStatus qs;

};


/**
 * Initialize information about denomination from the database.
 *
 * @param denom_hash hash of the public key of the denomination
 * @param[out] ds summary to initialize
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
init_denomination (const struct GNUNET_HashCode *denom_hash,
                   struct DenominationSummary *ds)
{
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_MasterSignatureP msig;
  uint64_t rowid;

  qs = adb->get_denomination_balance (adb->cls,
                                      asession,
                                      denom_hash,
                                      &ds->denom_balance,
                                      &ds->denom_loss,
                                      &ds->denom_risk,
                                      &ds->denom_payback,
                                      &ds->num_issued);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    ds->in_db = GNUNET_YES;
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Starting balance for denomination `%s' is %s\n",
                GNUNET_h2s (denom_hash),
                TALER_amount2s (&ds->denom_balance));
    return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  }
  qs = edb->get_denomination_revocation (edb->cls,
                                         esession,
                                         denom_hash,
                                         &msig,
                                         &rowid);
  if (0 > qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 < qs)
  {
    /* check revocation signature */
    struct TALER_MasterDenominationKeyRevocationPS rm;

    rm.purpose.purpose = htonl (
      TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED);
    rm.purpose.size = htonl (sizeof (rm));
    rm.h_denom_pub = *denom_hash;
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_verify (
          TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED,
          &rm.purpose,
          &msig.eddsa_signature,
          &master_pub.eddsa_pub))
    {
      report_row_inconsistency ("denomination revocation table",
                                rowid,
                                "revocation signature invalid");
    }
    else
    {
      ds->was_revoked = GNUNET_YES;
    }
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &ds->denom_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &ds->denom_loss));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &ds->denom_risk));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &ds->denom_payback));
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting balance for denomination `%s' is %s\n",
              GNUNET_h2s (denom_hash),
              TALER_amount2s (&ds->denom_balance));
  return GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
}


/**
 * Obtain the denomination summary for the given @a dh
 *
 * @param cc our execution context
 * @param dki denomination key information for @a dh
 * @param dh the denomination hash to use for the lookup
 * @return NULL on error
 */
static struct DenominationSummary *
get_denomination_summary (struct CoinContext *cc,
                          const struct
                          TALER_EXCHANGEDB_DenominationKeyInformationP *dki,
                          const struct GNUNET_HashCode *dh)
{
  struct DenominationSummary *ds;

  ds = GNUNET_CONTAINER_multihashmap_get (cc->denom_summaries,
                                          dh);
  if (NULL != ds)
    return ds;
  ds = GNUNET_new (struct DenominationSummary);
  ds->dki = dki;
  if (0 > (cc->qs = init_denomination (dh,
                                       ds)))
  {
    GNUNET_break (0);
    GNUNET_free (ds);
    return NULL;
  }
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONTAINER_multihashmap_put (cc->denom_summaries,
                                                    dh,
                                                    ds,
                                                    GNUNET_CONTAINER_MULTIHASHMAPOPTION_UNIQUE_ONLY));
  return ds;
}


/**
 * Write information about the current knowledge about a denomination key
 * back to the database and update our global reporting data about the
 * denomination.  Also remove and free the memory of @a value.
 *
 * @param cls the `struct CoinContext`
 * @param denom_hash the hash of the denomination key
 * @param value a `struct DenominationSummary`
 * @return #GNUNET_OK (continue to iterate)
 */
static int
sync_denomination (void *cls,
                   const struct GNUNET_HashCode *denom_hash,
                   void *value)
{
  struct CoinContext *cc = cls;
  struct DenominationSummary *ds = value;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki = ds->dki;
  struct GNUNET_TIME_Absolute now;
  struct GNUNET_TIME_Absolute expire_deposit;
  struct GNUNET_TIME_Absolute expire_deposit_grace;
  enum GNUNET_DB_QueryStatus qs;

  now = GNUNET_TIME_absolute_get ();
  expire_deposit = GNUNET_TIME_absolute_ntoh (dki->properties.expire_deposit);
  /* add day grace period to deal with clocks not being perfectly synchronized */
  expire_deposit_grace = GNUNET_TIME_absolute_add (expire_deposit,
                                                   DEPOSIT_GRACE_PERIOD);
  if (now.abs_value_us > expire_deposit_grace.abs_value_us)
  {
    /* Denominationkey has expired, book remaining balance of
       outstanding coins as revenue; and reduce cc->risk exposure. */
    if (ds->in_db)
      qs = adb->del_denomination_balance (adb->cls,
                                          asession,
                                          denom_hash);
    else
      qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
    if ( (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs) &&
         ( (0 != ds->denom_risk.value) ||
           (0 != ds->denom_risk.fraction) ) )
    {
      /* The denomination expired and carried a balance; we can now
         book the remaining balance as profit, and reduce our risk
         exposure by the accumulated risk of the denomination. */
      if (GNUNET_SYSERR ==
          TALER_amount_subtract (&total_risk,
                                 &total_risk,
                                 &ds->denom_risk))
      {
        /* Holy smokes, our risk assessment was inconsistent!
           This is really, really bad. */
        GNUNET_break (0);
        cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      }
    }
    if ( (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs) &&
         ( (0 != ds->denom_balance.value) ||
           (0 != ds->denom_balance.fraction) ) )
    {
      /* book denom_balance coin expiration profits! */
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Denomination `%s' expired, booking %s in expiration profits\n",
                  GNUNET_h2s (denom_hash),
                  TALER_amount2s (&ds->denom_balance));
      if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
          (qs = adb->insert_historic_denom_revenue (adb->cls,
                                                    asession,
                                                    &master_pub,
                                                    denom_hash,
                                                    expire_deposit,
                                                    &ds->denom_balance,
                                                    &ds->denom_payback)))
      {
        /* Failed to store profits? Bad database */
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        cc->qs = qs;
      }
    }
  }
  else
  {
    long long cnt;

    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Final balance for denomination `%s' is %s (%llu)\n",
                GNUNET_h2s (denom_hash),
                TALER_amount2s (&ds->denom_balance),
                (unsigned long long) ds->num_issued);
    cnt = edb->count_known_coins (edb->cls,
                                  esession,
                                  denom_hash);
    if (0 > cnt)
    {
      /* Failed to obtain count? Bad database */
      qs = (enum GNUNET_DB_QueryStatus) cnt;
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      cc->qs = qs;
    }
    else
    {
      if (ds->num_issued < (uint64_t) cnt)
      {
        report_emergency_by_count (dki,
                                   ds->num_issued,
                                   cnt,
                                   &ds->denom_risk);
      }
      if (GNUNET_YES == ds->report_emergency)
      {
        report_emergency_by_amount (dki,
                                    &ds->denom_risk,
                                    &ds->denom_loss);

      }
      if (ds->in_db)
        qs = adb->update_denomination_balance (adb->cls,
                                               asession,
                                               denom_hash,
                                               &ds->denom_balance,
                                               &ds->denom_loss,
                                               &ds->denom_risk,
                                               &ds->denom_payback,
                                               ds->num_issued);
      else
        qs = adb->insert_denomination_balance (adb->cls,
                                               asession,
                                               denom_hash,
                                               &ds->denom_balance,
                                               &ds->denom_loss,
                                               &ds->denom_risk,
                                               &ds->denom_payback,
                                               ds->num_issued);
    }
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
  }
  GNUNET_assert (GNUNET_YES ==
                 GNUNET_CONTAINER_multihashmap_remove (cc->denom_summaries,
                                                       denom_hash,
                                                       ds));
  GNUNET_free (ds);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != cc->qs)
    return GNUNET_SYSERR;
  return GNUNET_OK;
}


/**
 * Function called with details about all withdraw operations.
 * Updates the denomination balance and the overall balance as
 * we now have additional coins that have been issued.
 *
 * Note that the signature was already checked in
 * #handle_reserve_out(), so we do not check it again here.
 *
 * @param cls our `struct CoinContext`
 * @param rowid unique serial ID for the refresh session in our DB
 * @param h_blind_ev blinded hash of the coin's public key
 * @param denom_pub public denomination key of the deposited coin
 * @param denom_sig signature over the deposited coin
 * @param reserve_pub public key of the reserve
 * @param reserve_sig signature over the withdraw operation (verified elsewhere)
 * @param execution_date when did the wallet withdraw the coin
 * @param amount_with_fee amount that was withdrawn
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
withdraw_cb (void *cls,
             uint64_t rowid,
             const struct GNUNET_HashCode *h_blind_ev,
             const struct TALER_DenominationPublicKey *denom_pub,
             const struct TALER_DenominationSignature *denom_sig,
             const struct TALER_ReservePublicKeyP *reserve_pub,
             const struct TALER_ReserveSignatureP *reserve_sig,
             struct GNUNET_TIME_Absolute execution_date,
             const struct TALER_Amount *amount_with_fee)
{
  struct CoinContext *cc = cls;
  struct DenominationSummary *ds;
  struct GNUNET_HashCode dh;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct TALER_Amount value;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_assert (rowid >= ppc.last_withdraw_serial_id); /* should be monotonically increasing */
  ppc.last_withdraw_serial_id = rowid + 1;

  qs = get_denomination_info (denom_pub,
                              &dki,
                              &dh);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    /* The key not existing should be prevented by foreign key constraints,
       so must be a transient DB error. */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }
  ds = get_denomination_summary (cc,
                                 dki,
                                 &dh);
  if (NULL == ds)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  TALER_amount_ntoh (&value,
                     &dki->properties.value);
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Issued coin in denomination `%s' of total value %s\n",
              GNUNET_h2s (&dh),
              TALER_amount2s (&value));
  ds->num_issued++;
  if (GNUNET_OK !=
      TALER_amount_add (&ds->denom_balance,
                        &ds->denom_balance,
                        &value))
  {
    GNUNET_break (0);
    cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "New balance of denomination `%s' is %s\n",
              GNUNET_h2s (&dh),
              TALER_amount2s (&ds->denom_balance));
  if (GNUNET_OK !=
      TALER_amount_add (&total_escrow_balance,
                        &total_escrow_balance,
                        &value))
  {
    GNUNET_break (0);
    cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_amount_add (&total_risk,
                        &total_risk,
                        &value))
  {
    GNUNET_break (0);
    cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_amount_add (&ds->denom_risk,
                        &ds->denom_risk,
                        &value))
  {
    GNUNET_break (0);
    cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * Closure for #reveal_data_cb().
 */
struct RevealContext
{

  /**
   * Denomination public keys of the new coins.
   */
  struct TALER_DenominationPublicKey *new_dps;

  /**
   * Size of the @a new_dp and @a new_dki arrays.
   */
  unsigned int num_newcoins;
};


/**
 * Function called with information about a refresh order.
 *
 * @param cls closure
 * @param rowid unique serial ID for the row in our database
 * @param num_newcoins size of the @a rrcs array
 * @param rrcs array of @a num_newcoins information about coins to be created
 * @param num_tprivs number of entries in @a tprivs, should be #TALER_CNC_KAPPA - 1
 * @param tprivs array of @e num_tprivs transfer private keys
 * @param tp transfer public key information
 */
static void
reveal_data_cb (void *cls,
                uint32_t num_newcoins,
                const struct TALER_EXCHANGEDB_RefreshRevealedCoin *rrcs,
                unsigned int num_tprivs,
                const struct TALER_TransferPrivateKeyP *tprivs,
                const struct TALER_TransferPublicKeyP *tp)
{
  struct RevealContext *rctx = cls;

  rctx->num_newcoins = num_newcoins;
  rctx->new_dps = GNUNET_new_array (num_newcoins,
                                    struct TALER_DenominationPublicKey);
  for (unsigned int i = 0; i<num_newcoins; i++)
    rctx->new_dps[i].rsa_public_key
      = GNUNET_CRYPTO_rsa_public_key_dup (rrcs[i].denom_pub.rsa_public_key);
}


/**
 * Check that the @a coin_pub is a known coin with a proper
 * signature for denominatinon @a denom_pub. If not, report
 * a loss of @a loss_potential.
 *
 * @param coin_pub public key of a coin
 * @param denom_pub expected denomination of the coin
 * @return database transaction status, on success
 *  #GNUNET_DB_STATUS_SUCCESS_ONE_RESULT
 */
static enum GNUNET_DB_QueryStatus
check_known_coin (const struct TALER_CoinSpendPublicKeyP *coin_pub,
                  const struct TALER_DenominationPublicKey *denom_pub,
                  const struct TALER_Amount *loss_potential)
{
  struct TALER_CoinPublicInfo ci;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Checking denomination signature on %s\n",
              TALER_B2S (coin_pub));
  qs = edb->get_known_coin (edb->cls,
                            esession,
                            coin_pub,
                            &ci);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (GNUNET_YES !=
      TALER_test_coin_valid (&ci,
                             denom_pub))
  {
    report (report_bad_sig_losses,
            json_pack ("{s:s, s:I, s:o, s:o}",
                       "operation", "known-coin",
                       "row", (json_int_t) -1,
                       "loss", TALER_JSON_from_amount (loss_potential),
                       "key_pub", GNUNET_JSON_from_data_auto (coin_pub)));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_sig_loss,
                                    &total_bad_sig_loss,
                                    loss_potential));

  }
  GNUNET_CRYPTO_rsa_signature_free (ci.denom_sig.rsa_signature);
  return qs;
}


/**
 * Function called with details about coins that were melted, with the
 * goal of auditing the refresh's execution.  Verifies the signature
 * and updates our information about coins outstanding (the old coin's
 * denomination has less, the fresh coins increased outstanding
 * balances).
 *
 * @param cls closure
 * @param rowid unique serial ID for the refresh session in our DB
 * @param denom_pub denomination public key of @a coin_pub
 * @param coin_pub public key of the coin
 * @param coin_sig signature from the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param noreveal_index which index was picked by the exchange in cut-and-choose
 * @param session_hash what is the session hash
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
refresh_session_cb (void *cls,
                    uint64_t rowid,
                    const struct TALER_DenominationPublicKey *denom_pub,
                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                    const struct TALER_CoinSpendSignatureP *coin_sig,
                    const struct TALER_Amount *amount_with_fee,
                    uint32_t noreveal_index,
                    const struct TALER_RefreshCommitmentP *rc)
{
  struct CoinContext *cc = cls;
  struct TALER_RefreshMeltCoinAffirmationPS rmc;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct DenominationSummary *dso;
  struct TALER_Amount amount_without_fee;
  struct TALER_Amount tmp;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_assert (rowid >= ppc.last_melt_serial_id); /* should be monotonically increasing */
  ppc.last_melt_serial_id = rowid + 1;

  qs = get_denomination_info (denom_pub,
                              &dki,
                              NULL);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      check_known_coin (coin_pub,
                        denom_pub,
                        amount_with_fee))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }

  /* verify melt signature */
  rmc.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_MELT);
  rmc.purpose.size = htonl (sizeof (rmc));
  rmc.rc = *rc;
  TALER_amount_hton (&rmc.amount_with_fee,
                     amount_with_fee);
  rmc.melt_fee = dki->properties.fee_refresh;
  rmc.coin_pub = *coin_pub;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_MELT,
                                  &rmc.purpose,
                                  &coin_sig->eddsa_signature,
                                  &coin_pub->eddsa_pub))
  {
    report (report_bad_sig_losses,
            json_pack ("{s:s, s:I, s:o, s:o}",
                       "operation", "melt",
                       "row", (json_int_t) rowid,
                       "loss", TALER_JSON_from_amount (amount_with_fee),
                       "key_pub", GNUNET_JSON_from_data_auto (coin_pub)));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_sig_loss,
                                    &total_bad_sig_loss,
                                    amount_with_fee));
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Melting coin %s in denomination `%s' of value %s\n",
              TALER_B2S (coin_pub),
              GNUNET_h2s (&dki->properties.denom_hash),
              TALER_amount2s (amount_with_fee));

  {
    struct RevealContext reveal_ctx;
    struct TALER_Amount refresh_cost;
    int err;

    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_get_zero (amount_with_fee->currency,
                                          &refresh_cost));
    memset (&reveal_ctx,
            0,
            sizeof (reveal_ctx));
    qs = edb->get_refresh_reveal (edb->cls,
                                  esession,
                                  rc,
                                  &reveal_data_cb,
                                  &reveal_ctx);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return GNUNET_SYSERR;
    }
    if ( (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs) ||
         (0 == reveal_ctx.num_newcoins) )
    {
      /* This can happen if /refresh/reveal was not yet called or only
         with invalid data, even if the exchange is correctly
         operating. We still report it. */
      report (report_refreshs_hanging,
              json_pack ("{s:I, s:o, s:o}",
                         "row", (json_int_t) rowid,
                         "amount", TALER_JSON_from_amount (amount_with_fee),
                         "coin_pub", GNUNET_JSON_from_data_auto (coin_pub)));
      GNUNET_break (GNUNET_OK ==
                    TALER_amount_add (&total_refresh_hanging,
                                      &total_refresh_hanging,
                                      amount_with_fee));
      return GNUNET_OK;
    }

    {
      const struct
      TALER_EXCHANGEDB_DenominationKeyInformationP *new_dkis[reveal_ctx.
                                                             num_newcoins];

      /* Update outstanding amounts for all new coin's denominations, and check
         that the resulting amounts are consistent with the value being refreshed. */
      err = GNUNET_NO;
      for (unsigned int i = 0; i<reveal_ctx.num_newcoins; i++)
      {
        /* lookup new coin denomination key */
        qs = get_denomination_info (&reveal_ctx.new_dps[i],
                                    &new_dkis[i],
                                    NULL);
        if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
        {
          GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
          cc->qs = qs;
          err = GNUNET_YES;
        }
        GNUNET_CRYPTO_rsa_public_key_free (
          reveal_ctx.new_dps[i].rsa_public_key);
        reveal_ctx.new_dps[i].rsa_public_key = NULL;
      }
      GNUNET_free (reveal_ctx.new_dps);
      reveal_ctx.new_dps = NULL;

      if (err)
        return GNUNET_SYSERR;

      /* calculate total refresh cost */
      for (unsigned int i = 0; i<reveal_ctx.num_newcoins; i++)
      {
        /* update cost of refresh */
        struct TALER_Amount fee;
        struct TALER_Amount value;

        TALER_amount_ntoh (&fee,
                           &new_dkis[i]->properties.fee_withdraw);
        TALER_amount_ntoh (&value,
                           &new_dkis[i]->properties.value);
        if ( (GNUNET_OK !=
              TALER_amount_add (&refresh_cost,
                                &refresh_cost,
                                &fee)) ||
             (GNUNET_OK !=
              TALER_amount_add (&refresh_cost,
                                &refresh_cost,
                                &value)) )
        {
          GNUNET_break (0);
          cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
          return GNUNET_SYSERR;
        }
      }

      /* compute contribution of old coin */
      {
        struct TALER_Amount melt_fee;

        TALER_amount_ntoh (&melt_fee,
                           &dki->properties.fee_refresh);
        if (GNUNET_OK !=
            TALER_amount_subtract (&amount_without_fee,
                                   amount_with_fee,
                                   &melt_fee))
        {
          GNUNET_break (0);
          cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
          return GNUNET_SYSERR;
        }
      }

      /* check old coin covers complete expenses */
      if (1 == TALER_amount_cmp (&refresh_cost,
                                 &amount_without_fee))
      {
        /* refresh_cost > amount_without_fee */
        report_amount_arithmetic_inconsistency ("melt (fee)",
                                                rowid,
                                                &amount_without_fee,
                                                &refresh_cost,
                                                -1);
        return GNUNET_OK;
      }

      /* update outstanding denomination amounts */
      for (unsigned int i = 0; i<reveal_ctx.num_newcoins; i++)
      {
        struct DenominationSummary *dsi;
        struct TALER_Amount value;

        dsi = get_denomination_summary (cc,
                                        new_dkis[i],
                                        &new_dkis[i]->properties.denom_hash);
        if (NULL == dsi)
        {
          GNUNET_break (0);
          return GNUNET_SYSERR;
        }
        TALER_amount_ntoh (&value,
                           &new_dkis[i]->properties.value);
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Created fresh coin in denomination `%s' of value %s\n",
                    GNUNET_h2s (&new_dkis[i]->properties.denom_hash),
                    TALER_amount2s (&value));
        dsi->num_issued++;
        if (GNUNET_OK !=
            TALER_amount_add (&dsi->denom_balance,
                              &dsi->denom_balance,
                              &value))
        {
          GNUNET_break (0);
          cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
          return GNUNET_SYSERR;
        }
        if (GNUNET_OK !=
            TALER_amount_add (&dsi->denom_risk,
                              &dsi->denom_risk,
                              &value))
        {
          GNUNET_break (0);
          cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
          return GNUNET_SYSERR;
        }
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "New balance of denomination `%s' is %s\n",
                    GNUNET_h2s (&new_dkis[i]->properties.denom_hash),
                    TALER_amount2s (&dsi->denom_balance));
        if (GNUNET_OK !=
            TALER_amount_add (&total_escrow_balance,
                              &total_escrow_balance,
                              &value))
        {
          GNUNET_break (0);
          cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
          return GNUNET_SYSERR;
        }
        if (GNUNET_OK !=
            TALER_amount_add (&total_risk,
                              &total_risk,
                              &value))
        {
          GNUNET_break (0);
          cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
          return GNUNET_SYSERR;
        }
      }
    }
  }

  /* update old coin's denomination balance */
  dso = get_denomination_summary (cc,
                                  dki,
                                  &dki->properties.denom_hash);
  if (NULL == dso)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&tmp,
                             &dso->denom_balance,
                             amount_with_fee))
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&dso->denom_loss,
                                     &dso->denom_loss,
                                     amount_with_fee));
    dso->report_emergency = GNUNET_YES;
  }
  else
  {
    dso->denom_balance = tmp;
  }
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&total_escrow_balance,
                             &total_escrow_balance,
                             amount_with_fee))
  {
    /* This should not be possible, unless the AUDITOR
       has a bug in tracking total balance. */
    GNUNET_break (0);
    cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "New balance of denomination `%s' after melt is %s\n",
              GNUNET_h2s (&dki->properties.denom_hash),
              TALER_amount2s (&dso->denom_balance));

  /* update global melt fees */
  {
    struct TALER_Amount rfee;

    TALER_amount_ntoh (&rfee,
                       &dki->properties.fee_refresh);
    if (GNUNET_OK !=
        TALER_amount_add (&total_melt_fee_income,
                          &total_melt_fee_income,
                          &rfee))
    {
      GNUNET_break (0);
      cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return GNUNET_SYSERR;
    }
  }

  /* We're good! */
  return GNUNET_OK;
}


/**
 * Function called with details about deposits that have been made,
 * with the goal of auditing the deposit's execution.
 *
 * @param cls closure
 * @param rowid unique serial ID for the deposit in our DB
 * @param timestamp when did the deposit happen
 * @param merchant_pub public key of the merchant
 * @param denom_pub denomination public key of @a coin_pub
 * @param coin_pub public key of the coin
 * @param coin_sig signature from the coin
 * @param amount_with_fee amount that was deposited including fee
 * @param h_contract_terms hash of the proposal data known to merchant and customer
 * @param refund_deadline by which the merchant adviced that he might want
 *        to get a refund
 * @param wire_deadline by which the merchant adviced that he would like the
 *        wire transfer to be executed
 * @param receiver_wire_account wire details for the merchant, NULL from iterate_matching_deposits()
 * @param done flag set if the deposit was already executed (or not)
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
deposit_cb (void *cls,
            uint64_t rowid,
            struct GNUNET_TIME_Absolute timestamp,
            const struct TALER_MerchantPublicKeyP *merchant_pub,
            const struct TALER_DenominationPublicKey *denom_pub,
            const struct TALER_CoinSpendPublicKeyP *coin_pub,
            const struct TALER_CoinSpendSignatureP *coin_sig,
            const struct TALER_Amount *amount_with_fee,
            const struct GNUNET_HashCode *h_contract_terms,
            struct GNUNET_TIME_Absolute refund_deadline,
            struct GNUNET_TIME_Absolute wire_deadline,
            const json_t *receiver_wire_account,
            int done)
{
  struct CoinContext *cc = cls;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct DenominationSummary *ds;
  struct TALER_DepositRequestPS dr;
  struct TALER_Amount tmp;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_assert (rowid >= ppc.last_deposit_serial_id); /* should be monotonically increasing */
  ppc.last_deposit_serial_id = rowid + 1;

  qs = get_denomination_info (denom_pub,
                              &dki,
                              NULL);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
      check_known_coin (coin_pub,
                        denom_pub,
                        amount_with_fee))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }

  /* Verify deposit signature */
  dr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_DEPOSIT);
  dr.purpose.size = htonl (sizeof (dr));
  dr.h_contract_terms = *h_contract_terms;
  if (GNUNET_OK !=
      TALER_JSON_merchant_wire_signature_hash (receiver_wire_account,
                                               &dr.h_wire))
  {
    GNUNET_break (0);
    cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }
  dr.timestamp = GNUNET_TIME_absolute_hton (timestamp);
  dr.refund_deadline = GNUNET_TIME_absolute_hton (refund_deadline);
  TALER_amount_hton (&dr.amount_with_fee,
                     amount_with_fee);
  dr.deposit_fee = dki->properties.fee_deposit;
  dr.merchant = *merchant_pub;
  dr.coin_pub = *coin_pub;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_DEPOSIT,
                                  &dr.purpose,
                                  &coin_sig->eddsa_signature,
                                  &coin_pub->eddsa_pub))
  {
    report (report_bad_sig_losses,
            json_pack ("{s:s, s:I, s:o, s:o}",
                       "operation", "deposit",
                       "row", (json_int_t) rowid,
                       "loss", TALER_JSON_from_amount (amount_with_fee),
                       "key_pub", GNUNET_JSON_from_data_auto (coin_pub)));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_sig_loss,
                                    &total_bad_sig_loss,
                                    amount_with_fee));
    return GNUNET_OK;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Deposited coin %s in denomination `%s' of value %s\n",
              TALER_B2S (coin_pub),
              GNUNET_h2s (&dki->properties.denom_hash),
              TALER_amount2s (amount_with_fee));

  /* update old coin's denomination balance */
  ds = get_denomination_summary (cc,
                                 dki,
                                 &dki->properties.denom_hash);
  if (NULL == ds)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&tmp,
                             &ds->denom_balance,
                             amount_with_fee))
  {
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_add (&ds->denom_loss,
                                     &ds->denom_loss,
                                     amount_with_fee));
    ds->report_emergency = GNUNET_YES;
  }
  else
  {
    ds->denom_balance = tmp;
  }
  if (GNUNET_SYSERR ==
      TALER_amount_subtract (&total_escrow_balance,
                             &total_escrow_balance,
                             amount_with_fee))
  {
    /* This should not be possible, unless the AUDITOR
       has a bug in tracking total balance. */
    GNUNET_break (0);
    cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "New balance of denomination `%s' after deposit is %s\n",
              GNUNET_h2s (&dki->properties.denom_hash),
              TALER_amount2s (&ds->denom_balance));

  /* update global up melt fees */
  {
    struct TALER_Amount dfee;

    TALER_amount_ntoh (&dfee,
                       &dki->properties.fee_deposit);
    if (GNUNET_OK !=
        TALER_amount_add (&total_deposit_fee_income,
                          &total_deposit_fee_income,
                          &dfee))
    {
      GNUNET_break (0);
      cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
      return GNUNET_SYSERR;
    }
  }

  return GNUNET_OK;
}


/**
 * Function called with details about coins that were refunding,
 * with the goal of auditing the refund's execution.  Adds the
 * refunded amount back to the outstanding balance of the respective
 * denomination.
 *
 * @param cls closure
 * @param rowid unique serial ID for the refund in our DB
 * @param denom_pub denomination public key of @a coin_pub
 * @param coin_pub public key of the coin
 * @param merchant_pub public key of the merchant
 * @param merchant_sig signature of the merchant
 * @param h_contract_terms hash of the proposal data known to merchant and customer
 * @param rtransaction_id refund transaction ID chosen by the merchant
 * @param amount_with_fee amount that was deposited including fee
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
refund_cb (void *cls,
           uint64_t rowid,
           const struct TALER_DenominationPublicKey *denom_pub,
           const struct TALER_CoinSpendPublicKeyP *coin_pub,
           const struct TALER_MerchantPublicKeyP *merchant_pub,
           const struct TALER_MerchantSignatureP *merchant_sig,
           const struct GNUNET_HashCode *h_contract_terms,
           uint64_t rtransaction_id,
           const struct TALER_Amount *amount_with_fee)
{
  struct CoinContext *cc = cls;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;
  struct DenominationSummary *ds;
  struct TALER_RefundRequestPS rr;
  struct TALER_Amount amount_without_fee;
  struct TALER_Amount refund_fee;
  enum GNUNET_DB_QueryStatus qs;

  GNUNET_assert (rowid >= ppc.last_refund_serial_id); /* should be monotonically increasing */
  ppc.last_refund_serial_id = rowid + 1;

  qs = get_denomination_info (denom_pub,
                              &dki,
                              NULL);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return GNUNET_SYSERR;
  }

  /* verify refund signature */
  rr.purpose.purpose = htonl (TALER_SIGNATURE_MERCHANT_REFUND);
  rr.purpose.size = htonl (sizeof (rr));
  rr.h_contract_terms = *h_contract_terms;
  rr.coin_pub = *coin_pub;
  rr.merchant = *merchant_pub;
  rr.rtransaction_id = GNUNET_htonll (rtransaction_id);
  TALER_amount_hton (&rr.refund_amount,
                     amount_with_fee);
  rr.refund_fee = dki->properties.fee_refund;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MERCHANT_REFUND,
                                  &rr.purpose,
                                  &merchant_sig->eddsa_sig,
                                  &merchant_pub->eddsa_pub))
  {
    report (report_bad_sig_losses,
            json_pack ("{s:s, s:I, s:o, s:o}",
                       "operation", "refund",
                       "row", (json_int_t) rowid,
                       "loss", TALER_JSON_from_amount (amount_with_fee),
                       "key_pub", GNUNET_JSON_from_data_auto (merchant_pub)));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_sig_loss,
                                    &total_bad_sig_loss,
                                    amount_with_fee));
    return GNUNET_OK;
  }

  TALER_amount_ntoh (&refund_fee,
                     &dki->properties.fee_refund);
  if (GNUNET_OK !=
      TALER_amount_subtract (&amount_without_fee,
                             amount_with_fee,
                             &refund_fee))
  {
    report_amount_arithmetic_inconsistency ("refund (fee)",
                                            rowid,
                                            &amount_without_fee,
                                            &refund_fee,
                                            -1);
    return GNUNET_OK;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Refunding coin %s in denomination `%s' value %s\n",
              TALER_B2S (coin_pub),
              GNUNET_h2s (&dki->properties.denom_hash),
              TALER_amount2s (amount_with_fee));

  /* update coin's denomination balance */
  ds = get_denomination_summary (cc,
                                 dki,
                                 &dki->properties.denom_hash);
  if (NULL == ds)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_amount_add (&ds->denom_balance,
                        &ds->denom_balance,
                        &amount_without_fee))
  {
    GNUNET_break (0);
    cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_amount_add (&ds->denom_risk,
                        &ds->denom_risk,
                        &amount_without_fee))
  {
    GNUNET_break (0);
    cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_amount_add (&total_escrow_balance,
                        &total_escrow_balance,
                        &amount_without_fee))
  {
    GNUNET_break (0);
    cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      TALER_amount_add (&total_risk,
                        &total_risk,
                        &amount_without_fee))
  {
    GNUNET_break (0);
    cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "New balance of denomination `%s' after refund is %s\n",
              GNUNET_h2s (&dki->properties.denom_hash),
              TALER_amount2s (&ds->denom_balance));

  /* update total refund fee balance */
  if (GNUNET_OK !=
      TALER_amount_add (&total_refund_fee_income,
                        &total_refund_fee_income,
                        &refund_fee))
  {
    GNUNET_break (0);
    cc->qs = GNUNET_DB_STATUS_HARD_ERROR;
    return GNUNET_SYSERR;
  }

  return GNUNET_OK;
}


/**
 * Check that the payback operation was properly initiated by a coin
 * and update the denomination's losses accordingly.
 *
 * @param cls a `struct CoinContext *`
 * @param rowid row identifier used to uniquely identify the payback operation
 * @param amount how much should be added back to the reserve
 * @param coin public information about the coin
 * @param denom_pub public key of the denomionation of @a coin
 * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_COIN_PAYBACK
 * @param coin_blind blinding factor used to blind the coin
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
check_payback (struct CoinContext *cc,
               uint64_t rowid,
               const struct TALER_Amount *amount,
               const struct TALER_CoinPublicInfo *coin,
               const struct TALER_DenominationPublicKey *denom_pub,
               const struct TALER_CoinSpendSignatureP *coin_sig,
               const struct TALER_DenominationBlindingKeyP *coin_blind)
{
  struct TALER_PaybackRequestPS pr;
  struct DenominationSummary *ds;
  enum GNUNET_DB_QueryStatus qs;
  const struct TALER_EXCHANGEDB_DenominationKeyInformationP *dki;

  if (GNUNET_OK !=
      TALER_test_coin_valid (coin,
                             denom_pub))
  {
    report (report_bad_sig_losses,
            json_pack ("{s:s, s:I, s:o, s:o}",
                       "operation", "payback",
                       "row", (json_int_t) rowid,
                       "loss", TALER_JSON_from_amount (amount),
                       "key_pub", GNUNET_JSON_from_data_auto (
                         &pr.h_denom_pub)));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_sig_loss,
                                    &total_bad_sig_loss,
                                    amount));
  }
  qs = get_denomination_info (denom_pub,
                              &dki,
                              &pr.h_denom_pub);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT != qs)
  {
    /* The key not existing should be prevented by foreign key constraints,
       so must be a transient DB error. */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    cc->qs = qs;
    return GNUNET_SYSERR;
  }
  pr.purpose.purpose = htonl (TALER_SIGNATURE_WALLET_COIN_PAYBACK);
  pr.purpose.size = htonl (sizeof (pr));
  pr.coin_pub = coin->coin_pub;
  pr.coin_blind = *coin_blind;
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_WALLET_COIN_PAYBACK,
                                  &pr.purpose,
                                  &coin_sig->eddsa_signature,
                                  &coin->coin_pub.eddsa_pub))
  {
    report (report_bad_sig_losses,
            json_pack ("{s:s, s:I, s:o, s:o}",
                       "operation", "payback",
                       "row", (json_int_t) rowid,
                       "loss", TALER_JSON_from_amount (amount),
                       "coin_pub", GNUNET_JSON_from_data_auto (
                         &coin->coin_pub)));
    GNUNET_break (GNUNET_OK ==
                  TALER_amount_add (&total_bad_sig_loss,
                                    &total_bad_sig_loss,
                                    amount));
    return GNUNET_OK;
  }
  ds = get_denomination_summary (cc,
                                 dki,
                                 &dki->properties.denom_hash);
  if (GNUNET_NO == ds->was_revoked)
  {
    /* Woopsie, we allowed payback on non-revoked denomination!? */
    report (report_bad_sig_losses,
            json_pack ("{s:s, s:I, s:o, s:o}",
                       "operation", "payback (denomination not revoked)",
                       "row", (json_int_t) rowid,
                       "loss", TALER_JSON_from_amount (amount),
                       "coin_pub", GNUNET_JSON_from_data_auto (
                         &coin->coin_pub)));
  }
  GNUNET_break (GNUNET_OK ==
                TALER_amount_add (&ds->denom_payback,
                                  &ds->denom_payback,
                                  amount));
  GNUNET_break (GNUNET_OK ==
                TALER_amount_add (&total_payback_loss,
                                  &total_payback_loss,
                                  amount));
  return GNUNET_OK;
}


/**
 * Function called about paybacks the exchange has to perform.
 *
 * @param cls a `struct CoinContext *`
 * @param rowid row identifier used to uniquely identify the payback operation
 * @param timestamp when did we receive the payback request
 * @param amount how much should be added back to the reserve
 * @param reserve_pub public key of the reserve
 * @param coin public information about the coin
 * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_COIN_PAYBACK
 * @param coin_blind blinding factor used to blind the coin
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
payback_cb (void *cls,
            uint64_t rowid,
            struct GNUNET_TIME_Absolute timestamp,
            const struct TALER_Amount *amount,
            const struct TALER_ReservePublicKeyP *reserve_pub,
            const struct TALER_CoinPublicInfo *coin,
            const struct TALER_DenominationPublicKey *denom_pub,
            const struct TALER_CoinSpendSignatureP *coin_sig,
            const struct TALER_DenominationBlindingKeyP *coin_blind)
{
  struct CoinContext *cc = cls;

  return check_payback (cc,
                        rowid,
                        amount,
                        coin,
                        denom_pub,
                        coin_sig,
                        coin_blind);
}


/**
 * Function called about paybacks on refreshed coins the exchange has to
 * perform.
 *
 * @param cls a `struct CoinContext *`
 * @param rowid row identifier used to uniquely identify the payback operation
 * @param timestamp when did we receive the payback request
 * @param amount how much should be added back to the reserve
 * @param old_coin_pub original coin that was refreshed to create @a coin
 * @param coin public information about the coin
 * @param coin_sig signature with @e coin_pub of type #TALER_SIGNATURE_WALLET_COIN_PAYBACK
 * @param coin_blind blinding factor used to blind the coin
 * @return #GNUNET_OK to continue to iterate, #GNUNET_SYSERR to stop
 */
static int
payback_refresh_cb (void *cls,
                    uint64_t rowid,
                    struct GNUNET_TIME_Absolute timestamp,
                    const struct TALER_Amount *amount,
                    const struct TALER_CoinSpendPublicKeyP *old_coin_pub,
                    const struct TALER_CoinPublicInfo *coin,
                    const struct TALER_DenominationPublicKey *denom_pub,
                    const struct TALER_CoinSpendSignatureP *coin_sig,
                    const struct TALER_DenominationBlindingKeyP *coin_blind)
{
  struct CoinContext *cc = cls;

  return check_payback (cc,
                        rowid,
                        amount,
                        coin,
                        denom_pub,
                        coin_sig,
                        coin_blind);
}


/**
 * Analyze the exchange's processing of coins.
 *
 * @param cls closure
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
analyze_coins (void *cls)
{
  struct CoinContext cc;
  enum GNUNET_DB_QueryStatus qs;
  enum GNUNET_DB_QueryStatus qsx;
  enum GNUNET_DB_QueryStatus qsp;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing coins\n");
  qsp = adb->get_auditor_progress_coin (adb->cls,
                                        asession,
                                        &master_pub,
                                        &ppc);
  if (0 > qsp)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsp);
    return qsp;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsp)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                _ (
                  "First analysis using this auditor, starting audit from scratch\n"));
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                _ ("Resuming coin audit at %llu/%llu/%llu/%llu/%llu\n"),
                (unsigned long long) ppc.last_deposit_serial_id,
                (unsigned long long) ppc.last_melt_serial_id,
                (unsigned long long) ppc.last_refund_serial_id,
                (unsigned long long) ppc.last_withdraw_serial_id,
                (unsigned long long) ppc.last_payback_refresh_serial_id);
  }

  /* setup 'cc' */
  cc.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  cc.denom_summaries = GNUNET_CONTAINER_multihashmap_create (256,
                                                             GNUNET_NO);
  qsx = adb->get_balance_summary (adb->cls,
                                  asession,
                                  &master_pub,
                                  &total_escrow_balance,
                                  &total_deposit_fee_income,
                                  &total_melt_fee_income,
                                  &total_refund_fee_income,
                                  &total_risk,
                                  &total_payback_loss);
  if (0 > qsx)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx);
    return qsx;
  }

  /* process withdrawals */
  if (0 >
      (qs = edb->select_reserves_out_above_serial_id (edb->cls,
                                                      esession,
                                                      ppc.
                                                      last_withdraw_serial_id,
                                                      &withdraw_cb,
                                                      &cc)) )
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  /* process refunds */
  if (0 >
      (qs = edb->select_refunds_above_serial_id (edb->cls,
                                                 esession,
                                                 ppc.last_refund_serial_id,
                                                 &refund_cb,
                                                 &cc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  /* process refreshs */
  if (0 >
      (qs = edb->select_refreshs_above_serial_id (edb->cls,
                                                  esession,
                                                  ppc.last_melt_serial_id,
                                                  &refresh_session_cb,
                                                  &cc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  /* process deposits */
  if (0 >
      (qs = edb->select_deposits_above_serial_id (edb->cls,
                                                  esession,
                                                  ppc.last_deposit_serial_id,
                                                  &deposit_cb,
                                                  &cc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  /* process paybacks */
  if (0 >
      (qs = edb->select_payback_above_serial_id (edb->cls,
                                                 esession,
                                                 ppc.last_payback_serial_id,
                                                 &payback_cb,
                                                 &cc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  if (0 >
      (qs = edb->select_payback_refresh_above_serial_id (edb->cls,
                                                         esession,
                                                         ppc.
                                                         last_payback_refresh_serial_id,
                                                         &payback_refresh_cb,
                                                         &cc)))
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  /* sync 'cc' back to disk */
  cc.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  GNUNET_CONTAINER_multihashmap_iterate (cc.denom_summaries,
                                         &sync_denomination,
                                         &cc);
  GNUNET_CONTAINER_multihashmap_destroy (cc.denom_summaries);
  if (0 > cc.qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == cc.qs);
    return cc.qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsx)
    qs = adb->update_balance_summary (adb->cls,
                                      asession,
                                      &master_pub,
                                      &total_escrow_balance,
                                      &total_deposit_fee_income,
                                      &total_melt_fee_income,
                                      &total_refund_fee_income,
                                      &total_risk,
                                      &total_payback_loss);
  else
    qs = adb->insert_balance_summary (adb->cls,
                                      asession,
                                      &master_pub,
                                      &total_escrow_balance,
                                      &total_deposit_fee_income,
                                      &total_melt_fee_income,
                                      &total_refund_fee_income,
                                      &total_risk,
                                      &total_payback_loss);
  if (0 >= qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }

  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsp)
    qs = adb->update_auditor_progress_coin (adb->cls,
                                            asession,
                                            &master_pub,
                                            &ppc);
  else
    qs = adb->insert_auditor_progress_coin (adb->cls,
                                            asession,
                                            &master_pub,
                                            &ppc);
  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              _ ("Concluded coin audit step at %llu/%llu/%llu/%llu/%llu\n"),
              (unsigned long long) ppc.last_deposit_serial_id,
              (unsigned long long) ppc.last_melt_serial_id,
              (unsigned long long) ppc.last_refund_serial_id,
              (unsigned long long) ppc.last_withdraw_serial_id,
              (unsigned long long) ppc.last_payback_refresh_serial_id);
  return qs;
}


/* *************************** Analysis of deposit-confirmations ********** */

/**
 * Closure for #test_dc.
 */
struct DepositConfirmationContext
{

  /**
   * How many deposit confirmations did we NOT find in the #edb?
   */
  unsigned long long missed_count;

  /**
   * What is the total amount missing?
   */
  struct TALER_Amount missed_amount;

  /**
   * Lowest SerialID of the first coin we missed? (This is where we
   * should resume next time).
   */
  uint64_t first_missed_coin_serial;

  /**
   * Lowest SerialID of the first coin we missed? (This is where we
   * should resume next time).
   */
  uint64_t last_seen_coin_serial;

  /**
   * Success or failure of (exchange) database operations within
   * #test_dc.
   */
  enum GNUNET_DB_QueryStatus qs;

};


/**
 * Given a deposit confirmation from #adb, check that it is also
 * in #edb.  Update the deposit confirmation context accordingly.
 *
 * @param cls our `struct DepositConfirmationContext`
 * @param serial_id row of the @a dc in the database
 * @param dc the deposit confirmation we know
 */
static void
test_dc (void *cls,
         uint64_t serial_id,
         const struct TALER_AUDITORDB_DepositConfirmation *dc)
{
  struct DepositConfirmationContext *dcc = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_EXCHANGEDB_Deposit dep;

  dcc->last_seen_coin_serial = serial_id;
  memset (&dep,
          0,
          sizeof (dep));
  dep.coin.coin_pub = dc->coin_pub;
  dep.h_contract_terms = dc->h_contract_terms;
  dep.merchant_pub = dc->merchant;
  dep.h_wire = dc->h_wire;
  dep.refund_deadline = dc->refund_deadline;

  qs = edb->have_deposit (edb->cls,
                          esession,
                          &dep,
                          GNUNET_NO /* do not check refund deadline */);
  if (qs > 0)
    return; /* found, all good */
  if (qs < 0)
  {
    GNUNET_break (0); /* DB error, complain */
    dcc->qs = qs;
    return;
  }
  /* deposit confirmation missing! report! */
  report (report_deposit_confirmation_inconsistencies,
          json_pack ("{s:o, s:o, s:I, s:o}",
                     "timestamp",
                     json_from_time_abs (dc->timestamp),
                     "amount",
                     TALER_JSON_from_amount (&dc->amount_without_fee),
                     "rowid",
                     (json_int_t) serial_id,
                     "account",
                     GNUNET_JSON_from_data_auto (&dc->h_wire)));
  dcc->first_missed_coin_serial = GNUNET_MIN (dcc->first_missed_coin_serial,
                                              serial_id);
  dcc->missed_count++;
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_add (&dcc->missed_amount,
                                   &dcc->missed_amount,
                                   &dc->amount_without_fee));
}


/**
 * Check that the deposit-confirmations that were reported to
 * us by merchants are also in the exchange's database.
 *
 * @param cls closure
 * @return transaction status code
 */
static enum GNUNET_DB_QueryStatus
analyze_deposit_confirmations (void *cls)
{
  struct TALER_AUDITORDB_ProgressPointDepositConfirmation ppdc;
  struct DepositConfirmationContext dcc;
  enum GNUNET_DB_QueryStatus qs;
  enum GNUNET_DB_QueryStatus qsx;
  enum GNUNET_DB_QueryStatus qsp;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Analyzing deposit confirmations\n");
  ppdc.last_deposit_confirmation_serial_id = 0;
  qsp = adb->get_auditor_progress_deposit_confirmation (adb->cls,
                                                        asession,
                                                        &master_pub,
                                                        &ppdc);
  if (0 > qsp)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsp);
    return qsp;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qsp)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_MESSAGE,
                _ (
                  "First analysis using this auditor, starting audit from scratch\n"));
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                _ ("Resuming deposit confirmation audit at %llu\n"),
                (unsigned long long) ppdc.last_deposit_confirmation_serial_id);
  }

  /* setup 'cc' */
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &dcc.missed_amount));
  dcc.qs = GNUNET_DB_STATUS_SUCCESS_ONE_RESULT;
  dcc.missed_count = 0LLU;
  dcc.first_missed_coin_serial = UINT64_MAX;
  qsx = adb->get_deposit_confirmations (adb->cls,
                                        asession,
                                        &master_pub,
                                        ppdc.last_deposit_confirmation_serial_id,
                                        &test_dc,
                                        &dcc);
  if (0 > qsx)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qsx);
    return qsx;
  }
  if (0 > dcc.qs)
  {
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == dcc.qs);
    return dcc.qs;
  }
  if (UINT64_MAX == dcc.first_missed_coin_serial)
    ppdc.last_deposit_confirmation_serial_id = dcc.last_seen_coin_serial;
  else
    ppdc.last_deposit_confirmation_serial_id = dcc.first_missed_coin_serial - 1;

  /* sync 'cc' back to disk */
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qsp)
    qs = adb->update_auditor_progress_deposit_confirmation (adb->cls,
                                                            asession,
                                                            &master_pub,
                                                            &ppdc);
  else
    qs = adb->insert_auditor_progress_deposit_confirmation (adb->cls,
                                                            asession,
                                                            &master_pub,
                                                            &ppdc);
  if (0 >= qs)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Failed to update auditor DB, not recording progress\n");
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
    return qs;
  }
  number_missed_deposit_confirmations = (json_int_t) dcc.missed_count;
  total_missed_deposit_confirmations = dcc.missed_amount;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              _ ("Concluded deposit confirmation audit step at %llu\n"),
              (unsigned long long) ppdc.last_deposit_confirmation_serial_id);
  return qs;
}



/* *************************** General transaction logic ****************** */

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
static int
transact (Analysis analysis,
          void *analysis_cls)
{
  int ret;
  enum GNUNET_DB_QueryStatus qs;

  ret = adb->start (adb->cls,
                    asession);
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  edb->preflight (edb->cls,
                  esession);
  ret = edb->start (edb->cls,
                    esession,
                    "auditor");
  if (GNUNET_OK != ret)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  qs = analysis (analysis_cls);
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
  {
    qs = edb->commit (edb->cls,
                      esession);
    if (0 > qs)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Exchange DB commit failed, rolling back transaction\n");
      adb->rollback (adb->cls,
                     asession);
    }
    else
    {
      qs = adb->commit (adb->cls,
                        asession);
      if (0 > qs)
      {
        GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Auditor DB commit failed!\n");
      }
    }
  }
  else
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Processing failed, rolling back transaction\n");
    adb->rollback (adb->cls,
                   asession);
    edb->rollback (edb->cls,
                   esession);
  }
  clear_transaction_state_cache ();
  return qs;
}


/**
 * Initialize DB sessions and run the analysis.
 */
static void
setup_sessions_and_run ()
{
  esession = edb->get_session (edb->cls);
  if (NULL == esession)
  {
    fprintf (stderr,
             "Failed to initialize exchange session.\n");
    global_ret = 1;
    return;
  }
  asession = adb->get_session (adb->cls);
  if (NULL == asession)
  {
    fprintf (stderr,
             "Failed to initialize auditor session.\n");
    global_ret = 1;
    return;
  }

  transact (&analyze_reserves,
            NULL);
  transact (&analyze_aggregations,
            NULL);
  transact (&analyze_coins,
            NULL);
  transact (&analyze_deposit_confirmations,
            NULL);
}


/**
 * Test if the given @a mpub matches the #master_pub.
 * If so, set "found" to GNUNET_YES.
 *
 * @param cls a `int *` pointing to "found"
 * @param mpub exchange master public key to compare
 * @param exchange_url URL of the exchange (ignored)
 */
static void
test_master_present (void *cls,
                     const struct TALER_MasterPublicKeyP *mpub,
                     const char *exchange_url)
{
  int *found = cls;

  (void) exchange_url;
  if (0 == GNUNET_memcmp (mpub,
                          &master_pub))
    *found = GNUNET_YES;
}


/**
 * Main function that will be run.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param c configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *c)
{
  static const struct TALER_MasterPublicKeyP zeromp;
  struct TALER_Amount income_fee_total;
  json_t *report;
  struct TALER_AUDITORDB_Session *as;
  int found;

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Launching auditor\n");
  cfg = c;
  if (0 == GNUNET_memcmp (&zeromp,
                          &master_pub))
  {
    /* -m option not given, try configuration */
    char *master_public_key_str;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchange",
                                               "MASTER_PUBLIC_KEY",
                                               &master_public_key_str))
    {
      fprintf (stderr,
               "Pass option -m or set it in the configuration!\n");
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange",
                                 "MASTER_PUBLIC_KEY");
      global_ret = 1;
      return;
    }
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_public_key_from_string (master_public_key_str,
                                                    strlen (
                                                      master_public_key_str),
                                                    &master_pub.eddsa_pub))
    {
      fprintf (stderr,
               "Invalid master public key given in configuration file.");
      GNUNET_free (master_public_key_str);
      global_ret = 1;
      return;
    }
    GNUNET_free (master_public_key_str);
  } /* end of -m not given */

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (cfg,
                                             "taler",
                                             "CURRENCY",
                                             &currency))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "taler",
                               "CURRENCY");
    global_ret = 1;
    return;
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_time (cfg,
                                           "exchangedb",
                                           "IDLE_RESERVE_EXPIRATION_TIME",
                                           &idle_reserve_expiration_time))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchangedb",
                               "IDLE_RESERVE_EXPIRATION_TIME");
    global_ret = 1;
    return;
  }
  if (NULL ==
      (edb = TALER_EXCHANGEDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize exchange database plugin.\n");
    global_ret = 1;
    return;
  }
  if (NULL ==
      (adb = TALER_AUDITORDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize auditor database plugin.\n");
    global_ret = 1;
    TALER_EXCHANGEDB_plugin_unload (edb);
    return;
  }
  found = GNUNET_NO;
  as = adb->get_session (adb->cls);
  if (NULL == as)
  {
    fprintf (stderr,
             "Failed to start session with auditor database.\n");
    global_ret = 1;
    TALER_AUDITORDB_plugin_unload (adb);
    TALER_EXCHANGEDB_plugin_unload (edb);
    return;
  }
  (void) adb->list_exchanges (adb->cls,
                              as,
                              &test_master_present,
                              &found);
  if (GNUNET_NO == found)
  {
    fprintf (stderr,
             "Exchange's master public key `%s' not known to auditor DB. Did you forget to run `taler-auditor-exchange`?\n",
             GNUNET_p2s (&master_pub.eddsa_pub));
    global_ret = 1;
    TALER_AUDITORDB_plugin_unload (adb);
    TALER_EXCHANGEDB_plugin_unload (edb);
    return;
  }
  if (restart)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Full audit restart requested, dropping old audit data.\n");
    GNUNET_break (GNUNET_OK ==
                  adb->drop_tables (adb->cls,
                                    GNUNET_NO));
    TALER_AUDITORDB_plugin_unload (adb);
    if (NULL ==
        (adb = TALER_AUDITORDB_plugin_load (cfg)))
    {
      fprintf (stderr,
               "Failed to initialize auditor database plugin after drop.\n");
      global_ret = 1;
      TALER_EXCHANGEDB_plugin_unload (edb);
      return;
    }
    GNUNET_break (GNUNET_OK ==
                  adb->create_tables (adb->cls));
  }

  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Starting audit\n");
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &reported_emergency_sum));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_escrow_balance));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_risk));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_payback_loss));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_withdraw_fee_income));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_deposit_fee_income));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_melt_fee_income));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_refund_fee_income));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_aggregation_fee_income));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_balance_insufficient_loss));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_balance_summary_delta_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_balance_summary_delta_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_wire_out_delta_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_wire_out_delta_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_arithmetic_delta_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_arithmetic_delta_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_coin_delta_plus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_coin_delta_minus));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_balance_reserve_not_closed));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_bad_sig_loss));
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_get_zero (currency,
                                        &total_refresh_hanging));
  GNUNET_assert (NULL !=
                 (report_emergencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_emergencies_by_count = json_array ()));
  GNUNET_assert (NULL !=
                 (report_row_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (denomination_key_validity_withdraw_inconsistencies =
                    json_array ()));
  GNUNET_assert (NULL !=
                 (report_reserve_balance_summary_wrong_inconsistencies =
                    json_array ()));
  GNUNET_assert (NULL !=
                 (report_reserve_balance_insufficient_inconsistencies =
                    json_array ()));
  GNUNET_assert (NULL !=
                 (report_reserve_not_closed_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_wire_out_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_deposit_confirmation_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_coin_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_aggregation_fee_balances = json_array ()));
  GNUNET_assert (NULL !=
                 (report_amount_arithmetic_inconsistencies = json_array ()));
  GNUNET_assert (NULL !=
                 (report_bad_sig_losses = json_array ()));
  GNUNET_assert (NULL !=
                 (report_refreshs_hanging = json_array ()));
  GNUNET_assert (NULL !=
                 (report_fee_time_inconsistencies = json_array ()));
  setup_sessions_and_run ();
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Audit complete\n");
  TALER_AUDITORDB_plugin_unload (adb);
  TALER_EXCHANGEDB_plugin_unload (edb);

  GNUNET_assert (TALER_amount_add (&income_fee_total,
                                   &total_withdraw_fee_income,
                                   &total_deposit_fee_income));
  GNUNET_assert (TALER_amount_add (&income_fee_total,
                                   &income_fee_total,
                                   &total_melt_fee_income));
  GNUNET_assert (TALER_amount_add (&income_fee_total,
                                   &income_fee_total,
                                   &total_refund_fee_income));
  GNUNET_assert (TALER_amount_add (&income_fee_total,
                                   &income_fee_total,
                                   &total_aggregation_fee_income));
  report = json_pack ("{s:o, s:o, s:o, s:o, s:o,"
                      " s:o, s:o, s:o, s:o, s:o,"
                      " s:o, s:o, s:o, s:o, s:o,"
                      " s:o, s:o, s:o, s:o, s:o,"
                      " s:o, s:o, s:o, s:o, s:o,"
                      " s:o, s:o, s:o, s:o, s:o,"
                      " s:o, s:o, s:o, s:o, s:I,"
                      " s:o, s:o, s:o }",
                      /* blocks of 5 for easier counting/matching to format string */
                      /* block */
                      "reserve_balance_insufficient_inconsistencies",
                      report_reserve_balance_insufficient_inconsistencies,
                      /* Tested in test-auditor.sh #3 */
                      "total_loss_balance_insufficient",
                      TALER_JSON_from_amount (&total_balance_insufficient_loss),
                      /* Tested in test-auditor.sh #3 */
                      "reserve_balance_summary_wrong_inconsistencies",
                      report_reserve_balance_summary_wrong_inconsistencies,
                      "total_balance_summary_delta_plus",
                      TALER_JSON_from_amount (
                        &total_balance_summary_delta_plus),
                      "total_balance_summary_delta_minus",
                      TALER_JSON_from_amount (
                        &total_balance_summary_delta_minus),
                      /* block */
                      "total_escrow_balance",
                      TALER_JSON_from_amount (&total_escrow_balance),
                      "total_active_risk",
                      TALER_JSON_from_amount (&total_risk),
                      "total_withdraw_fee_income",
                      TALER_JSON_from_amount (&total_withdraw_fee_income),
                      "total_deposit_fee_income",
                      TALER_JSON_from_amount (&total_deposit_fee_income),
                      "total_melt_fee_income",
                      TALER_JSON_from_amount (&total_melt_fee_income),
                      /* block */
                      "total_refund_fee_income",
                      TALER_JSON_from_amount (&total_refund_fee_income),
                      "income_fee_total",
                      TALER_JSON_from_amount (&income_fee_total),
                      "emergencies",
                      report_emergencies,
                      "emergencies_risk_total",
                      TALER_JSON_from_amount (&reported_emergency_sum),
                      "reserve_not_closed_inconsistencies",
                      report_reserve_not_closed_inconsistencies,
                      /* block */
                      "total_balance_reserve_not_closed",
                      TALER_JSON_from_amount (
                        &total_balance_reserve_not_closed),
                      "wire_out_inconsistencies",
                      report_wire_out_inconsistencies,
                      "total_wire_out_delta_plus",
                      TALER_JSON_from_amount (&total_wire_out_delta_plus),
                      "total_wire_out_delta_minus",
                      TALER_JSON_from_amount (&total_wire_out_delta_minus),
                      /* Tested in test-auditor.sh #4/#5/#6/#7 */
                      "bad_sig_losses",
                      report_bad_sig_losses,
                      /* block */
                      /* Tested in test-auditor.sh #4/#5/#6/#7 */
                      "total_bad_sig_loss",
                      TALER_JSON_from_amount (&total_bad_sig_loss),
                      "row_inconsistencies",
                      report_row_inconsistencies,
                      "denomination_key_validity_withdraw_inconsistencies",
                      denomination_key_validity_withdraw_inconsistencies,
                      "coin_inconsistencies",
                      report_coin_inconsistencies,
                      "total_coin_delta_plus",
                      TALER_JSON_from_amount (&total_coin_delta_plus),
                      /* block */
                      "total_coin_delta_minus",
                      TALER_JSON_from_amount (&total_coin_delta_minus),
                      "amount_arithmetic_inconsistencies",
                      report_amount_arithmetic_inconsistencies,
                      "total_arithmetic_delta_plus",
                      TALER_JSON_from_amount (&total_arithmetic_delta_plus),
                      "total_arithmetic_delta_minus",
                      TALER_JSON_from_amount (&total_arithmetic_delta_minus),
                      "total_aggregation_fee_income",
                      TALER_JSON_from_amount (&total_aggregation_fee_income),
                      /* block */
                      "wire_fee_time_inconsistencies",
                      report_fee_time_inconsistencies,
                      "total_refresh_hanging",
                      TALER_JSON_from_amount (&total_refresh_hanging),
                      "refresh_hanging",
                      report_refreshs_hanging,
                      "deposit_confirmation_inconsistencies",
                      report_deposit_confirmation_inconsistencies,
                      "missing_deposit_confirmation_count",
                      (json_int_t) number_missed_deposit_confirmations,
                      /* block */
                      "missing_deposit_confirmation_total",
                      TALER_JSON_from_amount (
                        &total_missed_deposit_confirmations),
                      "total_payback_loss",
                      TALER_JSON_from_amount (&total_payback_loss),
                      "emergencies_by_count",
                      report_emergencies_by_count
                      );
  GNUNET_break (NULL != report);
  json_dumpf (report,
              stdout,
              JSON_INDENT (2));
  json_decref (report);
}


/**
 * The main function of the database initialization tool.
 * Used to initialize the Taler Exchange's database.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_base32_auto ('m',
                                      "exchange-key",
                                      "KEY",
                                      "public key of the exchange (Crockford base32 encoded)",
                                      &master_pub),
    GNUNET_GETOPT_option_flag ('r',
                               "restart",
                               "restart audit from the beginning (required on first run)",
                               &restart),
    GNUNET_GETOPT_OPTION_END
  };

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-auditor",
                                   "MESSAGE",
                                   NULL));
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc,
                          argv,
                          "taler-auditor",
                          "Audit Taler exchange database",
                          options,
                          &run,
                          NULL))
    return 1;
  return global_ret;
}


/* end of taler-auditor.c */
