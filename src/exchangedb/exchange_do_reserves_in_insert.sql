--
-- This file is part of TALER
-- Copyright (C) 2014--2023 Taler Systems SA
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
  IN in_gc_date INT8,
  IN in_reserve_expiration INT8,
  IN in_reserve_pub BYTEA,
  IN in_wire_ref INT8,
  IN in_credit_val INT8,
  IN in_credit_frac INT4,
  IN in_exchange_account_name VARCHAR,
  IN in_execution_date INT8,
  IN in_wire_source_h_payto BYTEA,    ---h_payto
  IN in_payto_uri VARCHAR,
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
      ,in_reserve_expiration
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

CREATE OR REPLACE FUNCTION exchange_do_batch2_reserves_insert(
  IN in_gc_date INT8,
  IN in_reserve_expiration INT8,
  IN in_reserve_pub BYTEA,
  IN in_wire_ref INT8,
  IN in_credit_val INT8,
  IN in_credit_frac INT4,
  IN in_exchange_account_name VARCHAR,
  IN in_execution_date INT8,
  IN in_wire_source_h_payto BYTEA,    ---h_payto
  IN in_payto_uri VARCHAR,
  IN in_notify text,
  IN in2_notify text,
  IN in2_reserve_pub BYTEA,
  IN in2_wire_ref INT8,
  IN in2_credit_val INT8,
  IN in2_credit_frac INT4,
  IN in2_exchange_account_name VARCHAR,
  IN in2_execution_date INT8,
  IN in2_wire_source_h_payto BYTEA,    ---h_payto
  IN in2_payto_uri VARCHAR,
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
DECLARE
  k INT8;
BEGIN
  transaction_duplicate=TRUE;
  transaction_duplicate2=TRUE;
  out_reserve_found = TRUE;
  out_reserve_found2 = TRUE;
  ruuid=0;
  ruuid2=0;
  k=0;
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
      ,in_reserve_expiration
      ,in_gc_date),
      (in2_reserve_pub
      ,in2_credit_val
      ,in2_credit_frac
      ,in_reserve_expiration
      ,in_gc_date)
     ON CONFLICT DO NOTHING
     RETURNING reserve_uuid,reserve_pub)
    SELECT * FROM reserve_changes;
  WHILE k < 2 LOOP
    FETCH FROM curs_reserve_exist INTO i;
    IF FOUND
    THEN
      IF in_reserve_pub = i.reserve_pub
      THEN
        ruuid = i.reserve_uuid;
        IF in_reserve_pub <> in2_reserve_pub
        THEN
          out_reserve_found = FALSE;
         END IF;
      END IF;
      IF in2_reserve_pub = i.reserve_pub
      THEN
          out_reserve_found2 = FALSE;
          ruuid2 = i.reserve_uuid;
      END IF;
    END IF;
    k=k+1;
  END LOOP;
  CLOSE curs_reserve_exist;

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
    ,in_execution_date),
    (in2_reserve_pub
    ,in2_wire_ref
    ,in2_credit_val
    ,in2_credit_frac
    ,in2_exchange_account_name
    ,in2_wire_source_h_payto
    ,in2_execution_date)
    ON CONFLICT DO NOTHING
    RETURNING reserve_pub)
  SELECT * FROM reserve_in_exist;
  FETCH FROM curs_transaction_exist INTO r;
  IF FOUND
  THEN
    IF in_reserve_pub = r.reserve_pub
    THEN
       transaction_duplicate = FALSE;
       EXECUTE FORMAT (
         'NOTIFY %s'
         ,in_notify);
    END IF;
    IF in2_reserve_pub = r.reserve_pub
    THEN
       transaction_duplicate2 = FALSE;
       EXECUTE FORMAT (
         'NOTIFY %s'
         ,in2_notify);
    END IF;
    FETCH FROM curs_transaction_exist INTO r;
    IF FOUND
    THEN
      IF in_reserve_pub = r.reserve_pub
      THEN
        transaction_duplicate = FALSE;
        EXECUTE FORMAT (
         'NOTIFY %s'
         ,in_notify);
      END IF;
      IF in2_reserve_pub = r.reserve_pub
      THEN
        transaction_duplicate2 = FALSE;
        EXECUTE FORMAT (
         'NOTIFY %s'
         ,in2_notify);
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

