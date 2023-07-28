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


CREATE OR REPLACE FUNCTION exchange_do_recoup_to_reserve(
  IN in_reserve_pub BYTEA,
  IN in_reserve_out_serial_id INT8,
  IN in_coin_blind BYTEA,
  IN in_coin_pub BYTEA,
  IN in_known_coin_id INT8,
  IN in_coin_sig BYTEA,
  IN in_reserve_gc INT8,
  IN in_reserve_expiration INT8,
  IN in_recoup_timestamp INT8,
  OUT out_recoup_ok BOOLEAN,
  OUT out_internal_failure BOOLEAN,
  OUT out_recoup_timestamp INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  tmp taler_amount; -- amount recouped
  balance taler_amount; -- current balance of the reserve
  new_balance taler_amount; -- new balance of the reserve
  reserve RECORD;
BEGIN
-- Shards: SELECT known_coins (by coin_pub)
--         SELECT recoup      (by coin_pub)
--         UPDATE known_coins (by coin_pub)
--         UPDATE reserves (by reserve_pub)
--         INSERT recoup      (by coin_pub)

out_internal_failure=FALSE;


-- Check remaining balance of the coin.
SELECT
   remaining_frac
  ,remaining_val
 INTO
   tmp.frac
  ,tmp.val
FROM exchange.known_coins
  WHERE coin_pub=in_coin_pub;

IF NOT FOUND
THEN
  out_internal_failure=TRUE;
  out_recoup_ok=FALSE;
  RETURN;
END IF;

IF tmp.val + tmp.frac = 0
THEN
  -- Check for idempotency
  SELECT
    recoup_timestamp
  INTO
    out_recoup_timestamp
    FROM exchange.recoup
    WHERE coin_pub=in_coin_pub;

  out_recoup_ok=FOUND;
  RETURN;
END IF;


-- Update balance of the coin.
UPDATE known_coins
  SET
     remaining_frac=0
    ,remaining_val=0
  WHERE coin_pub=in_coin_pub;

-- Get current balance
SELECT *
  INTO reserve
  FROM reserves
 WHERE reserve_pub=in_reserve_pub;

balance = reserve.current_balance;
new_balance.frac=balance.frac+tmp.frac
   - CASE
     WHEN balance.frac+tmp.frac >= 100000000
     THEN 100000000
     ELSE 0
     END;

new_balance.val=balance.val+tmp.val
   + CASE
     WHEN balance.frac+tmp.frac >= 100000000
     THEN 1
     ELSE 0
     END;

-- Credit the reserve and update reserve timers.
UPDATE reserves
  SET
    current_balance = new_balance,
    gc_date=GREATEST(gc_date, in_reserve_gc),
    expiration_date=GREATEST(expiration_date, in_reserve_expiration)
  WHERE reserve_pub=in_reserve_pub;


IF NOT FOUND
THEN
  RAISE NOTICE 'failed to increase reserve balance from recoup';
  out_recoup_ok=TRUE;
  out_internal_failure=TRUE;
  RETURN;
END IF;


INSERT INTO exchange.recoup
  (coin_pub
  ,coin_sig
  ,coin_blind
  ,amount_val
  ,amount_frac
  ,recoup_timestamp
  ,reserve_out_serial_id
  )
VALUES
  (in_coin_pub
  ,in_coin_sig
  ,in_coin_blind
  ,tmp.val
  ,tmp.frac
  ,in_recoup_timestamp
  ,in_reserve_out_serial_id);

-- Normal end, everything is fine.
out_recoup_ok=TRUE;
out_recoup_timestamp=in_recoup_timestamp;

END $$;

-- COMMENT ON FUNCTION exchange_do_recoup_to_reserve(INT8, INT4, BYTEA, BOOLEAN, BOOLEAN)
--  IS 'Executes a recoup of a coin that was withdrawn from a reserve';



