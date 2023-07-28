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
  IN in_credit taler_amount,
  IN in_exchange_account_name VARCHAR,
  IN in_execution_date INT8,
  IN in_wire_source_h_payto BYTEA,
  IN in_payto_uri VARCHAR,
  IN in_notify TEXT,
  OUT transaction_duplicate0 BOOLEAN,
  OUT ruuid0 INT8)
LANGUAGE plpgsql
AS $$
BEGIN

  INSERT INTO wire_targets
    (wire_target_h_payto
    ,payto_uri)
    VALUES
    (in_wire_source_h_payto
    ,in_payto_uri)
  ON CONFLICT DO NOTHING;

  INSERT INTO reserves
    (reserve_pub
    ,current_balance
    ,expiration_date
    ,gc_date)
    VALUES
    (in_reserve_pub
    ,in_credit
    ,in_reserve_expiration
    ,in_gc_date)
  ON CONFLICT DO NOTHING
  RETURNING reserve_uuid
  INTO ruuid0;

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
    ,in_credit.val
    ,in_credit.frac
    ,in_exchange_account_name
    ,in_wire_source_h_payto
    ,in_execution_date)
    ON CONFLICT DO NOTHING;

  transaction_duplicate0 = NOT FOUND;
  IF FOUND
  THEN
    EXECUTE FORMAT (
         'NOTIFY %s'
         ,in_notify);
  END IF;
  RETURN;
END $$;


CREATE OR REPLACE FUNCTION exchange_do_batch2_reserves_insert(
  IN in_gc_date INT8,
  IN in_reserve_expiration INT8,
  IN in0_reserve_pub BYTEA,
  IN in0_wire_ref INT8,
  IN in0_credit taler_amount,
  IN in0_exchange_account_name VARCHAR,
  IN in0_execution_date INT8,
  IN in0_wire_source_h_payto BYTEA,
  IN in0_payto_uri VARCHAR,
  IN in0_notify TEXT,
  IN in1_reserve_pub BYTEA,
  IN in1_wire_ref INT8,
  IN in1_credit taler_amount,
  IN in1_exchange_account_name VARCHAR,
  IN in1_execution_date INT8,
  IN in1_wire_source_h_payto BYTEA,
  IN in1_payto_uri VARCHAR,
  IN in1_notify TEXT,
  OUT transaction_duplicate0 BOOLEAN,
  OUT transaction_duplicate1 BOOLEAN,
  OUT ruuid0 INT8,
  OUT ruuid1 INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  curs_reserve_exist REFCURSOR;
  k INT8;
  curs_transaction_exist REFCURSOR;
  i RECORD;
BEGIN
  transaction_duplicate0 = TRUE;
  transaction_duplicate1 = TRUE;

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
      ,current_balance
      ,expiration_date
      ,gc_date)
      VALUES
      (in0_reserve_pub
      ,in0_credit
      ,in_reserve_expiration
      ,in_gc_date),
      (in1_reserve_pub
      ,in1_credit
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
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 1 THEN
          IF in1_reserve_pub = i.reserve_pub
          THEN
            ruuid1 = i.reserve_uuid;
          END IF;
          EXIT loop_reserve;
      END CASE;
    END LOOP loop_k;
  END LOOP loop_reserve;

  CLOSE curs_reserve_exist;

  OPEN curs_transaction_exist FOR
  WITH reserve_transaction AS (
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
      ,in0_credit.val
      ,in0_credit.frac
      ,in0_exchange_account_name
      ,in0_wire_source_h_payto
      ,in0_execution_date),
      (in1_reserve_pub
      ,in1_wire_ref
      ,in1_credit.val
      ,in1_credit.frac
      ,in1_exchange_account_name
      ,in1_wire_source_h_payto
      ,in1_execution_date)
    ON CONFLICT DO NOTHING
    RETURNING reserve_pub)
  SELECT reserve_pub FROM reserve_transaction;

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
          IF in0_reserve_pub = i.reserve_pub
          THEN
            transaction_duplicate0 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in0_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 1 THEN
          IF in1_reserve_pub = i.reserve_pub
          THEN
            transaction_duplicate1 = FALSE;
            EXECUTE FORMAT (
              'NOTIFY %s'
              ,in1_notify);
          END IF;
          EXIT loop_transaction;
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
  IN in0_credit taler_amount,
  IN in0_exchange_account_name VARCHAR,
  IN in0_execution_date INT8,
  IN in0_wire_source_h_payto BYTEA,
  IN in0_payto_uri VARCHAR,
  IN in0_notify TEXT,
  IN in1_reserve_pub BYTEA,
  IN in1_wire_ref INT8,
  IN in1_credit taler_amount,
  IN in1_exchange_account_name VARCHAR,
  IN in1_execution_date INT8,
  IN in1_wire_source_h_payto BYTEA,
  IN in1_payto_uri VARCHAR,
  IN in1_notify TEXT,
  IN in2_reserve_pub BYTEA,
  IN in2_wire_ref INT8,
  IN in2_credit taler_amount,
  IN in2_exchange_account_name VARCHAR,
  IN in2_execution_date INT8,
  IN in2_wire_source_h_payto BYTEA,
  IN in2_payto_uri VARCHAR,
  IN in2_notify TEXT,
  IN in3_reserve_pub BYTEA,
  IN in3_wire_ref INT8,
  IN in3_credit taler_amount,
  IN in3_exchange_account_name VARCHAR,
  IN in3_execution_date INT8,
  IN in3_wire_source_h_payto BYTEA,
  IN in3_payto_uri VARCHAR,
  IN in3_notify TEXT,
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
  k INT8;
  curs_transaction_exist REFCURSOR;
  i RECORD;
