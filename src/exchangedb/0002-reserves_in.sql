--
-- This file is part of TALER
-- Copyright (C) 2014--2023 Taler Systems SA
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

CREATE FUNCTION create_table_reserves_in(
  IN partition_suffix TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT default 'reserves_in';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE %I'
      '(reserve_in_serial_id BIGINT GENERATED BY DEFAULT AS IDENTITY'
      ',reserve_pub BYTEA PRIMARY KEY'
      ',wire_reference INT8 NOT NULL'
      ',credit taler_amount NOT NULL'
      ',wire_source_h_payto BYTEA CHECK (LENGTH(wire_source_h_payto)=32)'
      ',exchange_account_section TEXT NOT NULL'
      ',execution_date INT8 NOT NULL'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (reserve_pub)'
    ,partition_suffix
  );
  PERFORM comment_partitioned_table(
     'list of transfers of funds into the reserves, one per incoming wire transfer'
    ,table_name
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'Identifies the debited bank account and KYC status'
    ,'wire_source_h_payto'
    ,table_name
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'Public key of the reserve. Private key signifies ownership of the remaining balance.'
    ,'reserve_pub'
    ,table_name
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'Amount that was transferred into the reserve'
    ,'credit'
    ,table_name
    ,partition_suffix
  );
END $$;


CREATE FUNCTION constrain_table_reserves_in(
  IN partition_suffix TEXT
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT default 'reserves_in';
BEGIN
  table_name = concat_ws('_', table_name, partition_suffix);
  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' ADD CONSTRAINT ' || table_name || '_reserve_in_serial_id_key'
    ' UNIQUE (reserve_in_serial_id)'
  );
  EXECUTE FORMAT (
    'CREATE INDEX ' || table_name || '_by_reserve_in_serial_id_index '
    'ON ' || table_name || ' '
    '(reserve_in_serial_id);'
  );
  EXECUTE FORMAT (
    'CREATE INDEX ' || table_name || '_by_exch_accnt_reserve_in_serial_id_idx '
    'ON ' || table_name || ' '
    '(exchange_account_section'
    ',reserve_in_serial_id ASC'
    ');'
  );
  EXECUTE FORMAT (
    'COMMENT ON INDEX ' || table_name || '_by_exch_accnt_reserve_in_serial_id_idx '
    'IS ' || quote_literal ('for pg_select_reserves_in_above_serial_id_by_account') || ';'
  );

END
$$;

CREATE FUNCTION foreign_table_reserves_in()
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'reserves_in';
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' ADD CONSTRAINT ' || table_name || '_foreign_reserve_pub'
    ' FOREIGN KEY (reserve_pub) '
    ' REFERENCES reserves(reserve_pub) ON DELETE CASCADE'
  );
END $$;



CREATE OR REPLACE FUNCTION reserves_in_insert_trigger()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  INSERT INTO reserve_history
    (reserve_pub
    ,table_name
    ,serial_id)
  VALUES
    (NEW.reserve_pub
    ,'reserves_in'
    ,NEW.reserve_in_serial_id);
  RETURN NEW;
END $$;
COMMENT ON FUNCTION reserves_in_insert_trigger()
  IS 'Automatically generate reserve history entry.';


CREATE FUNCTION master_table_reserves_in()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  CREATE TRIGGER reserves_in_on_insert
    AFTER INSERT
     ON reserves_in
     FOR EACH ROW EXECUTE FUNCTION reserves_in_insert_trigger();
END $$;


INSERT INTO exchange_tables
    (name
    ,version
    ,action
    ,partitioned
    ,by_range)
  VALUES
    ('reserves_in'
    ,'exchange-0002'
    ,'create'
    ,TRUE
    ,FALSE),
    ('reserves_in'
    ,'exchange-0002'
    ,'constrain'
    ,TRUE
    ,FALSE),
    ('reserves_in'
    ,'exchange-0002'
    ,'foreign'
    ,TRUE
    ,FALSE),
    ('reserves_in'
    ,'exchange-0002'
    ,'master'
    ,TRUE
    ,FALSE);
