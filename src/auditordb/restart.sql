--
-- This file is part of TALER
-- Copyright (C) 2014--2020 Taler Systems SA
--
-- TALER is free software; you can redistribute it and/or modify it under the
-- terms of the GNU General Public License as published by the Free Software
-- Foundation; either version 3, or (at your option) any later version.
--
-- TALER is distributed in the hope that it will be useful, but WITHOUT ANY
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
-- A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along with
-- TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
--

-- Everything in one big transaction
BEGIN;

SET search_path TO auditor;

-- This script restart the auditor state as done to RESTART
-- an audit from scratch. It does NOT drop tables and also
-- PRESERVES data that running the auditor would not recover,
-- such as:
-- * the list of audited exchanges
-- * deposit confirmation reports the auditor received from merchants
-- * schema versioning information
-- * signing keys of exchanges we have downloaded
--
-- Unlike the other SQL files, it SHOULD be updated to reflect the
-- latest requirements for dropping tables.

DELETE FROM auditor_amount_arithmetic_inconsistency;
DELETE FROM auditor_bad_sig_losses;
DELETE FROM auditor_balances;
DELETE FROM auditor_closure_lags;
DELETE FROM auditor_coin_inconsistency;
DELETE FROM auditor_denomination_key_validity_withdraw_inconsistency;
DELETE FROM auditor_denomination_pending;
DELETE FROM auditor_denominations_without_sigs;
DELETE FROM auditor_emergency;
DELETE FROM auditor_emergency_by_count;
DELETE FROM auditor_fee_time_inconsistency;
DELETE FROM auditor_historic_denomination_revenue;
DELETE FROM auditor_historic_reserve_summary;
DELETE FROM auditor_misattribution_in_inconsistency;
DELETE FROM auditor_pending_deposits;
DELETE FROM auditor_progress;
DELETE FROM auditor_purse_not_closed_inconsistencies;
DELETE FROM auditor_purses;
DELETE FROM auditor_refreshes_hanging;
DELETE FROM auditor_reserve_balance_insufficient_inconsistency;
DELETE FROM auditor_reserve_balance_summary_wrong_inconsistency;
DELETE FROM auditor_reserve_in_inconsistency;
DELETE FROM auditor_reserve_not_closed_inconsistency;
DELETE FROM auditor_reserves;
DELETE FROM auditor_row_inconsistency;
DELETE FROM auditor_row_minor_inconsistencies;
DELETE FROM auditor_wire_format_inconsistency;
DELETE FROM auditor_wire_out_inconsistency;


-- And we're out of here...
COMMIT;
