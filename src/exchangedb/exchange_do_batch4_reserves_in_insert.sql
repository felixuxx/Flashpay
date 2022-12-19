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
CREATE OR REPLACE FUNCTION exchange_do_batch4_reserves_insert(
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
  IN in3_notify text,
  IN in4_notify text,
  IN in2_reserve_pub BYTEA,
  IN in2_wire_ref INT8,
  IN in2_credit_val INT8,
  IN in2_credit_frac INT4,
  IN in2_exchange_account_name VARCHAR,
  IN in2_exectution_date INT8,
  IN in2_wire_source_h_payto BYTEA,    ---h_payto
  IN in2_payto_uri VARCHAR,
  IN in2_reserve_expiration INT8,
  IN in3_reserve_pub BYTEA,
  IN in3_wire_ref INT8,
  IN in3_credit_val INT8,
  IN in3_credit_frac INT4,
  IN in3_exchange_account_name VARCHAR,
  IN in3_exectution_date INT8,
  IN in3_wire_source_h_payto BYTEA,    ---h_payto
  IN in3_payto_uri VARCHAR,
  IN in3_reserve_expiration INT8,
  IN in4_reserve_pub BYTEA,
  IN in4_wire_ref INT8,
  IN in4_credit_val INT8,
  IN in4_credit_frac INT4,
  IN in4_exchange_account_name VARCHAR,
  IN in4_exectution_date INT8,
  IN in4_wire_source_h_payto BYTEA,    ---h_payto
  IN in4_payto_uri VARCHAR,
  IN in4_reserve_expiration INT8,
  OUT out_reserve_found BOOLEAN,
  OUT out_reserve_found2 BOOLEAN,
  OUT out_reserve_found3 BOOLEAN,
  OUT out_reserve_found4 BOOLEAN,
  OUT transaction_duplicate BOOLEAN,
  OUT transaction_duplicate2 BOOLEAN,
  OUT transaction_duplicate3 BOOLEAN,
  OUT transaction_duplicate4 BOOLEAN,
  OUT ruuid INT8,
  OUT ruuid2 INT8,
  OUT ruuid3 INT8,
  OUT ruuid4 INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  curs_reserve_exist refcursor;

DECLARE
  curs_transaction_exist CURSOR
  FOR SELECT reserve_pub
  FROM reserves_in
  WHERE in_reserve_pub = reserves_in.reserve_pub
  OR in2_reserve_pub = reserves_in.reserve_pub
  OR in3_reserve_pub = reserves_in.reserve_pub
  OR in4_reserve_pub = reserves_in.reserve_pub;
DECLARE
  i RECORD;

BEGIN
--INITIALIZATION
  transaction_duplicate=FALSE;
  transaction_duplicate2=FALSE;
  transaction_duplicate3=FALSE;
  transaction_duplicate4=FALSE;
  out_reserve_found = TRUE;
  out_reserve_found2 = TRUE;
  out_reserve_found3 = TRUE;
  out_reserve_found4 = TRUE;
  ruuid=0;
  ruuid2=0;
  ruuid3=0;
  ruuid4=0;

  --SIMPLE INSERT ON CONFLICT DO NOTHING
  INSERT INTO wire_targets
    (wire_target_h_payto
    ,payto_uri)
    VALUES
    (in_wire_source_h_payto
    ,in_payto_uri),
    (in2_wire_source_h_payto
    ,in2_payto_uri),
    (in3_wire_source_h_payto
    ,in3_payto_uri),
    (in4_wire_source_h_payto
    ,in4_payto_uri)
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
      ,in_gc_date),
      (in3_reserve_pub
      ,in3_credit_val
      ,in3_credit_frac
      ,in_expiration_date
      ,in_gc_date),
      (in4_reserve_pub
      ,in4_credit_val
      ,in4_credit_frac
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
    IF in3_reserve_pub = i.reserve_pub
    THEN
        out_reserve_found3 = FALSE;
        ruuid3 = i.reserve_uuid;
    END IF;
    IF in4_reserve_pub = i.reserve_pub
    THEN
        out_reserve_found4 = FALSE;
        ruuid4 = i.reserve_uuid;
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
      IF in3_reserve_pub = i.reserve_pub
      THEN
        out_reserve_found3 = FALSE;
        ruuid3 = i.reserve_uuid;
      END IF;
      IF in4_reserve_pub = i.reserve_pub
      THEN
        out_reserve_found4 = FALSE;
        ruuid4 = i.reserve_uuid;
      END IF;
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
      IF in3_reserve_pub = i.reserve_pub
      THEN
          out_reserve_found3 = FALSE;
          ruuid3 = i.reserve_uuid;
      END IF;
      IF in4_reserve_pub = i.reserve_pub
      THEN
          out_reserve_found4 = FALSE;
          ruuid4 = i.reserve_uuid;
      END IF;
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
      IF in3_reserve_pub = i.reserve_pub
      THEN
          out_reserve_found3 = FALSE;
          ruuid3 = i.reserve_uuid;
      END IF;
      IF in4_reserve_pub = i.reserve_pub
      THEN
          out_reserve_found4 = FALSE;
          ruuid4 = i.reserve_uuid;
      END IF;
    END IF;
  END IF;
  CLOSE curs_reserve_exist;
  IF out_reserve_found AND out_reserve_found2 AND out_reserve_found3 AND out_reserve_found4
  THEN
      RETURN;
  END IF;

  PERFORM pg_notify(in_notify, NULL);
  PERFORM pg_notify(in2_notify, NULL);
  PERFORM pg_notify(in3_notify, NULL);
  PERFORM pg_notify(in4_notify, NULL);

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
    (in2_reserve_pub
    ,in2_wire_ref
    ,in2_credit_val
    ,in2_credit_frac
    ,in2_exchange_account_name
    ,in2_wire_source_h_payto
    ,in_expiration_date),
    (in3_reserve_pub
    ,in3_wire_ref
    ,in3_credit_val
    ,in3_credit_frac
    ,in3_exchange_account_name
    ,in3_wire_source_h_payto
    ,in_expiration_date),
    (in4_reserve_pub
    ,in4_wire_ref
    ,in4_credit_val
    ,in4_credit_frac
    ,in4_exchange_account_name
    ,in4_wire_source_h_payto
    ,in_expiration_date)
    ON CONFLICT DO NOTHING;
  IF FOUND
  THEN
    transaction_duplicate = FALSE;  /*HAPPY PATH THERE IS NO DUPLICATE TRANS AND NEW RESERVE*/
    transaction_duplicate2 = FALSE;
    transaction_duplicate3 = FALSE;
    transaction_duplicate4 = FALSE;
    RETURN;
  ELSE
    FOR l IN curs_transaction_exist
    LOOP
      IF in_reserve_pub = l.reserve_pub
      THEN
         transaction_duplicate = TRUE;
      END IF;

      IF in2_reserve_pub = l.reserve_pub
      THEN
         transaction_duplicate2 = TRUE;
      END IF;
      IF in3_reserve_pub = l.reserve_pub
      THEN
         transaction_duplicate3 = TRUE;
      END IF;
      IF in4_reserve_pub = l.reserve_pub
      THEN
         transaction_duplicate4 = TRUE;
      END IF;

      IF transaction_duplicate AND transaction_duplicate2 AND transaction_duplicate3 AND transaction_duplicate4
      THEN
        RETURN;
      END IF;
    END LOOP;
  END IF;

  CLOSE curs_reserve_exist;
  CLOSE curs_transaction_exist;
  RETURN;
END $$;
