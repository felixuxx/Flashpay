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

CREATE FUNCTION create_table_aml_history5(
  IN partition_suffix TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'aml_history';
BEGIN
  PERFORM create_partitioned_table(
    'ALTER TABLE %I'
    ' DROP COLUMN new_threshold'
    ',DROP COLUMN new_status'
    ',DROP COLUMN decision_time'
    ',DROP COLUMN kyc_requirements'
    ',DROP COLUMN kyc_req_row'
    ',ADD COLUMN outcome_serial_id INT8 NOT NULL'
    ';'
    ,table_name
    ,''
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'Actual outcome for the account (included in what decider_sig signs over)'
    ,'outcome_serial_id'
    ,table_name
    ,partition_suffix
  );
END $$;


CREATE FUNCTION foreign_table_aml_history5()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'aml_history';
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' ADD CONSTRAINT ' || table_name || '_legitimization_outcome'
    ' FOREIGN KEY (outcome_serial_id)'
    ' REFERENCES legitimization_outcomes (outcome_serial_id)'
  );
END $$;


INSERT INTO exchange_tables
    (name
    ,version
    ,action
    ,partitioned
    ,by_range)
  VALUES
    ('aml_history5'
    ,'exchange-0005'
    ,'create'
    ,TRUE
    ,FALSE),
    ('aml_history5'
    ,'exchange-0005'
    ,'foreign'
    ,TRUE
    ,FALSE);
