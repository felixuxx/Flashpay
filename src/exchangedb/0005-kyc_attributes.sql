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

CREATE FUNCTION create_table_kyc_attributes5(
  IN partition_suffix TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'kyc_attributes';
BEGIN
  PERFORM create_partitioned_table(
    'ALTER TABLE %I'
    ' DROP COLUMN kyc_prox'
    ',DROP COLUMN provider'
    ',DROP COLUMN satisfied_checks'
    ',ADD COLUMN legitimization_process_serial_id INT8 DEFAULT NULL'
    ',ADD COLUMN trigger_outcome_serial INT8 NOT NULL'
    ';'
    ,table_name
    ,''
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'serial ID of the legitimization process that resulted in these attributes, NULL if the attributes are from a form directly supplied by the account owner via a form'
    ,'legitimization_process_serial_id'
    ,table_name
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'ID of the outcome that was returned by the AML program based on the KYC data collected'
    ,'trigger_outcome_serial'
    ,table_name
    ,partition_suffix
  );
END $$;


CREATE OR REPLACE FUNCTION foreign_table_kyc_attributes5()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'kyc_attributes';
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' ADD CONSTRAINT ' || table_name || '_foreign_legitimization_outcomes'
    ' FOREIGN KEY (trigger_outcome_serial) '
    ' REFERENCES legitimization_outcomes (outcome_serial_id) ON DELETE CASCADE'
  );
END $$;


INSERT INTO exchange_tables
    (name
    ,version
    ,action
    ,partitioned
    ,by_range)
  VALUES
    ('kyc_attributes5'
    ,'exchange-0005'
    ,'create'
    ,TRUE
    ,FALSE),
    ('kyc_attributes5'
    ,'exchange-0005'
    ,'foreign'
    ,TRUE
    ,FALSE);
