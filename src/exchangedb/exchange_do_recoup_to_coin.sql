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




CREATE OR REPLACE FUNCTION exchange_do_recoup_to_coin(
  IN in_old_coin_pub BYTEA,
  IN in_rrc_serial INT8,
  IN in_coin_blind BYTEA,
  IN in_coin_pub BYTEA,
  IN in_known_coin_id INT8,
  IN in_coin_sig BYTEA,
  IN in_recoup_timestamp INT8,
  OUT out_recoup_ok BOOLEAN,
  OUT out_internal_failure BOOLEAN,
  OUT out_recoup_timestamp INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  rval RECORD;
DECLARE
  tmp taler_amount; -- amount recouped
BEGIN

-- Shards: UPDATE known_coins (by coin_pub)
--         SELECT recoup_refresh (by coin_pub)
--         UPDATE known_coins (by coin_pub)
--         INSERT recoup_refresh (by coin_pub)

out_internal_failure=FALSE;

-- Check remaining balance of the coin.
SELECT
   remaining
 INTO
   rval
FROM exchange.known_coins
  WHERE coin_pub=in_coin_pub;

IF NOT FOUND
THEN
  out_internal_failure=TRUE;
  out_recoup_ok=FALSE;
  RETURN;
END IF;

tmp := rval.remaining;

IF tmp.val + tmp.frac = 0
THEN
  -- Check for idempotency
  SELECT
      recoup_timestamp
    INTO
      out_recoup_timestamp
    FROM recoup_refresh
    WHERE coin_pub=in_coin_pub;
  out_recoup_ok=FOUND;
  RETURN;
END IF;

-- Update balance of the coin.
UPDATE known_coins
  SET
     remaining.val = 0
    ,remaining.frac = 0
  WHERE coin_pub=in_coin_pub;

-- Credit the old coin.
UPDATE known_coins kc
  SET
    remaining.frac=(kc.remaining).frac+tmp.frac
       - CASE
         WHEN (kc.remaining).frac+tmp.frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    remaining.val=(kc.remaining).val+tmp.val
       + CASE
         WHEN (kc.remaining).frac+tmp.frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_old_coin_pub;

IF NOT FOUND
THEN
  RAISE NOTICE 'failed to increase old coin balance from recoup';
  out_recoup_ok=TRUE;
  out_internal_failure=TRUE;
  RETURN;
END IF;


INSERT INTO recoup_refresh
  (coin_pub
  ,known_coin_id
  ,coin_sig
  ,coin_blind
  ,amount
  ,recoup_timestamp
  ,rrc_serial
  )
VALUES
  (in_coin_pub
  ,in_known_coin_id
  ,in_coin_sig
  ,in_coin_blind
  ,tmp
  ,in_recoup_timestamp
  ,in_rrc_serial);

-- Normal end, everything is fine.
out_recoup_ok=TRUE;
out_recoup_timestamp=in_recoup_timestamp;

END $$;


-- COMMENT ON FUNCTION exchange_do_recoup_to_coin(INT8, INT4, BYTEA, BOOLEAN, BOOLEAN)
--  IS 'Executes a recoup-refresh of a coin that was obtained from a refresh-reveal process';
