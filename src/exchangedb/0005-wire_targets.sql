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

CREATE OR REPLACE FUNCTION random_bytea(
  bytea_length INT
)
RETURNS BYTEA
  AS $body$
  SELECT decode(string_agg(lpad(to_hex(width_bucket(random(), 0, 1, 256)-1),2,'0') ,''), 'hex')
    FROM generate_series(1, $1);
  $body$
LANGUAGE 'sql'
VOLATILE;

CREATE FUNCTION create_table_wire_targets5(
  IN partition_suffix TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM create_partitioned_table(
    'ALTER TABLE %I'
    ' ADD COLUMN target_token BYTEA UNIQUE CHECK(LENGTH(target_token)=32) DEFAULT random_bytea(32)'
    ',ADD COLUMN target_pub BYTEA CHECK(LENGTH(target_pub)=32) DEFAULT NULL'
    ';'
    ,'wire_targets'
    ,partition_suffix
  );

  PERFORM comment_partitioned_column(
     'high-entropy random value that is used as a bearer token used to authenticate access to the KYC SPA and its state (without requiring a signature)'
    ,'target_token'
    ,'wire_targets'
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'Public key of a merchant instance or reserve to authenticate access; NULL if KYC is not allowed for the account (if there was no incoming KYC wire transfer yet); updated, thus NOT available to the auditor'
    ,'target_pub'
    ,'wire_targets'
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
    ('wire_targets5'
    ,'exchange-0005'
    ,'create'
    ,TRUE
    ,FALSE);
