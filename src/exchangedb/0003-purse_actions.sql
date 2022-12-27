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


CREATE OR REPLACE FUNCTION create_table_purse_actions(
  IN partition_suffix VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_actions';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE IF NOT EXISTS %I'
      '(purse_pub BYTEA NOT NULL PRIMARY KEY CHECK(LENGTH(purse_pub)=32)'
      ',action_date INT8 NOT NULL'
      ',partner_serial_id INT8'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (purse_pub)'
    ,partition_suffix
  );
  PERFORM comment_partitioned_table(
     'purses awaiting some action by the router'
    ,table_name
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'public (contract) key of the purse'
    ,'purse_pub'
    ,table_name
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'when is the purse ready for action'
    ,'action_date'
    ,table_name
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'wad target of an outgoing wire transfer, 0 for local, NULL if the purse is unmerged and thus the target is still unknown'
    ,'partner_serial_id'
    ,table_name
    ,partition_suffix
  );
END $$;


CREATE OR REPLACE FUNCTION purse_requests_insert_trigger()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  INSERT INTO
    purse_actions
    (purse_pub
    ,action_date)
  VALUES
    (NEW.purse_pub
    ,NEW.purse_expiration);
  RETURN NEW;
END $$;

COMMENT ON FUNCTION purse_requests_insert_trigger()
  IS 'When a purse is created, insert it into the purse_action table to take action when the purse expires.';


CREATE OR REPLACE FUNCTION master_table_purse_actions()
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name VARCHAR DEFAULT 'purse_actions';
BEGIN
  -- Create global index
  CREATE INDEX IF NOT EXISTS purse_action_by_target
    ON purse_actions
    (partner_serial_id,action_date);

  -- Setup trigger
  CREATE TRIGGER purse_requests_on_insert
    AFTER INSERT
    ON purse_requests
    FOR EACH ROW EXECUTE FUNCTION purse_requests_insert_trigger();
  COMMENT ON TRIGGER purse_requests_on_insert
          ON purse_requests
    IS 'Here we install an entry for the purse expiration.';
END $$;


INSERT INTO exchange_tables
    (name
    ,version
    ,action
    ,partitioned
    ,by_range)
  VALUES
    ('purse_actions'
    ,'exchange-0003'
    ,'create'
    ,TRUE
    ,FALSE),
    ('purse_actions'
    ,'exchange-0003'
    ,'master'
    ,TRUE
    ,FALSE);
