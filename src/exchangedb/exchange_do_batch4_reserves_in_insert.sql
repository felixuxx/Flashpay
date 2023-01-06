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
  k INT8;
DECLARE
  curs_transaction_exist refcursor;
DECLARE
  i RECORD;

BEGIN
--INITIALIZATION
  transaction_duplicate=TRUE;
  transaction_duplicate2=TRUE;
  transaction_duplicate3=TRUE;
  transaction_duplicate4=TRUE;
  out_reserve_found = TRUE;
  out_reserve_found2 = TRUE;
  out_reserve_found3 = TRUE;
  out_reserve_found4 = TRUE;
  ruuid=0;
  ruuid2=0;
  ruuid3=0;
  ruuid4=0;
  k=0;
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

  WHILE k < 4 LOOP
    FETCH FROM curs_reserve_exist INTO i;
    IF FOUND
    THEN
      IF in_reserve_pub = i.reserve_pub
      THEN
         ruuid = i.reserve_uuid;
         IF in_reserve_pub
         NOT IN (in2_reserve_pub
                ,in3_reserve_pub
                ,in4_reserve_pub)
         THEN
           out_reserve_found = FALSE;
         END IF;
      END IF;
      IF in2_reserve_pub = i.reserve_pub
      THEN
         ruuid2 = i.reserve_uuid;
         IF in2_reserve_pub
         NOT IN (in_reserve_pub
                ,in3_reserve_pub
                ,in4_reserve_pub)
         THEN
           out_reserve_found2 = FALSE;
         END IF;
      END IF;
      IF in3_reserve_pub = i.reserve_pub
      THEN
         ruuid3 = i.reserve_uuid;
         IF in3_reserve_pub
         NOT IN (in_reserve_pub
                ,in2_reserve_pub
                ,in4_reserve_pub)
         THEN
           out_reserve_found3 = FALSE;
         END IF;
      END IF;
      IF in4_reserve_pub = i.reserve_pub
      THEN
         ruuid4 = i.reserve_uuid;
         IF in4_reserve_pub
         NOT IN (in_reserve_pub
                ,in2_reserve_pub
                ,in3_reserve_pub)
         THEN
           out_reserve_found4 = FALSE;
         END IF;
      END IF;
    END IF;
  k=k+1;
  END LOOP;
  CLOSE curs_reserve_exist;


  PERFORM pg_notify(in_notify, NULL);
  PERFORM pg_notify(in2_notify, NULL);
  PERFORM pg_notify(in3_notify, NULL);
  PERFORM pg_notify(in4_notify, NULL);

  k=0;
  OPEN curs_transaction_exist FOR
  WITH reserve_in_changes AS (
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
     ON CONFLICT DO NOTHING
     RETURNING reserve_pub)
    SELECT * FROM reserve_in_changes;
  WHILE k < 4 LOOP
    FETCH FROM curs_transaction_exist INTO i;
    IF FOUND
    THEN
      IF in_reserve_pub = i.reserve_pub
      THEN
         transaction_duplicate = FALSE;
      END IF;
      IF in2_reserve_pub = i.reserve_pub
      THEN
         transaction_duplicate2 = FALSE;
      END IF;
      IF in3_reserve_pub = i.reserve_pub
      THEN
         transaction_duplicate3 = FALSE;
      END IF;
      IF in4_reserve_pub = i.reserve_pub
      THEN
         transaction_duplicate4 = FALSE;
      END IF;
    END IF;
  k=k+1;
  END LOOP;
 /**ROLLBACK TRANSACTION IN SOTRED PROCEDURE IS IT PROSSIBLE ?**/
  /*IF transaction_duplicate
  OR transaction_duplicate2
  OR transaction_duplicate3
  OR transaction_duplicate4
  THEN
    RAISE EXCEPTION 'Reserve did not exist, but INSERT into reserves_in gave conflict';
    ROLLBACK;
    CLOSE curs_transaction_exist;
    RETURN;
  END IF;*/
  CLOSE curs_transaction_exist;
  RETURN;

END $$;
