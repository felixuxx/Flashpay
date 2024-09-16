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
  TALER_AUDITORDB_CLOSURE_LAGS,
  TALER_AUDITORDB_PROGRESS,
  TALER_AUDITORDB_BAD_SIG_LOSSES,
  TALER_AUDITORDB_COIN_INCONSISTENCY,
  TALER_AUDITORDB_DENOMINATION_KEY_VALIDITY_WITHDRAW_INCONSISTENCY,
  TALER_AUDITORDB_DENOMINATION_PENDING,
  TALER_AUDITORDB_DENOMINATIONS_WITHOUT_SIG,
  TALER_AUDITORDB_DEPOSIT_CONFIRMATION,
  TALER_AUDITORDB_EMERGENCY,
  TALER_AUDITORDB_EMERGENCY_BY_COUNT,
  TALER_AUDITORDB_FEE_TIME_INCONSISTENCY,
  TALER_AUDITORDB_MISATTRIBUTION_IN_INCONSISTENCY,
  TALER_AUDITORDB_PURSE_NOT_CLOSED_INCONSISTENCY,
  TALER_AUDITORDB_REFRESHES_HANGING,
  TALER_AUDITORDB_RESERVE_BALANCE_INSUFFICIENT_INCONSISTENCY,
  TALER_AUDITORDB_RESERVE_BALANCE_SUMMARY_WRONG_INCONSISTENCY,
  TALER_AUDITORDB_RESERVE_IN_INCONSISTENCY,
  TALER_AUDITORDB_RESERVE_NOT_CLOSED_INCONSISTENCY,
  TALER_AUDITORDB_ROW_INCONSISTENCY,
  TALER_AUDITORDB_ROW_MINOR_INCONSISTENCY,
  TALER_AUDITORDB_WIRE_FORMAT_INCONSISTENCY,
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
