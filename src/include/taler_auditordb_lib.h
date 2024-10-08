/*
  This file is part of TALER
  Copyright (C) 2016 Taler Systems SA

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
 * @file include/taler_auditordb_lib.h
 * @brief high-level interface for the auditor's database
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#ifndef TALER_AUDITORDB_LIB_H
#define TALER_AUDITORDB_LIB_H


enum TALER_AUDITORDB_DeletableSuppressableTables
{
  /**
   * For auditor_amount_arithmetic_inconsistency table.
   */
  TALER_AUDITORDB_AMOUNT_ARITHMETIC_INCONSISTENCY,

  /**
   * For auditor_closure_lags table.
   */
  TALER_AUDITORDB_CLOSURE_LAGS,

  /**
   * For auditor_progress table.
   */
  TALER_AUDITORDB_PROGRESS,

  /**
   * For auditor_bad_sig_losses table.
   */
  TALER_AUDITORDB_BAD_SIG_LOSSES,

  /**
   * For auditor_coin_inconsistency table.
   */
  TALER_AUDITORDB_COIN_INCONSISTENCY,

  /**
   * For auditor_denomination_key_validity_withdraw_inconsistency table.
   */
  TALER_AUDITORDB_DENOMINATION_KEY_VALIDITY_WITHDRAW_INCONSISTENCY,

  /**
   * For auditor_denomination_pending table.
   */
  TALER_AUDITORDB_DENOMINATION_PENDING,

  /**
   * For auditor_denominations_without_sig table.
   */
  TALER_AUDITORDB_DENOMINATIONS_WITHOUT_SIG,

  /**
   * For auditor_deposit_confirmation table.
   */
  TALER_AUDITORDB_DEPOSIT_CONFIRMATION,

  /**
   * For auditor_emergency table.
   */
  TALER_AUDITORDB_EMERGENCY,

  /**
   * For auditor_emergency_by_count table.
   */
  TALER_AUDITORDB_EMERGENCY_BY_COUNT,

  /**
   * For auditor_fee_time_inconsistency table.
   */
  TALER_AUDITORDB_FEE_TIME_INCONSISTENCY,

  /**
   * For auditor_misattribution_in_inconsistency table.
   */
  TALER_AUDITORDB_MISATTRIBUTION_IN_INCONSISTENCY,

  /**
   * For auditor_purse_not_closed_inconsistency table.
   */
  TALER_AUDITORDB_PURSE_NOT_CLOSED_INCONSISTENCY,

  /**
   * For auditor_refreshes_hanging table.
   */
  TALER_AUDITORDB_REFRESHES_HANGING,

  /**
   * For auditor_reserve_balance_insufficient_inconsistency table.
   */
  TALER_AUDITORDB_RESERVE_BALANCE_INSUFFICIENT_INCONSISTENCY,

  /**
   * For auditor_reserve_balance_summary_wrong_inconsistency table.
   */
  TALER_AUDITORDB_RESERVE_BALANCE_SUMMARY_WRONG_INCONSISTENCY,

  /**
   * For auditor_reserve_in_inconsistency table.
   */
  TALER_AUDITORDB_RESERVE_IN_INCONSISTENCY,

  /**
   * For auditor_reserve_not_closed_inconsistency table.
   */
  TALER_AUDITORDB_RESERVE_NOT_CLOSED_INCONSISTENCY,

  /**
   * For auditor_row_inconsistency table.
   */
  TALER_AUDITORDB_ROW_INCONSISTENCY,

  /**
   * For auditor_row_minor_inconsistency table.
   */
  TALER_AUDITORDB_ROW_MINOR_INCONSISTENCY,

  /**
   * For auditor_wire_format_inconsistency table.
   */
  TALER_AUDITORDB_WIRE_FORMAT_INCONSISTENCY,

  /**
   * For auditor_wire_out_inconsistency table.
   */
  TALER_AUDITORDB_WIRE_OUT_INCONSISTENCY,

  /**
   * Terminal.
   */
  TALER_AUDITORDB_DELETABLESUPPRESSABLE_TABLES_MAX
};

/**
 * Initialize the plugin.
 *
 * @param cfg configuration to use
 * @return NULL on failure
 */
struct TALER_AUDITORDB_Plugin *
TALER_AUDITORDB_plugin_load (const struct GNUNET_CONFIGURATION_Handle *cfg);


/**
 * Shutdown the plugin.
 *
 * @param plugin plugin to unload
 */
void
TALER_AUDITORDB_plugin_unload (struct TALER_AUDITORDB_Plugin *plugin);


#endif