BEGIN
  transaction_duplicate0=TRUE;
  transaction_duplicate1=TRUE;
  transaction_duplicate2=TRUE;
  transaction_duplicate3=TRUE;

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
      ,current_balance
      ,expiration_date
      ,gc_date)
      VALUES
      (in0_reserve_pub
      ,in0_credit
      ,in_reserve_expiration
      ,in_gc_date),
      (in1_reserve_pub
      ,in1_credit
      ,in_reserve_expiration
      ,in_gc_date),
      (in2_reserve_pub
      ,in2_credit
      ,in_reserve_expiration
      ,in_gc_date),
      (in3_reserve_pub
      ,in3_credit
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
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 1 THEN
          k = k + 1;
          IF in1_reserve_pub = i.reserve_pub
          THEN
            ruuid1 = i.reserve_uuid;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 2 THEN
          k = k + 1;
          IF in2_reserve_pub = i.reserve_pub
          THEN
            ruuid2 = i.reserve_uuid;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 3 THEN
          IF in3_reserve_pub = i.reserve_pub
          THEN
            ruuid3 = i.reserve_uuid;
          END IF;
          EXIT loop_reserve;
      END CASE;
    END LOOP loop_k;
  END LOOP loop_reserve;

  CLOSE curs_reserve_exist;

  OPEN curs_transaction_exist FOR
  WITH reserve_transaction AS (
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
      ,in0_credit.val
      ,in0_credit.frac
      ,in0_exchange_account_name
      ,in0_wire_source_h_payto
      ,in0_execution_date),
      (in1_reserve_pub
      ,in1_wire_ref
      ,in1_credit.val
      ,in1_credit.frac
      ,in1_exchange_account_name
      ,in1_wire_source_h_payto
      ,in1_execution_date),
      (in2_reserve_pub
      ,in2_wire_ref
      ,in2_credit.val
      ,in2_credit.frac
      ,in2_exchange_account_name
      ,in2_wire_source_h_payto
      ,in2_execution_date),
      (in3_reserve_pub
      ,in3_wire_ref
      ,in3_credit.val
      ,in3_credit.frac
      ,in3_exchange_account_name
      ,in3_wire_source_h_payto
      ,in3_execution_date)
    ON CONFLICT DO NOTHING
    RETURNING reserve_pub)
  SELECT reserve_pub FROM reserve_transaction;

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
          IF in0_reserve_pub = i.reserve_pub
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
          IF in1_reserve_pub = i.reserve_pub
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
          IF in2_reserve_pub = i.reserve_pub
          THEN
            transaction_duplicate2 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in2_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 3 THEN
          IF in3_reserve_pub = i.reserve_pub
          THEN
            transaction_duplicate3 = FALSE;
            EXECUTE FORMAT (
              'NOTIFY %s'
              ,in3_notify);
          END IF;
          EXIT loop_transaction;
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
  IN in0_credit taler_amount,
  IN in0_exchange_account_name VARCHAR,
  IN in0_execution_date INT8,
  IN in0_wire_source_h_payto BYTEA,
  IN in0_payto_uri VARCHAR,
  IN in0_notify TEXT,
  IN in1_reserve_pub BYTEA,
  IN in1_wire_ref INT8,
  IN in1_credit taler_amount,
  IN in1_exchange_account_name VARCHAR,
  IN in1_execution_date INT8,
  IN in1_wire_source_h_payto BYTEA,
  IN in1_payto_uri VARCHAR,
  IN in1_notify TEXT,
  IN in2_reserve_pub BYTEA,
  IN in2_wire_ref INT8,
  IN in2_credit taler_amount,
  IN in2_exchange_account_name VARCHAR,
  IN in2_execution_date INT8,
  IN in2_wire_source_h_payto BYTEA,
  IN in2_payto_uri VARCHAR,
  IN in2_notify TEXT,
  IN in3_reserve_pub BYTEA,
  IN in3_wire_ref INT8,
  IN in3_credit taler_amount,
  IN in3_exchange_account_name VARCHAR,
  IN in3_execution_date INT8,
  IN in3_wire_source_h_payto BYTEA,
  IN in3_payto_uri VARCHAR,
  IN in3_notify TEXT,
  IN in4_reserve_pub BYTEA,
  IN in4_wire_ref INT8,
  IN in4_credit taler_amount,
  IN in4_exchange_account_name VARCHAR,
  IN in4_execution_date INT8,
  IN in4_wire_source_h_payto BYTEA,
  IN in4_payto_uri VARCHAR,
  IN in4_notify TEXT,
  IN in5_reserve_pub BYTEA,
  IN in5_wire_ref INT8,
  IN in5_credit taler_amount,
  IN in5_exchange_account_name VARCHAR,
  IN in5_execution_date INT8,
  IN in5_wire_source_h_payto BYTEA,
  IN in5_payto_uri VARCHAR,
  IN in5_notify TEXT,
  IN in6_reserve_pub BYTEA,
  IN in6_wire_ref INT8,
  IN in6_credit taler_amount,
  IN in6_exchange_account_name VARCHAR,
  IN in6_execution_date INT8,
  IN in6_wire_source_h_payto BYTEA,
  IN in6_payto_uri VARCHAR,
  IN in6_notify TEXT,
  IN in7_reserve_pub BYTEA,
  IN in7_wire_ref INT8,
  IN in7_credit taler_amount,
  IN in7_exchange_account_name VARCHAR,
  IN in7_execution_date INT8,
  IN in7_wire_source_h_payto BYTEA,
  IN in7_payto_uri VARCHAR,
  IN in7_notify TEXT,
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
  k INT8;
  curs_transaction_exist REFCURSOR;
  i RECORD;
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
      ,current_balance
      ,expiration_date
      ,gc_date)
      VALUES
      (in0_reserve_pub
      ,in0_credit
      ,in_reserve_expiration
      ,in_gc_date),
      (in1_reserve_pub
      ,in1_credit
      ,in_reserve_expiration
      ,in_gc_date),
      (in2_reserve_pub
      ,in2_credit
      ,in_reserve_expiration
      ,in_gc_date),
      (in3_reserve_pub
      ,in3_credit
      ,in_reserve_expiration
      ,in_gc_date),
      (in4_reserve_pub
      ,in4_credit
      ,in_reserve_expiration
      ,in_gc_date),
      (in5_reserve_pub
      ,in5_credit
      ,in_reserve_expiration
      ,in_gc_date),
      (in6_reserve_pub
      ,in6_credit
      ,in_reserve_expiration
      ,in_gc_date),
      (in7_reserve_pub
      ,in7_credit
      ,in_reserve_expiration
      ,in_gc_date)
    ON CONFLICT DO NOTHING
    RETURNING
       reserve_uuid
      ,reserve_pub)
  SELECT
     reserve_uuid
    ,reserve_pub
  FROM reserve_changes;

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
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 1 THEN
          k = k + 1;
          IF in1_reserve_pub = i.reserve_pub
          THEN
            ruuid1 = i.reserve_uuid;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 2 THEN
          k = k + 1;
          IF in2_reserve_pub = i.reserve_pub
          THEN
            ruuid2 = i.reserve_uuid;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 3 THEN
          k = k + 1;
          IF in3_reserve_pub = i.reserve_pub
          THEN
            ruuid3 = i.reserve_uuid;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 4 THEN
          k = k + 1;
          IF in4_reserve_pub = i.reserve_pub
          THEN
            ruuid4 = i.reserve_uuid;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 5 THEN
          k = k + 1;
          IF in5_reserve_pub = i.reserve_pub
          THEN
            ruuid5 = i.reserve_uuid;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 6 THEN
          k = k + 1;
          IF in6_reserve_pub = i.reserve_pub
          THEN
            ruuid6 = i.reserve_uuid;
            CONTINUE loop_reserve;
          END IF;
          CONTINUE loop_k;
        WHEN 7 THEN
          IF in7_reserve_pub = i.reserve_pub
          THEN
            ruuid7 = i.reserve_uuid;
          END IF;
          EXIT loop_reserve;
      END CASE;
    END LOOP loop_k;
  END LOOP loop_reserve;

  CLOSE curs_reserve_exist;

  OPEN curs_transaction_exist FOR
  WITH reserve_transaction AS (
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
      ,in0_credit.val
      ,in0_credit.frac
      ,in0_exchange_account_name
      ,in0_wire_source_h_payto
      ,in0_execution_date),
      (in1_reserve_pub
      ,in1_wire_ref
      ,in1_credit.val
      ,in1_credit.frac
      ,in1_exchange_account_name
      ,in1_wire_source_h_payto
      ,in1_execution_date),
      (in2_reserve_pub
      ,in2_wire_ref
      ,in2_credit.val
      ,in2_credit.frac
      ,in2_exchange_account_name
      ,in2_wire_source_h_payto
      ,in2_execution_date),
      (in3_reserve_pub
      ,in3_wire_ref
      ,in3_credit.val
      ,in3_credit.frac
      ,in3_exchange_account_name
      ,in3_wire_source_h_payto
      ,in3_execution_date),
      (in4_reserve_pub
      ,in4_wire_ref
      ,in4_credit.val
      ,in4_credit.frac
      ,in4_exchange_account_name
      ,in4_wire_source_h_payto
      ,in4_execution_date),
      (in5_reserve_pub
      ,in5_wire_ref
      ,in5_credit.val
      ,in5_credit.frac
      ,in5_exchange_account_name
      ,in5_wire_source_h_payto
      ,in5_execution_date),
      (in6_reserve_pub
      ,in6_wire_ref
      ,in6_credit.val
      ,in6_credit.frac
      ,in6_exchange_account_name
      ,in6_wire_source_h_payto
      ,in6_execution_date),
      (in7_reserve_pub
      ,in7_wire_ref
      ,in7_credit.val
      ,in7_credit.frac
      ,in7_exchange_account_name
      ,in7_wire_source_h_payto
      ,in7_execution_date)
    ON CONFLICT DO NOTHING
    RETURNING reserve_pub)
  SELECT reserve_pub FROM reserve_transaction;

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
          IF in0_reserve_pub = i.reserve_pub
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
          IF in1_reserve_pub = i.reserve_pub
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
          IF in2_reserve_pub = i.reserve_pub
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
          IF in3_reserve_pub = i.reserve_pub
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
          IF in4_reserve_pub = i.reserve_pub
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
          IF in5_reserve_pub = i.reserve_pub
          THEN
            transaction_duplicate5 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in5_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 6 THEN
          k = k + 1;
          IF in6_reserve_pub = i.reserve_pub
          THEN
            transaction_duplicate6 = FALSE;
            EXECUTE FORMAT (
               'NOTIFY %s'
              ,in6_notify);
            CONTINUE loop_transaction;
          END IF;
          CONTINUE loop2_k;
        WHEN 7 THEN
          IF in7_reserve_pub = i.reserve_pub
          THEN
            transaction_duplicate7 = FALSE;
            EXECUTE FORMAT (
              'NOTIFY %s'
              ,in7_notify);
          END IF;
          EXIT loop_transaction;
      END CASE;
    END LOOP loop2_k;
  END LOOP loop_transaction;

  CLOSE curs_transaction_exist;
  RETURN;
