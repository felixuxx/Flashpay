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

-- Everything in one big transaction
BEGIN;

-- This script DROPs all of the tables we create.
--
-- Unlike the other SQL files, it SHOULD be updated to reflect the
-- latest requirements for dropping tables.


-- Unregister patch (exchange-0001.sql)
SELECT _v.unregister_patch('exchange-0001');

-- Drops for exchange-0001.sql
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
DROP FUNCTION IF EXISTS add_constraints_to_recoup_partition;
DROP TABLE IF EXISTS recoup_refresh CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_recoup_refresh_partition;
DROP TABLE IF EXISTS aggregation_tracking CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_aggregation_tracking_partition;
DROP TABLE IF EXISTS wire_out CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_wire_out_partition;
DROP TABLE IF EXISTS wire_targets CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_wire_targets_partition;
DROP TABLE IF EXISTS wire_fee CASCADE;
DROP TABLE IF EXISTS deposits CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_deposits_partition;
DROP TABLE IF EXISTS extension_details CASCADE;
DROP TABLE IF EXISTS refunds CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_refunds_partition;
DROP TABLE IF EXISTS refresh_commitments CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_refresh_commitments_partition;
DROP TABLE IF EXISTS refresh_revealed_coins CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_refresh_revealed_coins_partition;
DROP TABLE IF EXISTS refresh_transfer_keys CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_refresh_transfer_keys_partition;
DROP TABLE IF EXISTS known_coins CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_known_coins_partition;
DROP TABLE IF EXISTS reserves_close CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_reserves_close_partition;
DROP TABLE IF EXISTS reserves_out CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_reserves_out_partition;
DROP TABLE IF EXISTS reserves_in CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_reserves_in_partition;
DROP TABLE IF EXISTS reserves CASCADE;
DROP TABLE IF EXISTS denomination_revocations CASCADE;
DROP TABLE IF EXISTS denominations CASCADE;
DROP TABLE IF EXISTS cs_nonce_locks CASCADE;
DROP FUNCTION IF EXISTS add_constraints_to_cs_nonce_locks_partition;

DROP FUNCTION IF EXISTS exchange_do_withdraw(bigint,int,bytea,bytea,bytea,bytea,bytea,bigint,bigint) ;

DROP FUNCTION IF EXISTS exchange_do_withdraw_limit_check(bytea,bigint,bigint,int) ;

DROP FUNCTION IF EXISTS exchange_do_deposit;

DROP FUNCTION IF EXISTS exchange_do_melt;

DROP FUNCTION IF EXISTS exchange_do_refund;

DROP FUNCTION IF EXISTS exchange_do_recoup_to_coin;

DROP FUNCTION IF EXISTS exchange_do_recoup_to_reserve;

-- FIXME: drop other stored functions!

-- Unregister patch (partition-0001.sql)
-- SELECT _v.unregister_patch('partition-0001');

-- Drops for partition-0001.sql
DROP FUNCTION IF EXISTS create_table_partition;

DROP FUNCTION IF EXISTS create_partitions;

DROP FUNCTION IF EXISTS detach_default_partitions;

DROP FUNCTION IF EXISTS drop_default_partitions;


-- And we're out of here...

COMMIT;
