--
-- This file is part of TALER
-- Copyright (C) 2024 Taler Systems SA
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

CREATE FUNCTION create_table_legitimization_processes5(
  IN shard_suffix TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM create_partitioned_table(
    'ALTER TABLE %I'
    ' ADD COLUMN legitimization_measure_serial_id BIGINT'
    ',RENAME COLUMN provider_section TO provider_name'
    ',ADD COLUMN measure_index INT4'
    ';'
    ,'legitimization_processes'
    ,''
    ,shard_suffix
  );
  PERFORM comment_partitioned_column(
     'measure that enabled this setup, NULL if client voluntarily initiated the process'
    ,'legitimization_measure_serial_id'
    ,'legitimization_processes'
    ,shard_suffix
  );
  PERFORM comment_partitioned_column(
     'index of the measure in legitimization_measures that was selected for this KYC setup; NULL if legitimization_measure_serial_id is NULL; enables determination of the context data provided to the external proces'
    ,'measure_index'
    ,'legitimization_processes'
    ,shard_suffix
  );
END
$$;

-- We need a separate function for this, as we call create_table only once but need to add
-- those constraints to each partition which gets created
CREATE FUNCTION foreign_table_legitimization_processes5()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'legitimization_processes';
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' ADD CONSTRAINT ' || table_name || '_foreign_key_legitimization_measure'
    ' FOREIGN KEY (legitimization_measure_serial_id)'
    ' REFERENCES legitimization_measures (legitimization_measure_serial_id)');
END
$$;


INSERT INTO exchange_tables
    (name
    ,version
    ,action
    ,partitioned
    ,by_range)
  VALUES
    ('legitimization_processes5'
    ,'exchange-0005'
    ,'create'
    ,TRUE
    ,FALSE),
    ('legitimization_processes5'
    ,'exchange-0005'
    ,'foreign'
    ,TRUE
    ,FALSE);
