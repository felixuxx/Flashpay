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
-- SELECT _v.register_patch('partition-0001', NULL, NULL);

CREATE OR REPLACE FUNCTION create_table_partition(
    source_table_name VARCHAR
    ,modulus INTEGER
    ,partition_num INTEGER
  )
  RETURNS VOID
  LANGUAGE plpgsql
AS $$
BEGIN

  RAISE NOTICE 'Creating partition %_%', source_table_name, partition_num;

  EXECUTE FORMAT(
    'CREATE TABLE IF NOT EXISTS %I '
      'PARTITION OF %I '
      'FOR VALUES WITH (MODULUS %s, REMAINDER %s)'
    ,source_table_name || '_' || partition_num
    ,source_table_name
    ,modulus
    ,partition_num-1
  );

END
$$;

CREATE OR REPLACE FUNCTION detach_default_partitions()
  RETURNS VOID
  LANGUAGE plpgsql
AS $$
BEGIN

  RAISE NOTICE 'Detaching all default table partitions';

  ALTER TABLE IF EXISTS wire_targets
    DETACH PARTITION wire_targets_default;

  ALTER TABLE IF EXISTS reserves
    DETACH PARTITION reserves_default;

  ALTER TABLE IF EXISTS reserves_in
    DETACH PARTITION reserves_in_default;
  
  ALTER TABLE IF EXISTS reserves_close
    DETACH PARTITION reserves_close_default;
  
  ALTER TABLE IF EXISTS reserves_out
    DETACH PARTITION reserves_out_default;
  
  ALTER TABLE IF EXISTS known_coins
    DETACH PARTITION known_coins_default;
  
  ALTER TABLE IF EXISTS refresh_commitments
    DETACH PARTITION refresh_commitments_default;
  
  ALTER TABLE IF EXISTS refresh_revealed_coins
    DETACH PARTITION refresh_revealed_coins_default;
  
  ALTER TABLE IF EXISTS refresh_transfer_keys
    DETACH PARTITION refresh_transfer_keys_default;
  
  ALTER TABLE IF EXISTS deposits
    DETACH PARTITION deposits_default;
  
  ALTER TABLE IF EXISTS refunds
    DETACH PARTITION refunds_default;
  
  ALTER TABLE IF EXISTS wire_out
    DETACH PARTITION wire_out_default;
  
  ALTER TABLE IF EXISTS aggregation_tracking
    DETACH PARTITION aggregation_tracking_default;
  
  ALTER TABLE IF EXISTS recoup
    DETACH PARTITION recoup_default;
  
  ALTER TABLE IF EXISTS recoup_refresh
    DETACH PARTITION recoup_refresh_default;
  
  ALTER TABLE IF EXISTS prewire
    DETACH PARTITION prewire_default;
  
  ALTER TABLE IF EXISTS cs_nonce_locks
    DETACH partition cs_nonce_locks_default;

END
$$;

COMMENT ON FUNCTION detach_default_partitions
  IS 'We need to drop default and create new one before deleting the default partitions
      otherwise constraints get lost too. Might be needed in shardig too';


CREATE OR REPLACE FUNCTION drop_default_partitions()
  RETURNS VOID
  LANGUAGE plpgsql
AS $$
BEGIN

  RAISE NOTICE 'Dropping default table partitions';

  DROP TABLE IF EXISTS wire_targets_default;
  DROP TABLE IF EXISTS reserves_default;
  DROP TABLE IF EXISTS reserves_in_default;
  DROP TABLE IF EXISTS reserves_close_default;
  DROP TABLE IF EXISTS reserves_out_default;
  DROP TABLE IF EXISTS known_coins_default;
  DROP TABLE IF EXISTS refresh_commitments_default;
  DROP TABLE IF EXISTS refresh_revealed_coins_default;
  DROP TABLE IF EXISTS refresh_transfer_keys_default;
  DROP TABLE IF EXISTS deposits_default;
  DROP TABLE IF EXISTS refunds_default;
  DROP TABLE IF EXISTS wire_out_default;
  DROP TABLE IF EXISTS aggregation_tracking_default;
  DROP TABLE IF EXISTS recoup_default;
  DROP TABLE IF EXISTS recoup_refresh_default;
  DROP TABLE IF EXISTS prewire_default;
  DROP TABLE IF EXISTS cs_nonce_locks_default;

