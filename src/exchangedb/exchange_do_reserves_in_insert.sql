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
  IN in_wire_source_h_payto BYTEA,
  IN in_payto_uri VARCHAR,
  IN in_notify TEXT,
  OUT out_reserve_found0 BOOLEAN,
  OUT transaction_duplicate0 BOOLEAN,
  OUT ruuid0 INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  curs refcursor;
DECLARE
  i RECORD;
DECLARE
  curs_trans refcursor;
BEGIN
  ruuid0 = 0;
  out_reserve_found0 = TRUE;
  transaction_duplicate0 = TRUE;

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
  SELECT reserve_uuid, reserve_pub FROM reserve_changes;

  FETCH FROM curs INTO i;
  IF FOUND
  THEN
    -- We made a change, so the reserve did not previously exist.
    out_reserve_found0 = FALSE;
    ruuid0 = i.reserve_uuid;
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
  SELECT reserve_pub FROM reserve_transaction;

  FETCH FROM curs_trans INTO i;
  IF FOUND
  THEN
    transaction_duplicate0 = FALSE;
    EXECUTE FORMAT (
         'NOTIFY %s'
         ,in_notify);
  END IF;

  CLOSE curs_trans;

  RETURN;
END $$;


CREATE OR REPLACE FUNCTION exchange_do_batch2_reserves_insert(
  IN in_gc_date INT8,
  IN in_reserve_expiration INT8,
  IN in0_reserve_pub BYTEA,
  IN in0_wire_ref INT8,
  IN in0_credit_val INT8,
  IN in0_credit_frac INT4,
  IN in0_exchange_account_name VARCHAR,
  IN in0_execution_date INT8,
  IN in0_wire_source_h_payto BYTEA,
  IN in0_payto_uri VARCHAR,
  IN in0_notify TEXT,
  IN in1_reserve_pub BYTEA,
  IN in1_wire_ref INT8,
  IN in1_credit_val INT8,
  IN in1_credit_frac INT4,
  IN in1_exchange_account_name VARCHAR,
  IN in1_execution_date INT8,
  IN in1_wire_source_h_payto BYTEA,
  IN in1_payto_uri VARCHAR,
  IN in1_notify TEXT,
  OUT out_reserve_found0 BOOLEAN,
  OUT out_reserve_found1 BOOLEAN,
  OUT transaction_duplicate0 BOOLEAN,
  OUT transaction_duplicate1 BOOLEAN,
  OUT ruuid0 INT8,
  OUT ruuid1 INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  curs_reserve_exist REFCURSOR;
DECLARE
  curs_transaction_exist REFCURSOR;
DECLARE
  i RECORD;
DECLARE
  r RECORD;
DECLARE
  k INT8;
BEGIN
  transaction_duplicate0 = TRUE;
  transaction_duplicate1 = TRUE;
  out_reserve_found0 = TRUE;
  out_reserve_found1 = TRUE;
  ruuid0=0;
  ruuid1=0;

  INSERT INTO wire_targets
    (wire_target_h_payto
    ,payto_uri)
    VALUES
    (in0_wire_source_h_payto
    ,in0_payto_uri),
    (in1_wire_source_h_payto
    ,in1_payto_uri)
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
      (in0_reserve_pub
      ,in0_credit_val
      ,in0_credit_frac
      ,in_reserve_expiration
      ,in_gc_date),
      (in1_reserve_pub
      ,in1_credit_val
      ,in1_credit_frac
      ,in_reserve_expiration
      ,in_gc_date)
    ON CONFLICT DO NOTHING
    RETURNING reserve_uuid, reserve_pub)
  SELECT reserve_uuid, reserve_pub FROM reserve_changes;

  k=0;
  <<loop_reserve>> LOOP
    FETCH FROM curs_reserve_exist INTO i;
    IF NOT FOUND
    THEN
      EXIT loop_reserve;
    END IF;

    <<loop_k>> LOOP
      CASE k
        WHEN 0 THEN
          k = k + 1;
          IF in0_reserve_pub = i.reserve_pub
          THEN
            ruuid0 = i.reserve_uuid;
            out_reserve_found0 = FALSE;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 1 THEN
          IF in1_reserve_pub = i.reserve_pub
          THEN
            ruuid1 = i.reserve_uuid;
            out_reserve_found1 = FALSE;
            EXIT loop_reserve;
          END IF;
          EXIT loop_k;
      END CASE;
    END LOOP loop_k;
  END LOOP loop_reserve;

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
    (in0_reserve_pub
    ,in0_wire_ref
    ,in0_credit_val
    ,in0_credit_frac
    ,in0_exchange_account_name
    ,in0_wire_source_h_payto
    ,in0_execution_date),
    (in1_reserve_pub
    ,in1_wire_ref
    ,in1_credit_val
    ,in1_credit_frac
    ,in1_exchange_account_name
    ,in1_wire_source_h_payto
    ,in1_execution_date)
    ON CONFLICT DO NOTHING
    RETURNING reserve_pub)
  SELECT reserve_pub FROM reserve_in_exist;

  FETCH FROM curs_transaction_exist INTO r;

  k=0;
  <<loop_transaction>> LOOP
    FETCH FROM curs_transaction_exist INTO i;
    IF NOT FOUND
    THEN
      EXIT loop_transaction;
    END IF;

    <<loop2_k>> LOOP
      CASE k
        WHEN 0 THEN
          k = k + 1;
          IF in0_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate0 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in0_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 1 THEN
          IF in0_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate1 = FALSE;
            EXECUTE FORMAT (
              'NOTIFY %s'
              ,in1_notify);
            EXIT loop_transaction;
          END IF;
      END CASE;
    END LOOP loop2_k;
  END LOOP loop_transaction;

  CLOSE curs_transaction_exist;

  RETURN;
