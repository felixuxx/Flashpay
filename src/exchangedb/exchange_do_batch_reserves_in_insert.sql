--
-- This file is part of TALER
-- Copyright (C) 2014--2022 Taler Systems SA
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

CREATE OR REPLACE FUNCTION exchange_do_batch_reserves_in_insert(
  IN in_reserve_pub BYTEA,
  IN in_expiration_date INT8,
  IN in_gc_date INT8,
  IN in_wire_ref INT8,
  IN in_credit_val INT8,
  IN in_credit_frac INT4,
  IN in_exchange_account_name VARCHAR,
  IN in_execution_date INT8,
  IN in_wire_source_h_payto BYTEA,    ---h_payto
  IN in_payto_uri VARCHAR,
  IN in_reserve_expiration INT8,
  IN in_notify text,
  OUT out_reserve_found BOOLEAN,
  OUT transaction_duplicate BOOLEAN,
  OUT ruuid INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  curs refcursor;
DECLARE
  i RECORD;
DECLARE
  curs_trans refcursor;
BEGIN
  ruuid = 0;
  out_reserve_found = TRUE;
  transaction_duplicate = TRUE;

--SIMPLE INSERT ON CONFLICT DO NOTHING
  INSERT INTO wire_targets
    (wire_target_h_payto
    ,payto_uri)
    VALUES
    (in_wire_source_h_payto
    ,in_payto_uri)
  ON CONFLICT DO NOTHING;

  OPEN curs FOR
  WITH reserve_changes AS (
    INSERT INTO reserves
      (reserve_pub
      ,current_balance_val
      ,current_balance_frac
      ,expiration_date
      ,gc_date)
      VALUES
      (in_reserve_pub
      ,in_credit_val
      ,in_credit_frac
      ,in_expiration_date
      ,in_gc_date)
     ON CONFLICT DO NOTHING
     RETURNING reserve_uuid, reserve_pub)
   SELECT * FROM reserve_changes;
  FETCH FROM curs INTO i;
  IF FOUND
  THEN
    -- We made a change, so the reserve did not previously exist.
    IF in_reserve_pub = i.reserve_pub
    THEN
        out_reserve_found = FALSE;
        ruuid = i.reserve_uuid;
    END IF;
  END IF;
  CLOSE curs;

  OPEN curs_trans FOR
  WITH reserve_transaction AS(
  INSERT INTO reserves_in
    (reserve_pub
    ,wire_reference
    ,credit_val
    ,credit_frac
    ,exchange_account_section
    ,wire_source_h_payto
    ,execution_date)
    VALUES
    (in_reserve_pub
    ,in_wire_ref
    ,in_credit_val
    ,in_credit_frac
    ,in_exchange_account_name
    ,in_wire_source_h_payto
    ,in_execution_date)
    ON CONFLICT DO NOTHING
    RETURNING reserve_pub)
  SELECT * FROM reserve_transaction;
  FETCH FROM curs_trans INTO i;
  IF FOUND
  THEN
    IF i.reserve_pub = in_reserve_pub
    THEN
    -- HAPPY PATH THERE IS NO DUPLICATE TRANS
       transaction_duplicate = FALSE;
       EXECUTE FORMAT (
         'NOTIFY %s'
         ,in_notify);
    END IF;
  END IF;
  CLOSE curs_trans;
  RETURN;
END $$;
