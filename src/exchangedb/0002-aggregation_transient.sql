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

CREATE FUNCTION create_table_aggregation_transient(
  IN shard_suffix VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name VARCHAR DEFAULT 'aggregation_transient';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE %I '
    '(amount taler_amount NOT NULL'
    ',wire_target_h_payto BYTEA CHECK (LENGTH(wire_target_h_payto)=32)'
    ',merchant_pub BYTEA CHECK (LENGTH(merchant_pub)=32)'
    ',exchange_account_section TEXT NOT NULL'
    ',legitimization_requirement_serial_id INT8 NOT NULL DEFAULT(0)'
    ',wtid_raw BYTEA NOT NULL CHECK (LENGTH(wtid_raw)=32)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (wire_target_h_payto)'
    ,shard_suffix
  );
  PERFORM comment_partitioned_table(
    'aggregations currently happening (lacking wire_out, usually because the amount is too low); this table is not replicated'
    ,table_name
    ,shard_suffix
  );
  PERFORM comment_partitioned_column(
       'Sum of all of the aggregated deposits (without deposit fees)'
      ,'amount'
      ,table_name
      ,shard_suffix
  );
  PERFORM comment_partitioned_column(
       'identifier of the wire transfer'
      ,'wtid_raw'
      ,table_name
      ,shard_suffix
  );
END
$$;


INSERT INTO exchange_tables
    (name
    ,version
    ,action
    ,partitioned
    ,by_range)
  VALUES
    ('aggregation_transient'
    ,'exchange-0002'
    ,'create'
    ,TRUE
    ,FALSE);