END $$;



CREATE OR REPLACE FUNCTION exchange_do_array_reserves_insert(
  IN in_gc_date INT8,
  IN in_reserve_expiration INT8,
  IN ina_reserve_pub BYTEA[],
  IN ina_wire_ref INT8[],
  IN ina_credit_val INT8[],
  IN ina_credit_frac INT4[],
  IN ina_exchange_account_name VARCHAR[],
  IN ina_execution_date INT8[],
  IN ina_wire_source_h_payto BYTEA[],
  IN ina_payto_uri VARCHAR[],
  IN ina_notify TEXT[])
RETURNS SETOF exchange_do_array_reserve_insert_return_type
LANGUAGE plpgsql
AS $$
DECLARE
  curs REFCURSOR;
  conflict BOOL;
  dup BOOL;
  uuid INT8;
  i RECORD;
BEGIN

  INSERT INTO wire_targets
    (wire_target_h_payto
    ,payto_uri)
    SELECT
      wire_source_h_payto
     ,payto_uri
    FROM
      UNNEST (ina_wire_source_h_payto) AS wire_source_h_payto
     ,UNNEST (ina_payto_uri) AS payto_uri
  ON CONFLICT DO NOTHING;

  FOR i IN
    SELECT
      reserve_pub
     ,wire_ref
     ,credit_val
     ,credit_frac
     ,exchange_account_name
     ,execution_date
     ,wire_source_h_payto
     ,payto_uri
     ,notify
    FROM
      UNNEST (ina_reserve_pub) AS reserve_pub
     ,UNNEST (ina_wire_ref) AS wire_ref
     ,UNNEST (ina_credit_val) AS credit_val
     ,UNNEST (ina_credit_frac) AS credit_frac
     ,UNNEST (ina_exchange_account_name) AS exchange_account_name
     ,UNNEST (ina_execution_date) AS execution_date
     ,UNNEST (ina_wire_source_h_payto) AS wire_source_h_payto
     ,UNNEST (ina_notify) AS notify
  LOOP
    INSERT INTO reserves
      (reserve_pub
      ,current_balance_val
      ,current_balance_frac
      ,expiration_date
      ,gc_date
    ) VALUES (
      i.reserve_pub
     ,i.credit_val
     ,i.credit_frac
     ,in_reserve_expiration
     ,in_gc_date
    )
    ON CONFLICT DO NOTHING
    RETURNING reserve_uuid
      INTO uuid;
    conflict = NOT FOUND;

    INSERT INTO reserves_in
      (reserve_pub
      ,wire_reference
      ,credit_val
      ,credit_frac
      ,exchange_account_section
      ,wire_source_h_payto
      ,execution_date
    ) VALUES (
      i.reserve_pub
     ,i.wire_reference
     ,i.credit_val
     ,i.credit_frac
     ,i.exchange_account_section
     ,i.wire_source_h_payto
     ,i.execution_date
    )
    ON CONFLICT DO NOTHING;

    IF NOT FOUND
    THEN
      IF conflict
      THEN
        dup = TRUE;
      else
        dup = FALSE;
      END IF;
    ELSE
      IF NOT conflict
      THEN
        EXECUTE FORMAT (
          'NOTIFY %s'
          ,i.notify);
      END IF;
      dup = FALSE;
    END IF;
    RETURN NEXT (dup,uuid);
  END LOOP;

  RETURN;
END $$;
