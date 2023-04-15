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

CREATE OR REPLACE FUNCTION exchange_do_batch4_known_coin(
  IN in_coin_pub1 BYTEA,
  IN in_denom_pub_hash1 BYTEA,
  IN in_h_age_commitment1 BYTEA,
  IN in_denom_sig1 BYTEA,
  IN in_coin_pub2 BYTEA,
  IN in_denom_pub_hash2 BYTEA,
  IN in_h_age_commitment2 BYTEA,
  IN in_denom_sig2 BYTEA,
  IN in_coin_pub3 BYTEA,
  IN in_denom_pub_hash3 BYTEA,
  IN in_h_age_commitment3 BYTEA,
  IN in_denom_sig3 BYTEA,
  IN in_coin_pub4 BYTEA,
  IN in_denom_pub_hash4 BYTEA,
  IN in_h_age_commitment4 BYTEA,
  IN in_denom_sig4 BYTEA,
  OUT existed1 BOOLEAN,
  OUT existed2 BOOLEAN,
  OUT existed3 BOOLEAN,
  OUT existed4 BOOLEAN,
  OUT known_coin_id1 INT8,
  OUT known_coin_id2 INT8,
  OUT known_coin_id3 INT8,
  OUT known_coin_id4 INT8,
  OUT denom_pub_hash1 BYTEA,
  OUT denom_pub_hash2 BYTEA,
  OUT denom_pub_hash3 BYTEA,
  OUT denom_pub_hash4 BYTEA,
  OUT age_commitment_hash1 BYTEA,
  OUT age_commitment_hash2 BYTEA,
  OUT age_commitment_hash3 BYTEA,
  OUT age_commitment_hash4 BYTEA)
LANGUAGE plpgsql
AS $$
BEGIN
WITH dd AS (
SELECT
  denominations_serial,
  coin_val, coin_frac
  FROM denominations
    WHERE denom_pub_hash
    IN
     (in_denom_pub_hash1,
      in_denom_pub_hash2,
      in_denom_pub_hash3,
      in_denom_pub_hash4)
     ),--dd
     input_rows AS (
     VALUES
      (in_coin_pub1,
      in_denom_pub_hash1,
      in_h_age_commitment1,
      in_denom_sig1),
      (in_coin_pub2,
      in_denom_pub_hash2,
      in_h_age_commitment2,
      in_denom_sig2),
      (in_coin_pub3,
      in_denom_pub_hash3,
      in_h_age_commitment3,
      in_denom_sig3),
      (in_coin_pub4,
      in_denom_pub_hash4,
      in_h_age_commitment4,
      in_denom_sig4)
      ),--ir
      ins AS (
      INSERT INTO known_coins (
      coin_pub,
      denominations_serial,
      age_commitment_hash,
      denom_sig,
      remaining_val,
      remaining_frac
      )
      SELECT
        ir.coin_pub,
        dd.denominations_serial,
        ir.age_commitment_hash,
        ir.denom_sig,
        dd.coin_val,
        dd.coin_frac
        FROM input_rows ir
        JOIN dd
          ON dd.denom_pub_hash = ir.denom_pub_hash
          ON CONFLICT DO NOTHING
          RETURNING known_coin_id
      ),--kc
       exists AS (
         SELECT
         CASE
           WHEN
             ins.known_coin_id IS NOT NULL
             THEN
               FALSE
             ELSE
               TRUE
         END AS existed,
         ins.known_coin_id,
         dd.denom_pub_hash,
         kc.age_commitment_hash
         FROM input_rows ir
         LEFT JOIN ins
           ON ins.coin_pub = ir.coin_pub
         LEFT JOIN known_coins kc
           ON kc.coin_pub = ir.coin_pub
         LEFT JOIN dd
           ON dd.denom_pub_hash = ir.denom_pub_hash
         )--exists
SELECT
 exists.existed AS existed1,
 exists.known_coin_id AS known_coin_id1,
 exists.denom_pub_hash AS denom_pub_hash1,
 exists.age_commitment_hash AS age_commitment_hash1,
 (
   SELECT exists.existed
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash2
 ) AS existed2,
 (
   SELECT exists.known_coin_id
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash2
 ) AS known_coin_id2,
 (
   SELECT exists.denom_pub_hash
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash2
 ) AS denom_pub_hash2,
 (
   SELECT exists.age_commitment_hash
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash2
 )AS age_commitment_hash2,
 (
   SELECT exists.existed
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash3
 ) AS existed3,
 (
   SELECT exists.known_coin_id
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash3
 ) AS known_coin_id3,
 (
   SELECT exists.denom_pub_hash
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash3
 ) AS denom_pub_hash3,
 (
   SELECT exists.age_commitment_hash
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash3
 )AS age_commitment_hash3,
 (
   SELECT exists.existed
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash4
 ) AS existed4,
 (
   SELECT exists.known_coin_id
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash4
 ) AS known_coin_id4,
 (
   SELECT exists.denom_pub_hash
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash4
 ) AS denom_pub_hash4,
 (
   SELECT exists.age_commitment_hash
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash4
 )AS age_commitment_hash4