END $$;


CREATE OR REPLACE FUNCTION exchange_do_batch4_reserves_insert(
  IN in_gc_date INT8,
  IN in_reserve_expiration INT8,
  IN in0_reserve_pub BYTEA,
  IN in0_wire_ref INT8,
  IN in0_credit_val INT8,
  IN in0_credit_frac INT4,
  IN in0_exchange_account_name VARCHAR,
  IN in0_execution_date INT8,
  IN in0_wire_source_h_payto BYTEA,
  IN in0_payto_uri VARCHAR,
  IN in0_notify TEXT,
  IN in1_reserve_pub BYTEA,
  IN in1_wire_ref INT8,
  IN in1_credit_val INT8,
  IN in1_credit_frac INT4,
  IN in1_exchange_account_name VARCHAR,
  IN in1_execution_date INT8,
  IN in1_wire_source_h_payto BYTEA,
  IN in1_payto_uri VARCHAR,
  IN in1_notify TEXT,
  IN in2_reserve_pub BYTEA,
  IN in2_wire_ref INT8,
  IN in2_credit_val INT8,
  IN in2_credit_frac INT4,
  IN in2_exchange_account_name VARCHAR,
  IN in2_execute_date INT8,
  IN in2_wire_source_h_payto BYTEA,
  IN in2_payto_uri VARCHAR,
  IN in2_notify TEXT,
  IN in3_reserve_pub BYTEA,
  IN in3_wire_ref INT8,
  IN in3_credit_val INT8,
  IN in3_credit_frac INT4,
  IN in3_exchange_account_name VARCHAR,
  IN in3_execute_date INT8,
  IN in3_wire_source_h_payto BYTEA,
  IN in3_payto_uri VARCHAR,
  IN in3_notify TEXT,
  OUT out_reserve_found0 BOOLEAN,
  OUT out_reserve_found1 BOOLEAN,
  OUT out_reserve_found2 BOOLEAN,
  OUT out_reserve_found3 BOOLEAN,
  OUT transaction_duplicate0 BOOLEAN,
  OUT transaction_duplicate1 BOOLEAN,
  OUT transaction_duplicate2 BOOLEAN,
  OUT transaction_duplicate3 BOOLEAN,
  OUT ruuid0 INT8,
  OUT ruuid1 INT8,
  OUT ruuid2 INT8,
  OUT ruuid3 INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  curs_reserve_exist REFCURSOR;
DECLARE
  k INT8;
DECLARE
  curs_transaction_exist REFCURSOR;
DECLARE
  i RECORD;
BEGIN
  transaction_duplicate0=TRUE;
  transaction_duplicate1=TRUE;
  transaction_duplicate2=TRUE;
  transaction_duplicate3=TRUE;
  out_reserve_found0 = TRUE;
  out_reserve_found1 = TRUE;
  out_reserve_found2 = TRUE;
  out_reserve_found3 = TRUE;
  ruuid0=0;
  ruuid1=0;
  ruuid2=0;
  ruuid3=0;

  INSERT INTO wire_targets
    (wire_target_h_payto
    ,payto_uri)
    VALUES
    (in0_wire_source_h_payto
    ,in0_payto_uri),
    (in1_wire_source_h_payto
    ,in1_payto_uri),
    (in2_wire_source_h_payto
    ,in2_payto_uri),
    (in3_wire_source_h_payto
    ,in3_payto_uri)
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
      (in0_reserve_pub
      ,in0_credit_val
      ,in0_credit_frac
      ,in_reserve_expiration
      ,in_gc_date),
      (in1_reserve_pub
      ,in1_credit_val
      ,in1_credit_frac
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
      ,in_gc_date)
    ON CONFLICT DO NOTHING
    RETURNING reserve_uuid,reserve_pub)
  SELECT reserve_uuid, reserve_pub FROM reserve_changes;

  k=0;
  <<loop_reserve>> LOOP
    FETCH FROM curs_reserve_exist INTO i;
    IF NOT FOUND
    THEN
      EXIT loop_reserve;
    END IF;

    <<loop_k>> LOOP
      CASE k
        WHEN 0 THEN
          k = k + 1;
          IF in0_reserve_pub = i.reserve_pub
          THEN
            ruuid0 = i.reserve_uuid;
            out_reserve_found0 = FALSE;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 1 THEN
          k = k + 1;
          IF in1_reserve_pub = i.reserve_pub
          THEN
            ruuid1 = i.reserve_uuid;
            out_reserve_found1 = FALSE;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 2 THEN
          k = k + 1;
          IF in2_reserve_pub = i.reserve_pub
          THEN
            ruuid2 = i.reserve_uuid;
            out_reserve_found2 = FALSE;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 3 THEN
          IF in3_reserve_pub = i.reserve_pub
          THEN
            ruuid3 = i.reserve_uuid;
            out_reserve_found3 = FALSE;
            EXIT loop_reserve;
          END IF;
          EXIT loop_k;
      END CASE;
    END LOOP loop_k;
  END LOOP loop_reserve;

  CLOSE curs_reserve_exist;

  OPEN curs_transaction_exist FOR
  WITH reserve_changes AS (
    INSERT INTO reserves_in
      (reserve_pub
      ,wire_reference
      ,credit_val
      ,credit_frac
      ,exchange_account_section
      ,wire_source_h_payto
      ,execution_date)
      VALUES
      (in0_reserve_pub
      ,in0_wire_ref
      ,in0_credit_val
      ,in0_credit_frac
      ,in0_exchange_account_name
      ,in0_wire_source_h_payto
      ,in0_execution_date),
      (in1_reserve_pub
      ,in1_wire_ref
      ,in1_credit_val
      ,in1_credit_frac
      ,in1_exchange_account_name
      ,in1_wire_source_h_payto
      ,in1_execution_date),
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
      ,in3_execution_date)
    ON CONFLICT DO NOTHING
    RETURNING reserve_pub)
  SELECT reserve_uuid, reserve_pub FROM reserve_changes;

  k=0;
  <<loop_transaction>> LOOP
    FETCH FROM curs_transaction_exist INTO i;
    IF NOT FOUND
    THEN
      EXIT loop_transaction;
    END IF;

    <<loop2_k>> LOOP
      CASE k
        WHEN 0 THEN
          k = k + 1;
          IF in0_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate0 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in0_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 1 THEN
          k = k + 1;
          IF in1_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate1 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in1_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 2 THEN
          k = k + 1;
          IF in2_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate2 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in2_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 3 THEN
          IF in3_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate3 = FALSE;
            EXECUTE FORMAT (
              'NOTIFY %s'
              ,in3_notify);
            EXIT loop_transaction;
          END IF;
      END CASE;
    END LOOP loop2_k;
  END LOOP loop_transaction;

  CLOSE curs_transaction_exist;

  RETURN;