END
$$;

COMMENT ON FUNCTION drop_default_partitions
  IS 'Drop all default partitions once other partitions are attached.
      Might be needed in sharding too.';

CREATE OR REPLACE FUNCTION create_partitions(
    num_partitions INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  modulus INTEGER;
BEGIN

  modulus := num_partitions;

  PERFORM detach_default_partitions();

  LOOP
    PERFORM create_table_partition(
      'wire_targets'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_wire_targets_partition(num_partitions::varchar);

    PERFORM create_table_partition(
      'reserves'
      ,modulus
      ,num_partitions
    );

    PERFORM create_table_partition(
      'reserves_in'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_reserves_in_partition(num_partitions::varchar);

    PERFORM create_table_partition(
      'reserves_close'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_reserves_close_partition(num_partitions::varchar);

    PERFORM create_table_partition(
      'reserves_out'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_reserves_out_partition(num_partitions::varchar);

    PERFORM create_table_partition(
      'known_coins'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_known_coins_partition(num_partitions::varchar);
    
    PERFORM create_table_partition(
      'refresh_commitments'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_refresh_commitments_partition(num_partitions::varchar);

    PERFORM create_table_partition(
      'refresh_revealed_coins'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_refresh_revealed_coins_partition(num_partitions::varchar);

    PERFORM create_table_partition(
      'refresh_transfer_keys'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_refresh_transfer_keys_partition(num_partitions::varchar);

    PERFORM create_table_partition(
      'deposits'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_deposits_partition(num_partitions::varchar);

-- TODO: dynamically (!) creating/deleting deposits partitions:
--    create new partitions 'as needed', drop old ones once the aggregator has made
--    them empty; as 'new' deposits will always have deadlines in the future, this
--    would basically guarantee no conflict between aggregator and exchange service!
-- SEE also: https://www.cybertec-postgresql.com/en/automatic-partition-creation-in-postgresql/
-- (article is slightly wrong, as this works:)
--CREATE TABLE tab (
--  id bigint GENERATED ALWAYS AS IDENTITY,
--  ts timestamp NOT NULL,
--  data text
-- PARTITION BY LIST ((ts::date));
-- CREATE TABLE tab_def PARTITION OF tab DEFAULT;
-- BEGIN
-- CREATE TABLE tab_part2 (LIKE tab);
-- insert into tab_part2 (id,ts, data) values (5,'2022-03-21', 'foo');
-- alter table tab attach partition tab_part2 for values in ('2022-03-21');
-- commit;
-- Naturally, to ensure this is actually 100% conflict-free, we'd
-- need to create tables at the granularity of the wire/refund deadlines;
-- that is right now configurable via AGGREGATOR_SHIFT option.


    PERFORM create_table_partition(
      'refunds'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_refunds_partition(num_partitions::varchar);

    PERFORM create_table_partition(
      'wire_out'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_wire_out_partition(num_partitions::varchar);

    PERFORM create_table_partition(
      'aggregation_tracking'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_aggregation_tracking_partition(num_partitions::varchar);

    PERFORM create_table_partition(
      'recoup'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_recoup_partition(num_partitions::varchar);

    PERFORM create_table_partition(
      'recoup_refresh'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_recoup_refresh_partition(num_partitions::varchar);

    PERFORM create_table_partition(
      'prewire'
      ,modulus
      ,num_partitions
    );

    PERFORM create_table_partition(
      'cs_nonce_locks'
      ,modulus
      ,num_partitions
    );
    PERFORM add_constraints_to_cs_nonce_locks_partition(num_partitions::varchar);

    num_partitions=num_partitions-1;
    EXIT WHEN num_partitions=0;

  END LOOP;

  PERFORM drop_default_partitions();

END
$$;

COMMIT;
