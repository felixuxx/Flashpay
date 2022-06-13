--
-- This file is part of TALER
-- Copyright (C) 2014--2022 Taler Systems SA
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

-- Check patch versioning is in place.
SELECT _v.register_patch('shard-0001', NULL, NULL);

CREATE OR REPLACE FUNCTION setup_shard(
  shard_idx INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  shard_suffix VARCHAR;
BEGIN

  shard_suffix = shard_idx::varchar;

  PERFORM create_table_wire_targets(shard_suffix);
  PERFORM add_constraints_to_wire_targets_partition(shard_suffix);

  PERFORM create_table_reserves(shard_suffix);

  PERFORM create_table_reserves_in(shard_suffix);
  PERFORM add_constraints_to_reserves_in_partition(shard_suffix);

  PERFORM create_table_reserves_close(shard_suffix);

  PERFORM create_table_reserves_out(shard_suffix);

  PERFORM create_table_reserves_out_by_reserve(shard_suffix);

  PERFORM create_table_known_coins(shard_suffix);
  PERFORM add_constraints_to_known_coins_partition(shard_suffix);

  PERFORM create_table_refresh_commitments(shard_suffix);
  PERFORM add_constraints_to_refresh_commitments_partition(shard_suffix);

  PERFORM create_table_refresh_revealed_coins(shard_suffix);
  PERFORM add_constraints_to_refresh_revealed_coins_partition(shard_suffix);

  PERFORM create_table_refresh_transfer_keys(shard_suffix);
  PERFORM add_constraints_to_refresh_transfer_keys_partition(shard_suffix);

  PERFORM create_table_deposits(shard_suffix);
  PERFORM add_constraints_to_deposits_partition(shard_suffix);

  PERFORM create_table_deposits_by_ready(shard_suffix);

  PERFORM create_table_deposits_for_matching(shard_suffix);

  PERFORM create_table_refunds(shard_suffix);
  PERFORM add_constraints_to_refunds_partition(shard_suffix);

  PERFORM create_table_wire_out(shard_suffix);
  PERFORM add_constraints_to_wire_out_partition(shard_suffix);

  PERFORM create_table_aggregation_transient(shard_suffix);

  PERFORM create_table_aggregation_tracking(shard_suffix);
  PERFORM add_constraints_to_aggregation_tracking_partition(shard_suffix);

  PERFORM create_table_recoup(shard_suffix);
  PERFORM add_constraints_to_recoup_partition(shard_suffix);

  PERFORM create_table_recoup_by_reserve(shard_suffix);

  PERFORM create_table_recoup_refresh(shard_suffix);
  PERFORM add_constraints_to_recoup_refresh_partition(shard_suffix);

  PERFORM create_table_prewire(shard_suffix);

  PERFORM create_table_cs_nonce_locks(shard_suffix);
  PERFORM add_constraints_to_cs_nonce_locks_partition(shard_suffix);

  PERFORM create_table_purse_requests(shard_suffix);
  PERFORM add_constraints_to_purse_requests_partition(shard_suffix);

  PERFORM create_table_purse_refunds(shard_suffix);
  PERFORM add_constraints_to_purse_refunds_partition(shard_suffix);

  PERFORM create_table_purse_merges(shard_suffix);
  PERFORM add_constraints_to_purse_merges_partition(shard_suffix);

  PERFORM create_table_account_merges(shard_suffix);
  PERFORM add_constraints_to_account_merges_partition(shard_suffix);

  PERFORM create_table_contracts(shard_suffix);
  PERFORM add_constraints_to_contracts_partition(shard_suffix);

  PERFORM create_table_history_requests(shard_suffix);

  PERFORM create_table_close_requests(shard_suffix);

  PERFORM create_table_purse_deposits(shard_suffix);
  PERFORM add_constraints_to_purse_deposits_partition(shard_suffix);

  PERFORM create_table_wad_out_entries(shard_suffix);
  PERFORM add_constraints_to_wad_out_entries_partition(shard_suffix);

  PERFORM create_table_wads_in(shard_suffix);
  PERFORM add_constraints_to_wads_in_partition(shard_suffix);

  PERFORM create_table_wad_in_entries(shard_suffix);
  PERFORM add_constraints_to_wad_in_entries_partition(shard_suffix);
END
$$;


CREATE OR REPLACE FUNCTION drop_shard(
  shard_idx INTEGER
)
  RETURNS VOID
  LANGUAGE plpgsql
AS $$
DECLARE
  shard_suffix VARCHAR;
BEGIN

  shard_suffix = shard_idx::varchar;

  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'wire_targets_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'reserves_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'reserves_in_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'reserves_out_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'reserves_close_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'known_coins_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'refresh_commitments_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'refresh_revealed_coins_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'refresh_transfer_keys_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'deposits_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'deposits_by_ready_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'deposits_for_matching_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'refunds_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'wire_out_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'aggregation_transient_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'aggregation_tracking_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'recoup_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'recoup_by_reserve_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'reserves_out_by_reserve_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'recoup_refresh_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'prewire_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'cs_nonce_locks_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'purse_requests_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'purse_refunds_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'purse_merges_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'account_merges_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'contracts_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'history_requests_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'close_requests_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'purse_deposits_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'wad_out_entries_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'wads_in_' || shard_suffix
  );
  EXECUTE FORMAT(
    'DROP TABLE IF EXISTS %I CASCADE'
    ,'wad_in_entries_' || shard_suffix
  );
END
$$;

COMMIT;
