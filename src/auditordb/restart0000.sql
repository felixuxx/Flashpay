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

-- This script restart the auditor state as done to RESTART
-- an audit from scratch. It does NOT drop tables and also
-- PRESERVES data that running the auditor would not recover,
-- such as:
-- * the list of audited exchanges
-- * deposit confirmation reports the auditor received from merchants
-- * schema versioning information
--
-- Unlike the other SQL files, it SHOULD be updated to reflect the
-- latest requirements for dropping tables.

DELETE FROM auditor_predicted_result;
DELETE FROM auditor_historic_denomination_revenue;
DELETE FROM auditor_balance_summary;
DELETE FROM auditor_denomination_pending;
DELETE FROM auditor_reserve_balance;
DELETE FROM auditor_wire_fee_balance;
DELETE FROM auditor_reserves;
DELETE FROM auditor_progress_reserve;
DELETE FROM auditor_progress_aggregation;
DELETE FROM auditor_progress_deposit_confirmation;
DELETE FROM auditor_progress_coin;
DELETE FROM wire_auditor_progress;
DELETE FROM wire_auditor_account_progress;
DELETE FROM auditor_historic_reserve_summary;

-- And we're out of here...
COMMIT;
