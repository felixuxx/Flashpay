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

CREATE FUNCTION create_table_wads_out(
  IN shard_suffix TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'wads_out';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE %I '
      '(wad_out_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY'
      ',wad_id BYTEA PRIMARY KEY CHECK (LENGTH(wad_id)=24)'
      ',partner_serial_id INT8 NOT NULL'
      ',amount taler_amount NOT NULL'
      ',execution_time INT8 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (wad_id)'
    ,shard_suffix
  );
  PERFORM comment_partitioned_table(
     'Wire transfers made to another exchange to transfer purse funds'
    ,table_name
    ,shard_suffix
  );
  PERFORM comment_partitioned_column(
     'Unique identifier of the wad, part of the wire transfer subject'
    ,'wad_id'
    ,table_name
    ,shard_suffix
  );
  PERFORM comment_partitioned_column(
     'target exchange of the wad'
    ,'partner_serial_id'
    ,table_name
    ,shard_suffix
  );
  PERFORM comment_partitioned_column(
     'Amount that was wired'
    ,'amount'
    ,table_name
    ,shard_suffix
  );
  PERFORM comment_partitioned_column(
     'Time when the wire transfer was scheduled'
    ,'execution_time'
    ,table_name
    ,shard_suffix
  );
END
$$;


CREATE FUNCTION constrain_table_wads_out(
  IN partition_suffix TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'wads_out';
BEGIN
  table_name = concat_ws('_', table_name, partition_suffix);
  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' ADD CONSTRAINT ' || table_name || '_wad_out_serial_id_key'
    ' UNIQUE (wad_out_serial_id) '
  );
END
$$;


CREATE FUNCTION foreign_table_wads_out()
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'wads_out';
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' ADD CONSTRAINT ' || table_name || '_foreign_partner'
    ' FOREIGN KEY(partner_serial_id)'
    ' REFERENCES partners(partner_serial_id) ON DELETE CASCADE'
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
    ('wads_out'
    ,'exchange-0002'
    ,'create'
    ,TRUE
    ,FALSE),
    ('wads_out'
    ,'exchange-0002'
    ,'constrain'
    ,TRUE
    ,FALSE),
    ('wads_out'
    ,'exchange-0002'
    ,'foreign'
    ,TRUE
    ,FALSE);
