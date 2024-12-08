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

CREATE FUNCTION alter_table_kyc_attributes7(
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
    ' DROP COLUMN trigger_outcome_serial'
    ';'
    ,table_name
    ,''
    ,partition_suffix
  );
END $$;


INSERT INTO exchange_tables
    (name
    ,version
    ,action
    ,partitioned
    ,by_range)
  VALUES
    ('kyc_attributes7'
    ,'exchange-0007'
    ,'alter'
    ,TRUE
    ,FALSE);