END $$;


CREATE OR REPLACE FUNCTION exchange_do_batch8_reserves_insert(
  IN in_gc_date INT8,
  IN in_reserve_expiration INT8,
  IN in0_reserve_pub BYTEA,
  IN in0_wire_ref INT8,
  IN in0_credit_val INT8,
  IN in0_credit_frac INT4,
  IN in0_exchange_account_name VARCHAR,
  IN in0_execution_date INT8,
  IN in0_wire_source_h_payto BYTEA,
  IN in0_payto_uri VARCHAR,
  IN in0_notify TEXT,
  IN in1_reserve_pub BYTEA,
  IN in1_wire_ref INT8,
  IN in1_credit_val INT8,
  IN in1_credit_frac INT4,
  IN in1_exchange_account_name VARCHAR,
  IN in1_execution_date INT8,
  IN in1_wire_source_h_payto BYTEA,
  IN in1_payto_uri VARCHAR,
  IN in1_notify TEXT,
  IN in2_reserve_pub BYTEA,
  IN in2_wire_ref INT8,
  IN in2_credit_val INT8,
  IN in2_credit_frac INT4,
  IN in2_exchange_account_name VARCHAR,
  IN in2_execution_date INT8,
  IN in2_wire_source_h_payto BYTEA,
  IN in2_payto_uri VARCHAR,
  IN in2_notify TEXT,
  IN in3_reserve_pub BYTEA,
  IN in3_wire_ref INT8,
  IN in3_credit_val INT8,
  IN in3_credit_frac INT4,
  IN in3_exchange_account_name VARCHAR,
  IN in3_execution_date INT8,
  IN in3_wire_source_h_payto BYTEA,
  IN in3_payto_uri VARCHAR,
  IN in3_notify TEXT,
  IN in4_reserve_pub BYTEA,
  IN in4_wire_ref INT8,
  IN in4_credit_val INT8,
  IN in4_credit_frac INT4,
  IN in4_exchange_account_name VARCHAR,
  IN in4_execution_date INT8,
  IN in4_wire_source_h_payto BYTEA,
  IN in4_payto_uri VARCHAR,
  IN in4_notify TEXT,
  IN in5_reserve_pub BYTEA,
  IN in5_wire_ref INT8,
  IN in5_credit_val INT8,
  IN in5_credit_frac INT4,
  IN in5_exchange_account_name VARCHAR,
  IN in5_execution_date INT8,
  IN in5_wire_source_h_payto BYTEA,
  IN in5_payto_uri VARCHAR,
  IN in5_notify TEXT,
  IN in6_reserve_pub BYTEA,
  IN in6_wire_ref INT8,
  IN in6_credit_val INT8,
  IN in6_credit_frac INT4,
  IN in6_exchange_account_name VARCHAR,
  IN in6_execution_date INT8,
  IN in6_wire_source_h_payto BYTEA,
  IN in6_payto_uri VARCHAR,
  IN in6_notify TEXT,
  IN in7_reserve_pub BYTEA,
  IN in7_wire_ref INT8,
  IN in7_credit_val INT8,
  IN in7_credit_frac INT4,
  IN in7_exchange_account_name VARCHAR,
  IN in7_execution_date INT8,
  IN in7_wire_source_h_payto BYTEA,
  IN in7_payto_uri VARCHAR,
  IN in7_notify TEXT,
  OUT out_reserve_found0 BOOLEAN,
  OUT out_reserve_found1 BOOLEAN,
  OUT out_reserve_found2 BOOLEAN,
  OUT out_reserve_found3 BOOLEAN,
  OUT out_reserve_found4 BOOLEAN,
  OUT out_reserve_found5 BOOLEAN,
  OUT out_reserve_found6 BOOLEAN,
  OUT out_reserve_found7 BOOLEAN,
  OUT transaction_duplicate0 BOOLEAN,
  OUT transaction_duplicate1 BOOLEAN,
  OUT transaction_duplicate2 BOOLEAN,
  OUT transaction_duplicate3 BOOLEAN,
  OUT transaction_duplicate4 BOOLEAN,
  OUT transaction_duplicate5 BOOLEAN,
  OUT transaction_duplicate6 BOOLEAN,
  OUT transaction_duplicate7 BOOLEAN,
  OUT ruuid0 INT8,
  OUT ruuid1 INT8,
  OUT ruuid2 INT8,
  OUT ruuid3 INT8,
  OUT ruuid4 INT8,
  OUT ruuid5 INT8,
  OUT ruuid6 INT8,
  OUT ruuid7 INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  curs_reserve_exist REFCURSOR;
DECLARE
  k INT8;
DECLARE
  curs_transaction_exist REFCURSOR;
DECLARE
  i RECORD;
DECLARE
  r RECORD;

BEGIN
  transaction_duplicate0=TRUE;
  transaction_duplicate1=TRUE;
  transaction_duplicate2=TRUE;
  transaction_duplicate3=TRUE;
  transaction_duplicate4=TRUE;
  transaction_duplicate5=TRUE;
  transaction_duplicate6=TRUE;
  transaction_duplicate7=TRUE;
  out_reserve_found0 = TRUE;
  out_reserve_found1 = TRUE;
  out_reserve_found2 = TRUE;
  out_reserve_found3 = TRUE;
  out_reserve_found4 = TRUE;
  out_reserve_found5 = TRUE;
  out_reserve_found6 = TRUE;
  out_reserve_found7 = TRUE;
  ruuid0=0;
  ruuid1=0;
  ruuid2=0;
  ruuid3=0;
  ruuid4=0;
  ruuid5=0;
  ruuid6=0;
  ruuid7=0;

  INSERT INTO wire_targets
    (wire_target_h_payto
    ,payto_uri)
    VALUES
    (in0_wire_source_h_payto
    ,in0_payto_uri),
    (in1_wire_source_h_payto
    ,in1_payto_uri),
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
    ,in7_payto_uri)
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
      (in0_reserve_pub
      ,in0_credit_val
      ,in0_credit_frac
      ,in_reserve_expiration
      ,in_gc_date),
      (in1_reserve_pub
      ,in1_credit_val
      ,in1_credit_frac
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
      ,in_gc_date)
    ON CONFLICT DO NOTHING
    RETURNING reserve_uuid,reserve_pub)
  SELECT reserve_uuid, reserve_pub FROM reserve_changes;

  k=0;
  <<loop_reserve>> LOOP
    FETCH FROM curs_reserve_exist INTO i;
    IF NOT FOUND
    THEN
      EXIT loop_reserve;
    END IF;

    <<loop_k>> LOOP
      CASE k
        WHEN 0 THEN
          k = k + 1;
          IF in0_reserve_pub = i.reserve_pub
          THEN
            ruuid0 = i.reserve_uuid;
            out_reserve_found0 = FALSE;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 1 THEN
          k = k + 1;
          IF in1_reserve_pub = i.reserve_pub
          THEN
            ruuid1 = i.reserve_uuid;
            out_reserve_found1 = FALSE;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 2 THEN
          k = k + 1;
          IF in2_reserve_pub = i.reserve_pub
          THEN
            ruuid2 = i.reserve_uuid;
            out_reserve_found2 = FALSE;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 3 THEN
          k = k + 1;
          IF in3_reserve_pub = i.reserve_pub
          THEN
            ruuid3 = i.reserve_uuid;
            out_reserve_found3 = FALSE;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 4 THEN
          k = k + 1;
          IF in4_reserve_pub = i.reserve_pub
          THEN
            ruuid4 = i.reserve_uuid;
            out_reserve_found4 = FALSE;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 5 THEN
          k = k + 1;
          IF in5_reserve_pub = i.reserve_pub
          THEN
            ruuid5 = i.reserve_uuid;
            out_reserve_found5 = FALSE;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 6 THEN
          k = k + 1;
          IF in6_reserve_pub = i.reserve_pub
          THEN
            ruuid6 = i.reserve_uuid;
            out_reserve_found6 = FALSE;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 7 THEN
          IF in7_reserve_pub = i.reserve_pub
          THEN
            ruuid7 = i.reserve_uuid;
            out_reserve_found7 = FALSE;
            EXIT loop_reserve;
          END IF;
          EXIT loop_k;
      END CASE;
    END LOOP loop_k;
  END LOOP loop_reserve;

  CLOSE curs_reserve_exist;

  OPEN curs_transaction_exist FOR
  WITH reserve_changes AS (
    INSERT INTO reserves_in
      (reserve_pub
      ,wire_reference
      ,credit_val
      ,credit_frac
      ,exchange_account_section
      ,wire_source_h_payto
      ,execution_date)
      VALUES
      (in0_reserve_pub
      ,in0_wire_ref
      ,in0_credit_val
      ,in0_credit_frac
      ,in0_exchange_account_name
      ,in0_wire_source_h_payto
      ,in0_execution_date),
      (in1_reserve_pub
      ,in1_wire_ref
      ,in1_credit_val
      ,in1_credit_frac
      ,in1_exchange_account_name
      ,in1_wire_source_h_payto
      ,in1_execution_date),
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
      ,in7_execution_date)
    ON CONFLICT DO NOTHING
    RETURNING reserve_pub)
  SELECT reserve_pub FROM reserve_changes;

  k=0;
  <<loop_transaction>> LOOP
    FETCH FROM curs_transaction_exist INTO i;
    IF NOT FOUND
    THEN
      EXIT loop_transaction;
    END IF;

    <<loop2_k>> LOOP
      CASE k
        WHEN 0 THEN
          k = k + 1;
          IF in0_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate0 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in0_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 1 THEN
          k = k + 1;
          IF in1_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate1 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in1_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 2 THEN
          k = k + 1;
          IF in2_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate2 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in2_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 3 THEN
          k = k + 1;
          IF in3_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate3 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in3_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 4 THEN
          k = k + 1;
          IF in4_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate4 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in4_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 5 THEN
          k = k + 1;
          IF in5_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate2 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in5_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 6 THEN
          k = k + 1;
          IF in6_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate6 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in6_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 7 THEN
          IF in7_reserve_pub = r.reserve_pub
          THEN
            transaction_duplicate7 = FALSE;
            EXECUTE FORMAT (
              'NOTIFY %s'
              ,in7_notify);
            EXIT loop_transaction;
          END IF;
      END CASE;
    END LOOP loop2_k;
  END LOOP loop_transaction;

  CLOSE curs_transaction_exist;
  RETURN;
END $$;