CREATE OR REPLACE FUNCTION exchange_do_batch4_reserves_insert(
  IN in_gc_date INT8,
  IN in_reserve_expiration INT8,
  IN in_reserve_pub BYTEA,
  IN in_wire_ref INT8,
  IN in_credit_val INT8,
  IN in_credit_frac INT4,
  IN in_exchange_account_name VARCHAR,
  IN in_execution_date INT8,
  IN in_wire_source_h_payto BYTEA,    ---h_payto
  IN in_payto_uri VARCHAR,
  IN in_notify text,
  IN in2_notify text,
  IN in3_notify text,
  IN in4_notify text,
  IN in2_reserve_pub BYTEA,
  IN in2_wire_ref INT8,
  IN in2_credit_val INT8,
  IN in2_credit_frac INT4,
  IN in2_exchange_account_name VARCHAR,
  IN in2_execute_date INT8,
  IN in2_wire_source_h_payto BYTEA,    ---h_payto
  IN in2_payto_uri VARCHAR,
  IN in3_reserve_pub BYTEA,
  IN in3_wire_ref INT8,
  IN in3_credit_val INT8,
  IN in3_credit_frac INT4,
  IN in3_exchange_account_name VARCHAR,
  IN in3_execute_date INT8,
  IN in3_wire_source_h_payto BYTEA,    ---h_payto
  IN in3_payto_uri VARCHAR,
  IN in4_reserve_pub BYTEA,
  IN in4_wire_ref INT8,
  IN in4_credit_val INT8,
  IN in4_credit_frac INT4,
  IN in4_exchange_account_name VARCHAR,
  IN in4_execution_date INT8,
  IN in4_wire_source_h_payto BYTEA,    ---h_payto
  IN in4_payto_uri VARCHAR,
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
      ,in_reserve_expiration
      ,in_gc_date),
      (in2_reserve_pub
      ,in2_credit_val
      ,in2_credit_frac
      ,in_reserve_expiration
      ,in_gc_date),
      (in3_reserve_pub
      ,in3_credit_val
      ,in3_credit_frac
      ,in_reserve_expiration
      ,in_gc_date),
      (in4_reserve_pub
      ,in4_credit_val
      ,in4_credit_frac
      ,in_reserve_expiration
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
    ,in_execution_date),
    (in2_reserve_pub
    ,in2_wire_ref
    ,in2_credit_val
    ,in2_credit_frac
    ,in2_exchange_account_name
    ,in2_wire_source_h_payto
    ,in2_execution_date),
    (in3_reserve_pub
    ,in3_wire_ref
    ,in3_credit_val
    ,in3_credit_frac
    ,in3_exchange_account_name
    ,in3_wire_source_h_payto
    ,in3_execution_date),
    (in4_reserve_pub
    ,in4_wire_ref
    ,in4_credit_val
    ,in4_credit_frac
    ,in4_exchange_account_name
    ,in4_wire_source_h_payto
    ,in4_execution_date)
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
         EXECUTE FORMAT (
         'NOTIFY %s'
         ,in_notify);
      END IF;
      IF in2_reserve_pub = i.reserve_pub
      THEN
         transaction_duplicate2 = FALSE;
         EXECUTE FORMAT (
         'NOTIFY %s'
         ,in2_notify);
      END IF;
      IF in3_reserve_pub = i.reserve_pub
      THEN
         transaction_duplicate3 = FALSE;
         EXECUTE FORMAT (
         'NOTIFY %s'
         ,in3_notify);
      END IF;
      IF in4_reserve_pub = i.reserve_pub
      THEN
         transaction_duplicate4 = FALSE;
         EXECUTE FORMAT (
         'NOTIFY %s'
         ,in4_notify);
      END IF;
    END IF;
  k=k+1;
  END LOOP;
 /**ROLLBACK TRANSACTION IN SORTED PROCEDURE IS IT PROSSIBLE ?**/
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

