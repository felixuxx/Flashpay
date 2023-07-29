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


CREATE OR REPLACE FUNCTION exchange_do_reserve_open_deposit(
  IN in_coin_pub BYTEA,
  IN in_known_coin_id INT8,
  IN in_coin_sig BYTEA,
  IN in_reserve_sig BYTEA,
  IN in_reserve_pub BYTEA,
  IN in_coin_total taler_amount,
  OUT out_insufficient_funds BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN

INSERT INTO exchange.reserves_open_deposits
  (reserve_sig
  ,reserve_pub
  ,coin_pub
  ,coin_sig
  ,contribution
  )
  VALUES
  (in_reserve_sig
  ,in_reserve_pub
  ,in_coin_pub
  ,in_coin_sig
  ,in_coin_total
  )
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotent request known, return success.
  out_insufficient_funds=FALSE;
  RETURN;
END IF;


-- Check and update balance of the coin.
UPDATE exchange.known_coins kc
  SET
    remaining.frac=(kc.remaining).frac-in_coin_total.frac
       + CASE
         WHEN (kc.remaining).frac < in_coin_total.frac
         THEN 100000000
         ELSE 0
         END,
    remaining.val=(kc.remaining).val-in_coin_total.val
       - CASE
         WHEN (kc.remaining).frac < in_coin_total.frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub
    AND ( ((kc.remaining).val > in_coin_total.val) OR
          ( ((kc.remaining).frac >= in_coin_total.frac) AND
            ((kc.remaining).val >= in_coin_total.val) ) );

IF NOT FOUND
THEN
  -- Insufficient balance.
  out_insufficient_funds=TRUE;
  RETURN;
END IF;

-- Everything fine, return success!
out_insufficient_funds=FALSE;

END $$;
