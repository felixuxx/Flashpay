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

CREATE FUNCTION foreign_table_legitimization_outcomes7()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'legitimization_outcomes';
BEGIN

  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' DROP CONSTRAINT ' || table_name || '_foreign_key_h_payto');
END
$$;


INSERT INTO exchange_tables
    (name
    ,version
    ,action
    ,partitioned
    ,by_range)
  VALUES
    ('legitimization_outcomes7'
    ,'exchange-0007'
    ,'foreign'
    ,TRUE
    ,FALSE);
