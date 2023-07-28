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


CREATE OR REPLACE FUNCTION exchange_do_history_request(
  IN in_reserve_pub BYTEA,
  IN in_reserve_sig BYTEA,
  IN in_request_timestamp INT8,
  IN in_history_fee taler_amount,
  OUT out_balance_ok BOOLEAN,
  OUT out_idempotent BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  reserve RECORD;
  balance taler_amount;
  new_balance taler_amount;
BEGIN

  -- Insert and check for idempotency.
  INSERT INTO exchange.history_requests
  (reserve_pub
  ,request_timestamp
  ,reserve_sig
  ,history_fee_val
  ,history_fee_frac)
  VALUES
  (in_reserve_pub
  ,in_request_timestamp
  ,in_reserve_sig
  ,in_history_fee.val
  ,in_history_fee.frac)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    out_balance_ok=TRUE;
    out_idempotent=TRUE;
    RETURN;
  END IF;

  out_idempotent=FALSE;

  SELECT *
    INTO reserve
    FROM exchange.reserves
   WHERE reserve_pub=in_reserve_pub;

  IF NOT FOUND
  THEN
    -- Reserve does not exist, we treat it the same here
    -- as balance insufficient.
    out_balance_ok=FALSE;
    RETURN;
  END IF;

  balance = reserve.current_balance;

  -- check balance
  IF ( (balance.val <= in_history_fee.val) AND
       ( (balance.frac < in_history_fee.frac) OR
         (balance.val < in_history_fee.val) ) )
  THEN
    out_balance_ok=FALSE;
    RETURN;
  END IF;

  new_balance.frac=balance.frac-in_history_fee.frac
     + CASE
       WHEN balance.frac < in_history_fee.frac
       THEN 100000000
       ELSE 0
       END;
  new_balance.val=balance.val-in_history_fee.val
     - CASE
       WHEN balance.frac < in_history_fee.frac
       THEN 1
       ELSE 0
       END;

  -- Update reserve balance.
  UPDATE exchange.reserves
     SET current_balance=new_balance
   WHERE reserve_pub=in_reserve_pub;

  ASSERT FOUND, 'reserve suddenly disappeared';

  out_balance_ok=TRUE;

END $$;