CREATE OR REPLACE FUNCTION exchange_do_batch8_reserves_insert(
  IN in_gc_date INT8,
  IN in_reserve_expiration INT8,
  IN in_reserve_pub BYTEA,
  IN in_wire_ref INT8,
  IN in_credit_val INT8,
  IN in_credit_frac INT4,
  IN in_exchange_account_name VARCHAR,
  IN in_execution_date INT8,
  IN in_wire_source_h_payto BYTEA,    ---h_payto
  IN in_payto_uri VARCHAR,
  IN in_notify text,
  IN in2_notify text,
  IN in3_notify text,
  IN in4_notify text,
  IN in5_notify text,
  IN in6_notify text,
  IN in7_notify text,
  IN in8_notify text,
  IN in2_reserve_pub BYTEA,
  IN in2_wire_ref INT8,
  IN in2_credit_val INT8,
  IN in2_credit_frac INT4,
  IN in2_exchange_account_name VARCHAR,
  IN in2_execution_date INT8,
  IN in2_wire_source_h_payto BYTEA,    ---h_payto
  IN in2_payto_uri VARCHAR,
  IN in3_reserve_pub BYTEA,
  IN in3_wire_ref INT8,
  IN in3_credit_val INT8,
  IN in3_credit_frac INT4,
  IN in3_exchange_account_name VARCHAR,
  IN in3_execution_date INT8,
  IN in3_wire_source_h_payto BYTEA,    ---h_payto
  IN in3_payto_uri VARCHAR,
  IN in4_reserve_pub BYTEA,
  IN in4_wire_ref INT8,
  IN in4_credit_val INT8,
  IN in4_credit_frac INT4,
  IN in4_exchange_account_name VARCHAR,
  IN in4_execution_date INT8,
  IN in4_wire_source_h_payto BYTEA,    ---h_payto
  IN in4_payto_uri VARCHAR,
  IN in5_reserve_pub BYTEA,
  IN in5_wire_ref INT8,
  IN in5_credit_val INT8,
  IN in5_credit_frac INT4,
  IN in5_exchange_account_name VARCHAR,
  IN in5_execution_date INT8,
  IN in5_wire_source_h_payto BYTEA,    ---h_payto
  IN in5_payto_uri VARCHAR,
  IN in6_reserve_pub BYTEA,
  IN in6_wire_ref INT8,
  IN in6_credit_val INT8,
  IN in6_credit_frac INT4,
  IN in6_exchange_account_name VARCHAR,
  IN in6_execution_date INT8,
  IN in6_wire_source_h_payto BYTEA,    ---h_payto
  IN in6_payto_uri VARCHAR,
  IN in7_reserve_pub BYTEA,
  IN in7_wire_ref INT8,
  IN in7_credit_val INT8,
  IN in7_credit_frac INT4,
  IN in7_exchange_account_name VARCHAR,
  IN in7_execution_date INT8,
  IN in7_wire_source_h_payto BYTEA,    ---h_payto
  IN in7_payto_uri VARCHAR,
  IN in8_reserve_pub BYTEA,
  IN in8_wire_ref INT8,
  IN in8_credit_val INT8,
  IN in8_credit_frac INT4,
  IN in8_exchange_account_name VARCHAR,
  IN in8_execution_date INT8,
  IN in8_wire_source_h_payto BYTEA,    ---h_payto
  IN in8_payto_uri VARCHAR,
  OUT out_reserve_found BOOLEAN,
  OUT out_reserve_found2 BOOLEAN,
  OUT out_reserve_found3 BOOLEAN,
  OUT out_reserve_found4 BOOLEAN,
  OUT out_reserve_found5 BOOLEAN,
  OUT out_reserve_found6 BOOLEAN,
  OUT out_reserve_found7 BOOLEAN,
  OUT out_reserve_found8 BOOLEAN,
  OUT transaction_duplicate BOOLEAN,
  OUT transaction_duplicate2 BOOLEAN,
  OUT transaction_duplicate3 BOOLEAN,
  OUT transaction_duplicate4 BOOLEAN,
  OUT transaction_duplicate5 BOOLEAN,
  OUT transaction_duplicate6 BOOLEAN,
  OUT transaction_duplicate7 BOOLEAN,
  OUT transaction_duplicate8 BOOLEAN,
  OUT ruuid INT8,
  OUT ruuid2 INT8,
  OUT ruuid3 INT8,
  OUT ruuid4 INT8,
  OUT ruuid5 INT8,
  OUT ruuid6 INT8,
  OUT ruuid7 INT8,
  OUT ruuid8 INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  curs_reserve_existed refcursor;
DECLARE
  k INT8;
DECLARE
  curs_transaction_existed refcursor;
DECLARE
  i RECORD;
DECLARE
  r RECORD;

BEGIN
--INITIALIZATION
  transaction_duplicate=TRUE;
  transaction_duplicate2=TRUE;
  transaction_duplicate3=TRUE;
  transaction_duplicate4=TRUE;
  transaction_duplicate5=TRUE;
  transaction_duplicate6=TRUE;
  transaction_duplicate7=TRUE;
  transaction_duplicate8=TRUE;
  out_reserve_found = TRUE;
  out_reserve_found2 = TRUE;
  out_reserve_found3 = TRUE;
  out_reserve_found4 = TRUE;
  out_reserve_found5 = TRUE;
  out_reserve_found6 = TRUE;
  out_reserve_found7 = TRUE;
  out_reserve_found8 = TRUE;
  ruuid=0;
  ruuid2=0;
  ruuid3=0;
  ruuid4=0;
  ruuid5=0;
  ruuid6=0;
  ruuid7=0;
  ruuid8=0;
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
    ,in4_payto_uri),
    (in5_wire_source_h_payto
    ,in5_payto_uri),
    (in6_wire_source_h_payto
    ,in6_payto_uri),
    (in7_wire_source_h_payto
    ,in7_payto_uri),
    (in8_wire_source_h_payto
    ,in8_payto_uri)
  ON CONFLICT DO NOTHING;

  OPEN curs_reserve_existed FOR
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
      ,in_reserve_expiration
      ,in_gc_date),
      (in2_reserve_pub
      ,in2_credit_val
      ,in2_credit_frac
      ,in_reserve_expiration
      ,in_gc_date),
      (in3_reserve_pub
      ,in3_credit_val
      ,in3_credit_frac
      ,in_reserve_expiration
      ,in_gc_date),
      (in4_reserve_pub
      ,in4_credit_val
      ,in4_credit_frac
      ,in_reserve_expiration
      ,in_gc_date),
      (in5_reserve_pub
      ,in5_credit_val
      ,in5_credit_frac
      ,in_reserve_expiration
      ,in_gc_date),
      (in6_reserve_pub
      ,in6_credit_val
      ,in6_credit_frac
      ,in_reserve_expiration
      ,in_gc_date),
      (in7_reserve_pub
      ,in7_credit_val
      ,in7_credit_frac
      ,in_reserve_expiration
      ,in_gc_date),
      (in8_reserve_pub
      ,in8_credit_val
      ,in8_credit_frac
      ,in_reserve_expiration
      ,in_gc_date)
     ON CONFLICT DO NOTHING
     RETURNING reserve_uuid,reserve_pub)
    SELECT * FROM reserve_changes;

  WHILE k < 8 LOOP

    FETCH FROM curs_reserve_existed INTO i;
    IF FOUND
    THEN
      IF in_reserve_pub = i.reserve_pub
      THEN
         ruuid = i.reserve_uuid;
         IF in_reserve_pub
         NOT IN (in2_reserve_pub
                ,in3_reserve_pub
                ,in4_reserve_pub
                ,in5_reserve_pub
                ,in6_reserve_pub
                ,in7_reserve_pub
                ,in8_reserve_pub)
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
                ,in4_reserve_pub
                ,in5_reserve_pub
                ,in6_reserve_pub
                ,in7_reserve_pub
                ,in8_reserve_pub)
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
                ,in4_reserve_pub
                ,in5_reserve_pub
                ,in6_reserve_pub
                ,in7_reserve_pub
                ,in8_reserve_pub)
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
                ,in3_reserve_pub
                ,in5_reserve_pub
                ,in6_reserve_pub
                ,in7_reserve_pub
                ,in8_reserve_pub)
         THEN
           out_reserve_found4 = FALSE;
         END IF;
      END IF;
      IF in5_reserve_pub = i.reserve_pub
      THEN
         ruuid5 = i.reserve_uuid;
         IF in5_reserve_pub
         NOT IN (in_reserve_pub
                ,in2_reserve_pub
                ,in3_reserve_pub
                ,in4_reserve_pub
                ,in6_reserve_pub
                ,in7_reserve_pub
                ,in8_reserve_pub)
         THEN
           out_reserve_found5 = FALSE;
         END IF;
      END IF;
      IF in6_reserve_pub = i.reserve_pub
      THEN
         ruuid6 = i.reserve_uuid;
         IF in6_reserve_pub
         NOT IN (in_reserve_pub
                ,in2_reserve_pub
                ,in3_reserve_pub
                ,in4_reserve_pub
                ,in5_reserve_pub
                ,in7_reserve_pub
                ,in8_reserve_pub)
         THEN
           out_reserve_found6 = FALSE;
         END IF;
      END IF;
      IF in7_reserve_pub = i.reserve_pub
      THEN
         ruuid7 = i.reserve_uuid;
         IF in7_reserve_pub
         NOT IN (in_reserve_pub
                ,in2_reserve_pub
                ,in3_reserve_pub
                ,in4_reserve_pub
                ,in5_reserve_pub
                ,in6_reserve_pub
                ,in8_reserve_pub)
         THEN
           out_reserve_found7 = FALSE;
         END IF;
      END IF;
      IF in8_reserve_pub = i.reserve_pub
      THEN
         ruuid8 = i.reserve_uuid;
         IF in8_reserve_pub
         NOT IN (in_reserve_pub
                ,in2_reserve_pub
                ,in3_reserve_pub
                ,in4_reserve_pub
                ,in5_reserve_pub
                ,in6_reserve_pub
                ,in7_reserve_pub)
         THEN
           out_reserve_found8 = FALSE;
         END IF;
      END IF;
    END IF;
  k=k+1;
  END LOOP;

  CLOSE curs_reserve_existed;

  k=0;
  OPEN curs_transaction_existed FOR
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
    ,in_execution_date),
    (in2_reserve_pub
    ,in2_wire_ref
    ,in2_credit_val
    ,in2_credit_frac
    ,in2_exchange_account_name
    ,in2_wire_source_h_payto
    ,in2_execution_date),
    (in3_reserve_pub
    ,in3_wire_ref
    ,in3_credit_val
    ,in3_credit_frac
    ,in3_exchange_account_name
    ,in3_wire_source_h_payto
    ,in3_execution_date),
    (in4_reserve_pub
    ,in4_wire_ref
    ,in4_credit_val
    ,in4_credit_frac
    ,in4_exchange_account_name
    ,in4_wire_source_h_payto
    ,in4_execution_date),
    (in5_reserve_pub
    ,in5_wire_ref
    ,in5_credit_val
    ,in5_credit_frac
    ,in5_exchange_account_name
    ,in5_wire_source_h_payto
    ,in5_execution_date),
    (in6_reserve_pub
    ,in6_wire_ref
    ,in6_credit_val
    ,in6_credit_frac
    ,in6_exchange_account_name
    ,in6_wire_source_h_payto
    ,in6_execution_date),
    (in7_reserve_pub
    ,in7_wire_ref
    ,in7_credit_val
    ,in7_credit_frac
    ,in7_exchange_account_name
    ,in7_wire_source_h_payto
    ,in7_execution_date),
    (in8_reserve_pub
    ,in8_wire_ref
    ,in8_credit_val
    ,in8_credit_frac
    ,in8_exchange_account_name
    ,in8_wire_source_h_payto
    ,in8_execution_date)
     ON CONFLICT DO NOTHING
     RETURNING reserve_pub)
    SELECT * FROM reserve_in_changes;

  WHILE k < 8 LOOP
    FETCH FROM curs_transaction_existed INTO r;
    IF FOUND
    THEN
      IF in_reserve_pub = r.reserve_pub
      THEN
         transaction_duplicate = FALSE;
         EXECUTE FORMAT (
         'NOTIFY %s'
         ,in_notify);
      END IF;
      IF in2_reserve_pub = r.reserve_pub
      THEN
         transaction_duplicate2 = FALSE;
         EXECUTE FORMAT (
         'NOTIFY %s'
         ,in2_notify);
      END IF;
      IF in3_reserve_pub = r.reserve_pub
      THEN
         transaction_duplicate3 = FALSE;
         EXECUTE FORMAT (
         'NOTIFY %s'
         ,in3_notify);
      END IF;
      IF in4_reserve_pub = r.reserve_pub
      THEN
         transaction_duplicate4 = FALSE;
         EXECUTE FORMAT (
         'NOTIFY %s'
         ,in4_notify);
      END IF;
      IF in5_reserve_pub = r.reserve_pub
      THEN
         transaction_duplicate5 = FALSE;
         EXECUTE FORMAT (
         'NOTIFY %s'
         ,in5_notify);
      END IF;
      IF in6_reserve_pub = r.reserve_pub
      THEN
         transaction_duplicate6 = FALSE;
         EXECUTE FORMAT (
         'NOTIFY %s'
         ,in6_notify);
      END IF;
      IF in7_reserve_pub = r.reserve_pub
      THEN
         transaction_duplicate7 = FALSE;
         EXECUTE FORMAT (
         'NOTIFY %s'
         ,in7_notify);
      END IF;
      IF in8_reserve_pub = r.reserve_pub
      THEN
         transaction_duplicate8 = FALSE;
         EXECUTE FORMAT (
         'NOTIFY %s'
         ,in8_notify);
      END IF;
    END IF;
  k=k+1;
  END LOOP;
 /* IF transaction_duplicate
  OR transaction_duplicate2
  OR transaction_duplicate3
  OR transaction_duplicate4
  OR transaction_duplicate5
  OR transaction_duplicate6
  OR transaction_duplicate7
  OR transaction_duplicate8
  THEN
    CLOSE curs_transaction_existed;
    ROLLBACK;
    RETURN;
  END IF;*/
  CLOSE curs_transaction_existed;
  RETURN;
END $$;
