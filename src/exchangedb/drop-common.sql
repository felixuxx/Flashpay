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

-- This script DROPs all of the common functions we create.
--
-- Unlike the other SQL files, it SHOULD be updated to reflect the
-- latest requirements for dropping tables.


DROP FUNCTION IF EXISTS create_table_prewire;
DROP FUNCTION IF EXISTS create_table_recoup;
DROP FUNCTION IF EXISTS add_constraints_to_recoup_partition;
DROP FUNCTION IF EXISTS create_table_recoup_by_reserve;
DROP FUNCTION IF EXISTS create_table_recoup_refresh;
DROP FUNCTION IF EXISTS add_constraints_to_recoup_refresh_partition;
DROP FUNCTION IF EXISTS create_table_aggregation_transient;
DROP FUNCTION IF EXISTS create_table_aggregation_tracking;
DROP FUNCTION IF EXISTS add_constraints_to_aggregation_tracking_partition;
DROP FUNCTION IF EXISTS create_table_wire_out;
DROP FUNCTION IF EXISTS add_constraints_to_wire_out_partition;
DROP FUNCTION IF EXISTS create_table_wire_targets;
DROP FUNCTION IF EXISTS add_constraints_to_wire_targets_partition;
DROP FUNCTION IF EXISTS create_table_deposits;
DROP FUNCTION IF EXISTS create_table_deposits_by_ready;
DROP FUNCTION IF EXISTS create_table_deposits_for_matching;
DROP FUNCTION IF EXISTS add_constraints_to_deposits_partition;
DROP FUNCTION IF EXISTS create_table_refunds;
DROP FUNCTION IF EXISTS add_constraints_to_refunds_partition;
DROP FUNCTION IF EXISTS create_table_refresh_commitments;
DROP FUNCTION IF EXISTS add_constraints_to_refresh_commitments_partition;
DROP FUNCTION IF EXISTS create_table_refresh_revealed_coins;
DROP FUNCTION IF EXISTS add_constraints_to_refresh_revealed_coins_partition;
DROP FUNCTION IF EXISTS create_table_refresh_transfer_keys;
DROP FUNCTION IF EXISTS add_constraints_to_refresh_transfer_keys_partition;
DROP FUNCTION IF EXISTS create_table_known_coins;
DROP FUNCTION IF EXISTS add_constraints_to_known_coins_partition;
DROP FUNCTION IF EXISTS create_table_reserves_close;
DROP FUNCTION IF EXISTS add_constraints_to_reserves_close_partition;
DROP FUNCTION IF EXISTS create_table_reserves_out;
DROP FUNCTION IF EXISTS create_table_reserves_out_by_reserve;
DROP FUNCTION IF EXISTS add_constraints_to_reserves_out_partition;
DROP FUNCTION IF EXISTS create_table_reserves_in;
DROP FUNCTION IF EXISTS add_constraints_to_reserves_in_partition;
DROP FUNCTION IF EXISTS create_table_reserves;
DROP FUNCTION IF EXISTS create_table_cs_nonce_locks;
DROP FUNCTION IF EXISTS add_constraints_to_cs_nonce_locks_partition;

DROP FUNCTION IF EXISTS create_table_purse_requests;
DROP FUNCTION IF EXISTS add_constraints_to_purse_requests_partition;
DROP FUNCTION IF EXISTS create_table_purse_refunds;
DROP FUNCTION IF EXISTS add_constraints_to_purse_refunds_partition;
DROP FUNCTION IF EXISTS create_table_purse_merges;
DROP FUNCTION IF EXISTS add_constraints_to_purse_merges_partition;
DROP FUNCTION IF EXISTS create_table_account_merges;
DROP FUNCTION IF EXISTS add_constraints_to_account_merges_partition;
DROP FUNCTION IF EXISTS create_table_contracts;
DROP FUNCTION IF EXISTS add_constraints_to_contracts_partition;
DROP FUNCTION IF EXISTS create_table_history_requests;
DROP FUNCTION IF EXISTS create_table_close_requests;
DROP FUNCTION IF EXISTS create_table_purse_deposits;
DROP FUNCTION IF EXISTS add_constraints_to_purse_deposits_partition;
DROP FUNCTION IF EXISTS create_table_wad_out_entries;
DROP FUNCTION IF EXISTS add_constraints_to_wad_out_entries_partition;
DROP FUNCTION IF EXISTS create_table_wads_in;
DROP FUNCTION IF EXISTS add_constraints_to_wads_in_partition;
DROP FUNCTION IF EXISTS create_table_wad_in_entries;
DROP FUNCTION IF EXISTS add_constraints_to_wad_in_entries_partition;

DROP FUNCTION IF EXISTS create_partitioned_table;
DROP FUNCTION IF EXISTS create_hash_partition;
DROP FUNCTION IF EXISTS create_range_partition;
DROP FUNCTION IF EXISTS create_partitions;
DROP FUNCTION IF EXISTS detach_default_partitions;
DROP FUNCTION IF EXISTS drop_default_partitions;
DROP FUNCTION IF EXISTS prepare_sharding;
DROP FUNCTION IF EXISTS create_foreign_hash_partition;
DROP FUNCTION IF EXISTS create_foreign_range_partition;
DROP FUNCTION IF EXISTS create_foreign_servers;
DROP FUNCTION IF EXISTS create_shard_server;

COMMIT;
