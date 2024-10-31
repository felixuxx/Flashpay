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

CREATE FUNCTION alter_table_wire_targets7()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE wire_targets'
    ' ADD COLUMN h_normalized_payto BYTEA CHECK(LENGTH(h_normalized_payto)=32)'
    '   DEFAULT NULL'
    ';'
  );

  PERFORM comment_partitioned_column(
     'hash over the normalized payto URI for this account; used for KYC operations; NULL if not available (due to DB migration not initializing this value)'
    ,'h_normalized_payto'
    ,'wire_targets'
    ,NULL
  );
END $$;


CREATE FUNCTION constrain_table_wire_targets7(
  IN partition_suffix TEXT
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  table_name TEXT DEFAULT 'wire_targets';
BEGIN
  table_name = concat_ws('_', table_name, partition_suffix);
  EXECUTE FORMAT (
    'CREATE INDEX ' || table_name || '_normalized_h_payto_index '
    'ON ' || table_name || ' '
    '(h_normalized_payto);'
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
    ('wire_targets7'
    ,'exchange-0007'
    ,'alter'
    ,TRUE
    ,FALSE),
    ('wire_targets7'
    ,'exchange-0007'
    ,'constrain'
    ,TRUE
    ,FALSE);
