--
-- This file is part of TALER
-- Copyright (C) 2014--2021 Taler Systems SA
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

BEGIN;

-- Unregister patch (exchange-0001.sql)
SELECT _v.unregister_patch('exchange-0001');


-- Drops for exchange-0001-part.sql
DROP TRIGGER IF EXISTS reserves_out_on_insert ON reserves_out;
DROP TRIGGER IF EXISTS reserves_out_on_delete ON reserves_out;
DROP TRIGGER IF EXISTS deposits_on_insert ON deposits;
DROP TRIGGER IF EXISTS deposits_on_delete ON deposits;
DROP TRIGGER IF EXISTS recoup_on_insert ON recoup;
DROP TRIGGER IF EXISTS recoup_on_delete ON recoup;

DROP TABLE IF EXISTS revolving_work_shards CASCADE;
DROP TABLE IF EXISTS extensions CASCADE;
DROP TABLE IF EXISTS auditors CASCADE;
DROP TABLE IF EXISTS auditor_denom_sigs CASCADE;
DROP TABLE IF EXISTS exchange_sign_keys CASCADE;
DROP TABLE IF EXISTS wire_accounts CASCADE;
DROP TABLE IF EXISTS signkey_revocations CASCADE;
DROP TABLE IF EXISTS work_shards CASCADE;
DROP TABLE IF EXISTS prewire CASCADE;
DROP TABLE IF EXISTS recoup CASCADE;
DROP TABLE IF EXISTS recoup_refresh CASCADE;
DROP TABLE IF EXISTS aggregation_transient CASCADE;
DROP TABLE IF EXISTS aggregation_tracking CASCADE;
DROP TABLE IF EXISTS wire_out CASCADE;
DROP TABLE IF EXISTS wire_targets CASCADE;
DROP TABLE IF EXISTS wire_fee CASCADE;
DROP TABLE IF EXISTS deposits CASCADE;
DROP TABLE IF EXISTS deposits_by_ready CASCADE;
DROP TABLE IF EXISTS deposits_for_matching CASCADE;
DROP TABLE IF EXISTS extension_details CASCADE;
DROP TABLE IF EXISTS refunds CASCADE;
DROP TABLE IF EXISTS refresh_commitments CASCADE;
DROP TABLE IF EXISTS refresh_revealed_coins CASCADE;
DROP TABLE IF EXISTS refresh_transfer_keys CASCADE;
DROP TABLE IF EXISTS known_coins CASCADE;
DROP TABLE IF EXISTS reserves_close CASCADE;
DROP TABLE IF EXISTS reserves_out CASCADE;
DROP TABLE IF EXISTS reserves_out_by_reserve CASCADE;
DROP TABLE IF EXISTS reserves_in CASCADE;
DROP TABLE IF EXISTS reserves CASCADE;
DROP TABLE IF EXISTS denomination_revocations CASCADE;
DROP TABLE IF EXISTS denominations CASCADE;
DROP TABLE IF EXISTS cs_nonce_locks CASCADE;
DROP TABLE IF EXISTS global_fee CASCADE;
DROP TABLE IF EXISTS recoup_by_reserve CASCADE;


DROP TABLE IF EXISTS partners CASCADE;
DROP TABLE IF EXISTS account_merges CASCADE;
DROP TABLE IF EXISTS purse_merges CASCADE;
DROP TABLE IF EXISTS purse_deposits CASCADE;
DROP TABLE IF EXISTS contracts CASCADE;
DROP TABLE IF EXISTS history_requests CASCADE;
DROP TABLE IF EXISTS close_requests CASCADE;
DROP TABLE IF EXISTS purse_requests CASCADE;
DROP TABLE IF EXISTS wads_out CASCADE;
DROP TABLE IF EXISTS wad_out_entries CASCADE;
DROP TABLE IF EXISTS wads_in CASCADE;
DROP TABLE IF EXISTS wad_in_entries CASCADE;
DROP TABLE IF EXISTS partner_accounts CASCADE;
DROP TABLE IF EXISTS purse_actions CASCADE;

DROP FUNCTION IF EXISTS exchange_do_withdraw;
DROP FUNCTION IF EXISTS exchange_do_withdraw_limit_check;
DROP FUNCTION IF EXISTS exchange_do_recoup_by_reserve;
DROP FUNCTION IF EXISTS recoup_insert_trigger;
DROP FUNCTION IF EXISTS recoup_delete_trigger;
DROP FUNCTION IF EXISTS deposits_insert_trigger;
DROP FUNCTION IF EXISTS deposits_update_trigger;
DROP FUNCTION IF EXISTS deposits_delete_trigger;
DROP FUNCTION IF EXISTS reserves_out_by_reserve_insert_trigger;
DROP FUNCTION IF EXISTS reserves_out_by_reserve_delete_trigger;
DROP FUNCTION IF EXISTS exchange_do_deposit;
DROP FUNCTION IF EXISTS exchange_do_melt;
DROP FUNCTION IF EXISTS exchange_do_refund;
DROP FUNCTION IF EXISTS exchange_do_recoup_to_coin;
DROP FUNCTION IF EXISTS exchange_do_recoup_to_reserve;
DROP FUNCTION IF EXISTS exchange_do_purse_deposit;
DROP FUNCTION IF EXISTS exchange_do_purse_merge;
DROP FUNCTION IF EXISTS exchange_do_account_merge;
DROP FUNCTION IF EXISTS exchange_do_history_request;
DROP FUNCTION IF EXISTS exchange_do_close_request;
DROP FUNCTION IF EXISTS exchange_do_reserve_purse;

-- And we're out of here...

COMMIT;
