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
CREATE OR REPLACE FUNCTION exchange_do_batch2_reserves_insert(
  IN in_reserve_pub BYTEA,
  IN in_expiration_date INT8,
  IN in_gc_date INT8,
  IN in_wire_ref INT8,
  IN in_credit_val INT8,
  IN in_credit_frac INT4,
  IN in_exchange_account_name VARCHAR,
  IN in_exectution_date INT8,
  IN in_wire_source_h_payto BYTEA,    ---h_payto
  IN in_payto_uri VARCHAR,
  IN in_reserve_expiration INT8,
  IN in_notify text,
  IN in2_notify text,
  IN in2_reserve_pub BYTEA,
  IN in2_wire_ref INT8,
  IN in2_credit_val INT8,
  IN in2_credit_frac INT4,
  IN in2_exchange_account_name VARCHAR,
  IN in2_exectution_date INT8,
  IN in2_wire_source_h_payto BYTEA,    ---h_payto
  IN in2_payto_uri VARCHAR,
  IN in2_reserve_expiration INT8,
  OUT out_reserve_found BOOLEAN,
  OUT out_reserve_found2 BOOLEAN,
  OUT transaction_duplicate BOOLEAN,
  OUT transaction_duplicate2 BOOLEAN,
  OUT ruuid INT8,
  OUT ruuid2 INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  curs_reserve_exist REFCURSOR;
DECLARE
  curs_transaction_exist refcursor;
DECLARE
  i RECORD;
DECLARE
  r RECORD;
BEGIN
  --SIMPLE INSERT ON CONFLICT DO NOTHING
  transaction_duplicate=TRUE;
  transaction_duplicate2=TRUE;
  out_reserve_found = TRUE;
  out_reserve_found2 = TRUE;
  ruuid=0;
  ruuid2=0;
  INSERT INTO wire_targets
    (wire_target_h_payto
    ,payto_uri)
    VALUES
    (in_wire_source_h_payto
    ,in_payto_uri),
    (in2_wire_source_h_payto
    ,in2_payto_uri)
  ON CONFLICT DO NOTHING;

  OPEN curs_reserve_exist FOR
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
      ,in_gc_date),
      (in2_reserve_pub
      ,in2_credit_val
      ,in2_credit_frac
      ,in_expiration_date
      ,in_gc_date)
     ON CONFLICT DO NOTHING
     RETURNING reserve_uuid,reserve_pub)
    SELECT * FROM reserve_changes;

  FETCH FROM curs_reserve_exist INTO i;
  IF FOUND
  THEN
    IF in_reserve_pub = i.reserve_pub
    THEN
       out_reserve_found = FALSE;
       ruuid = i.reserve_uuid;
    END IF;
    IF in2_reserve_pub = i.reserve_pub
    THEN
        out_reserve_found2 = FALSE;
        ruuid2 = i.reserve_uuid;
    END IF;
    FETCH FROM curs_reserve_exist INTO i;
    IF FOUND
    THEN
      IF in_reserve_pub = i.reserve_pub
      THEN
        out_reserve_found = FALSE;
        ruuid = i.reserve_uuid;
      END IF;
      IF in2_reserve_pub = i.reserve_pub
      THEN
        out_reserve_found2 = FALSE;
        ruuid2 = i.reserve_uuid;
     END IF;
    END IF;
  END IF;
  CLOSE curs_reserve_exist;
  IF out_reserve_found AND out_reserve_found2
  THEN
      RETURN;
  END IF;

  PERFORM pg_notify(in_notify, NULL);
  PERFORM pg_notify(in2_notify, NULL);

  OPEN curs_transaction_exist FOR
  WITH reserve_in_exist AS (
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
    ,in_expiration_date),
    (in3_reserve_pub
    ,in2_wire_ref
    ,in2_credit_val
    ,in2_credit_frac
    ,in2_exchange_account_name
    ,in2_wire_source_h_payto
    ,in_expiration_date)
    ON CONFLICT DO NOTHING
    RETURNING reserve_pub)
  SELECT * FROM reserve_in_exist;
  FETCH FROM curs_transaction_exist INTO r;
  IF FOUND
  THEN
    IF in_reserve_pub = r.reserve_pub
    THEN
       transaction_duplicate = FALSE;
    END IF;
    IF in2_reserve_pub = r.reserve_pub
    THEN
       transaction_duplicate2 = FALSE;
    END IF;
    FETCH FROM curs_transaction_exist INTO r;
    IF FOUND
    THEN
      IF in_reserve_pub = r.reserve_pub
      THEN
        transaction_duplicate = FALSE;
      END IF;
      IF in2_reserve_pub = r.reserve_pub
      THEN
        transaction_duplicate2 = FALSE;
      END IF;
    END IF;
  END IF;
/*  IF transaction_duplicate
  OR transaction_duplicate2
  THEN
    CLOSE curs_transaction_exist;
    ROLLBACK;
    RETURN;
  END IF;*/
  CLOSE curs_transaction_exist;
  RETURN;
END $$;

