--
-- This file is part of TALER
-- Copyright (C) 2022 Taler Systems SA
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

CREATE FUNCTION create_table_withdraw_age_reveals(
  IN partition_suffix VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  table_name VARCHAR DEFAULT 'withdraw_age_reveals';
BEGIN
  PERFORM create_partitioned_table(
    'CREATE TABLE %I'
      '(withdraw_age_commitments_id INT8 NOT NULL' -- TODO: can here be the foreign key reference?
      ',freshcoin_index INT4 NOT NULL'
      ',denominations_serial INT8 NOT NULL' -- TODO: can here be the foreign key reference?
      ',h_coin_ev BYTEA CHECK (LENGTH(h_coin_ev)=32)'
    ') %s ;'
    ,table_name
    ,'PARTITION BY HASH (withdraw_age_commitments_id)' -- TODO: does that make sense?
    ,partition_suffix
  );
  PERFORM comment_partitioned_table(
     'Reveal of proofs of the correct age restriction after the commitment when withdrawing coins with age restriction'
    ,table_name
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'Foreign key reference to the corresponding commitment'
    ,'withdraw_age_commitments_id'
    ,table_name
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'Index of the coin in the withdraw-age request, which is implicitly a batch request'
    ,'freshcoin_index'
    ,table_name
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'Foreign key reference to the denominations'
    ,'denominations_serial'
    ,table_name
    ,partition_suffix
  );
  PERFORM comment_partitioned_column(
     'Hash of the blinded coins'
    ,'h_coin_ev'
    ,table_name
    ,partition_suffix
  );
END
$$;


CREATE FUNCTION foreign_table_withdraw_age_reveals()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  table_name VARCHAR DEFAULT 'withdraw_age_reveals';
BEGIN
  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' ADD CONSTRAINT ' || table_name || '_foreign_withdraw_age_commitment_id'
    ' FOREIGN KEY (withdraw_age_commitments_id) '
    ' REFERENCES withdraw_age_commitments (withdraw_age_commitment_id) ON DELETE CASCADE'
  );
  EXECUTE FORMAT (
    'ALTER TABLE ' || table_name ||
    ' ADD CONSTRAINT ' || table_name || '_foreign_denominations_serial'
    ' FOREIGN KEY (denominations_serial) '
    ' REFERENCES denominations (denominations_serial) ON DELETE CASCADE'
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
    ('withdraw_age_reveals'
    ,'exchange-0003'
    ,'create'
    ,TRUE
    ,FALSE),
    ('withdraw_age_reveals'
    ,'exchange-0003'
    ,'foreign'
    ,TRUE
    ,FALSE);
