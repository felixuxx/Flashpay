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

CREATE OR REPLACE FUNCTION exchange_do_expire_purse(
  IN in_start_time INT8,
  IN in_end_time INT8,
  IN in_now INT8,
  OUT out_found BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  my_purse_pub BYTEA;
DECLARE
  my_deposit record;
DECLARE
  my_in_reserve_quota BOOLEAN;
BEGIN

-- FIXME: we should probably do this in a loop
-- and expire all at once, instead of one per query
SELECT purse_pub
      ,in_reserve_quota
  INTO my_purse_pub
      ,my_in_reserve_quota
  FROM purse_requests
 WHERE (purse_expiration >= in_start_time) AND
       (purse_expiration < in_end_time) AND
       NOT was_decided
  ORDER BY purse_expiration ASC
 LIMIT 1;
out_found = FOUND;
IF NOT FOUND
THEN
  RETURN;
END IF;

INSERT INTO purse_decision
  (purse_pub
  ,action_timestamp
  ,refunded)
VALUES
  (my_purse_pub
  ,in_now
  ,TRUE);

IF (my_in_reserve_quota)
THEN
  UPDATE reserves
    SET purses_active=purses_active-1
  WHERE reserve_pub IN
    (SELECT reserve_pub
       FROM exchange.purse_merges
      WHERE purse_pub=my_purse_pub
     LIMIT 1);
END IF;

-- restore balance to each coin deposited into the purse
FOR my_deposit IN
  SELECT coin_pub
        ,amount_with_fee
    FROM purse_deposits
  WHERE purse_pub = my_purse_pub
LOOP
  UPDATE known_coins kc SET
    remaining.frac=(kc.remaining).frac+(my_deposit.amount_with_fee).frac
     - CASE
       WHEN (kc.remaining).frac+(my_deposit.amount_with_fee).frac >= 100000000
       THEN 100000000
       ELSE 0
       END,
    remaining.val=(kc.remaining).val+(my_deposit.amount_with_fee).val
     + CASE
       WHEN (kc.remaining).frac+(my_deposit.amount_with_fee).frac >= 100000000
       THEN 1
       ELSE 0
       END
    WHERE coin_pub = my_deposit.coin_pub;
  END LOOP;
END $$;

COMMENT ON FUNCTION exchange_do_expire_purse(INT8,INT8,INT8)
  IS 'Finds an expired purse in the given time range and refunds the coins (if any).';