FROM exists;

RETURN;
END $$;


CREATE OR REPLACE FUNCTION exchange_do_batch2_known_coin(
  IN in_coin_pub1 BYTEA,
  IN in_denom_pub_hash1 BYTEA,
  IN in_h_age_commitment1 BYTEA,
  IN in_denom_sig1 BYTEA,
  IN in_coin_pub2 BYTEA,
  IN in_denom_pub_hash2 BYTEA,
  IN in_h_age_commitment2 BYTEA,
  IN in_denom_sig2 BYTEA,
  OUT existed1 BOOLEAN,
  OUT existed2 BOOLEAN,
  OUT known_coin_id1 INT8,
  OUT known_coin_id2 INT8,
  OUT denom_pub_hash1 BYTEA,
  OUT denom_pub_hash2 BYTEA,
  OUT age_commitment_hash1 BYTEA,
  OUT age_commitment_hash2 BYTEA)
LANGUAGE plpgsql
AS $$
BEGIN
WITH dd AS (
SELECT
  denominations_serial,
  coin_val, coin_frac
  FROM denominations
    WHERE denom_pub_hash
    IN
     (in_denom_pub_hash1,
      in_denom_pub_hash2)
     ),--dd
     input_rows AS (
     VALUES
      (in_coin_pub1,
      in_denom_pub_hash1,
      in_h_age_commitment1,
      in_denom_sig1),
      (in_coin_pub2,
      in_denom_pub_hash2,
      in_h_age_commitment2,
      in_denom_sig2)
      ),--ir
      ins AS (
      INSERT INTO known_coins (
      coin_pub,
      denominations_serial,
      age_commitment_hash,
      denom_sig,
      remaining_val,
      remaining_frac
      )
      SELECT
        ir.coin_pub,
        dd.denominations_serial,
        ir.age_commitment_hash,
        ir.denom_sig,
        dd.coin_val,
        dd.coin_frac
        FROM input_rows ir
        JOIN dd
          ON dd.denom_pub_hash = ir.denom_pub_hash
          ON CONFLICT DO NOTHING
          RETURNING known_coin_id
      ),--kc
       exists AS (
       SELECT
        CASE
          WHEN ins.known_coin_id IS NOT NULL
          THEN
            FALSE
          ELSE
            TRUE
        END AS existed,
        ins.known_coin_id,
        dd.denom_pub_hash,
        kc.age_commitment_hash
        FROM input_rows ir
        LEFT JOIN ins
          ON ins.coin_pub = ir.coin_pub
        LEFT JOIN known_coins kc
          ON kc.coin_pub = ir.coin_pub
        LEFT JOIN dd
          ON dd.denom_pub_hash = ir.denom_pub_hash
     )--exists
SELECT
 exists.existed AS existed1,
 exists.known_coin_id AS known_coin_id1,
 exists.denom_pub_hash AS denom_pub_hash1,
 exists.age_commitment_hash AS age_commitment_hash1,
 (
   SELECT exists.existed
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash2
 ) AS existed2,
 (
   SELECT exists.known_coin_id
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash2
 ) AS known_coin_id2,
 (
   SELECT exists.denom_pub_hash
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash2
 ) AS denom_pub_hash2,
 (
   SELECT exists.age_commitment_hash
   FROM exists
   WHERE exists.denom_pub_hash = in_denom_pub_hash2
 )AS age_commitment_hash2
FROM exists;

RETURN;
END $$;


CREATE OR REPLACE FUNCTION exchange_do_batch1_known_coin(
  IN in_coin_pub1 BYTEA,
  IN in_denom_pub_hash1 BYTEA,
  IN in_h_age_commitment1 BYTEA,
  IN in_denom_sig1 BYTEA,
  OUT existed1 BOOLEAN,
  OUT known_coin_id1 INT8,
  OUT denom_pub_hash1 BYTEA,
  OUT age_commitment_hash1 BYTEA)
