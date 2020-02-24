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

-- This script DROPs all of the tables we create, including the
-- versioning schema!
--
-- Unlike the other SQL files, it SHOULD be updated to reflect the
-- latest requirements for dropping tables.

-- Drops for 0001.sql
DROP TABLE IF EXISTS auditor_predicted_result;
DROP TABLE IF EXISTS auditor_historic_denomination_revenue;
DROP TABLE IF EXISTS auditor_balance_summary;
DROP TABLE IF EXISTS auditor_denomination_pending;
DROP TABLE IF EXISTS auditor_reserve_balance;
DROP TABLE IF EXISTS auditor_wire_fee_balance;
DROP TABLE IF EXISTS auditor_reserves;
DROP TABLE IF EXISTS auditor_progress_reserve;
DROP TABLE IF EXISTS auditor_progress_aggregation;
DROP TABLE IF EXISTS auditor_progress_deposit_confirmation;
DROP TABLE IF EXISTS auditor_progress_coin;
DROP TABLE IF EXISTS auditor_exchange_signkeys;
DROP TABLE IF EXISTS wire_auditor_progress;
DROP TABLE IF EXISTS wire_auditor_account_progress;
DROP TABLE IF EXISTS auditor_historic_reserve_summary CASCADE;
DROP TABLE IF EXISTS auditor_denominations CASCADE;
DROP TABLE IF EXISTS deposit_confirmations CASCADE;
DROP TABLE IF EXISTS auditor_exchanges CASCADE;

-- Drop versioning (0000.sql)
DROP SCHEMA IF EXISTS _v CASCADE;

-- And we're out of here...
COMMIT;
