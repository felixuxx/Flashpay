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

-- Adds a 'unique' constraint to the 'purse_pub'.
-- This is not only semantically correct, but also
-- creates a dramatic speed-up on the
-- pg_select_purse query (which otherwise fails to
-- use indices correctly).

CREATE FUNCTION constrain_table_purse_decision3(
  IN partition_suffix TEXT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'purse_decision';
BEGIN
  table_name = concat_ws('_', table_name, partition_suffix);
  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' ADD CONSTRAINT ' || table_name || '_purse_decision_purse_pub'
    ' UNIQUE (purse_pub) '
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
    ('purse_decision3'
    ,'exchange-0003'
    ,'constrain'
    ,TRUE
    ,FALSE);