LANGUAGE plpgsql
AS $$
BEGIN
WITH dd AS (
SELECT
  denominations_serial,
  coin_val, coin_frac
  FROM denominations
    WHERE denom_pub_hash
    IN
     (in_denom_pub_hash1,
      in_denom_pub_hash2)
     ),--dd
     input_rows AS (
     VALUES
      (in_coin_pub1,
      in_denom_pub_hash1,
      in_h_age_commitment1,
      in_denom_sig1)
      ),--ir
      ins AS (
      INSERT INTO known_coins (
      coin_pub,
      denominations_serial,
      age_commitment_hash,
      denom_sig,
      remaining_val,
      remaining_frac
      )
      SELECT
        ir.coin_pub,
        dd.denominations_serial,
        ir.age_commitment_hash,
        ir.denom_sig,
        dd.coin_val,
        dd.coin_frac
        FROM input_rows ir
        JOIN dd
          ON dd.denom_pub_hash = ir.denom_pub_hash
          ON CONFLICT DO NOTHING
          RETURNING known_coin_id
      ),--kc
       exists AS (
       SELECT
        CASE
          WHEN ins.known_coin_id IS NOT NULL
          THEN
            FALSE
          ELSE
            TRUE
        END AS existed,
        ins.known_coin_id,
        dd.denom_pub_hash,
        kc.age_commitment_hash
        FROM input_rows ir
        LEFT JOIN ins
          ON ins.coin_pub = ir.coin_pub
        LEFT JOIN known_coins kc
          ON kc.coin_pub = ir.coin_pub
        LEFT JOIN dd
          ON dd.denom_pub_hash = ir.denom_pub_hash
       )--exists
SELECT
 exists.existed AS existed1,
 exists.known_coin_id AS known_coin_id1,
 exists.denom_pub_hash AS denom_pub_hash1,
 exists.age_commitment_hash AS age_commitment_hash1
FROM exists;

RETURN;
END $$;

/*** Experiment using a loop ***/
/*
CREATE OR REPLACE FUNCTION exchange_do_batch2_known_coin(
  IN in_coin_pub1 BYTEA,
  IN in_denom_pub_hash1 TEXT,
  IN in_h_age_commitment1 TEXT,
  IN in_denom_sig1 TEXT,
  IN in_coin_pub2 BYTEA,
  IN in_denom_pub_hash2 TEXT,
  IN in_h_age_commitment2 TEXT,
  IN in_denom_sig2 TEXT,
  OUT existed1 BOOLEAN,
  OUT existed2 BOOLEAN,
  OUT known_coin_id1 INT8,
  OUT known_coin_id2 INT8,
  OUT denom_pub_hash1 TEXT,
  OUT denom_pub_hash2 TEXT,
  OUT age_commitment_hash1 TEXT,
  OUT age_commitment_hash2 TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
  ins_values RECORD;
BEGIN
  FOR i IN 1..2 LOOP
    ins_values := (
      SELECT
        in_coin_pub1 AS coin_pub,
        in_denom_pub_hash1 AS denom_pub_hash,
        in_h_age_commitment1 AS age_commitment_hash,
        in_denom_sig1 AS denom_sig
      WHERE i = 1
      UNION
      SELECT
        in_coin_pub2 AS coin_pub,
        in_denom_pub_hash2 AS denom_pub_hash,
        in_h_age_commitment2 AS age_commitment_hash,
        in_denom_sig2 AS denom_sig
      WHERE i = 2
    );
    WITH dd (denominations_serial, coin_val, coin_frac) AS (
      SELECT denominations_serial, coin_val, coin_frac
      FROM denominations
      WHERE denom_pub_hash = ins_values.denom_pub_hash
    ),
    input_rows(coin_pub) AS (
      VALUES (ins_values.coin_pub)
    ),
    ins AS (
      INSERT INTO known_coins (
        coin_pub,
        denominations_serial,
        age_commitment_hash,
        denom_sig,
        remaining_val,
        remaining_frac
      ) SELECT
        input_rows.coin_pub,
        dd.denominations_serial,
        ins_values.age_commitment_hash,
        ins_values.denom_sig,
        coin_val,
        coin_frac
      FROM dd
      CROSS JOIN input_rows
      ON CONFLICT DO NOTHING
      RETURNING known_coin_id, denom_pub_hash
    )
    SELECT
      CASE i
        WHEN 1 THEN
          COALESCE(ins.known_coin_id, 0) <> 0 AS existed1,
          ins.known_coin_id AS known_coin_id1,
          ins.denom_pub_hash AS denom_pub_hash1,
          ins.age_commitment_hash AS age_commitment_hash1
        WHEN 2 THEN
          COALESCE(ins.known_coin_id, 0) <> 0 AS existed2,
          ins.known_coin_id AS known_coin_id2,
          ins.denom_pub_hash AS denom_pub_hash2,
          ins.age_commitment_hash AS age_commitment_hash2
      END
    FROM ins;
  END LOOP;
END;
$$;*/
