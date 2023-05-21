--
-- This file is part of TALER
-- Copyright (C) 2023 Taler Systems SA
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

CREATE OR REPLACE FUNCTION master_table_kyc_attributes_V2()
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name VARCHAR DEFAULT 'kyc_attributes';
BEGIN
  EXECUTE FORMAT (
   'ALTER TABLE ' || table_name ||
   ' DROP COLUMN birthdate;'
  );
END $$;

COMMENT ON FUNCTION master_table_kyc_attributes_V2
  IS 'Removes birthdate column from the kyc_attributes table';

INSERT INTO exchange_tables
    (name
    ,version
    ,action
    ,partitioned
    ,by_range)
  VALUES
    ('kyc_attributes_V2'
    ,'exchange-0004'
    ,'master'
    ,TRUE
    ,FALSE);
