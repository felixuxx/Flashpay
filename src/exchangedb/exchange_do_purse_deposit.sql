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

CREATE OR REPLACE FUNCTION exchange_do_purse_deposit(
  IN in_partner_id INT8,
  IN in_purse_pub BYTEA,
  IN in_amount_with_fee taler_amount,
  IN in_coin_pub BYTEA,
  IN in_coin_sig BYTEA,
  IN in_amount_without_fee taler_amount,
  IN in_reserve_expiration INT8,
  IN in_now INT8,
  OUT out_balance_ok BOOLEAN,
  OUT out_late BOOLEAN,
  OUT out_conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  was_merged BOOLEAN;
DECLARE
  psi INT8; -- partner's serial ID (set if merged)
DECLARE
  my_amount taler_amount; -- total in purse
DECLARE
  was_paid BOOLEAN;
DECLARE
  my_in_reserve_quota BOOLEAN;
DECLARE
  my_reserve_pub BYTEA;
DECLARE
  rval RECORD;
BEGIN

-- Store the deposit request.
INSERT INTO exchange.purse_deposits
  (partner_serial_id
  ,purse_pub
  ,coin_pub
  ,amount_with_fee
  ,coin_sig)
  VALUES
  (in_partner_id
  ,in_purse_pub
  ,in_coin_pub
  ,in_amount_with_fee
  ,in_coin_sig)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: check if coin_sig is the same,
  -- if so, success, otherwise conflict!

  PERFORM
  FROM exchange.purse_deposits
  WHERE coin_pub = in_coin_pub
    AND purse_pub = in_purse_pub
    AND coin_sig = in_coin_sig;
  IF NOT FOUND
  THEN
    -- Deposit exists, but with differences. Not allowed.
    out_balance_ok=FALSE;
    out_late=FALSE;
    out_conflict=TRUE;
    RETURN;
  ELSE
    -- Deposit exists, do not count for balance. Allow.
    out_late=FALSE;
    out_balance_ok=TRUE;
    out_conflict=FALSE;
    RETURN;
  END IF;
END IF;


-- Check if purse was deleted, if so, abort and prevent deposit.
PERFORM
  FROM exchange.purse_deletion
  WHERE purse_pub = in_purse_pub;
IF FOUND
THEN
  out_late=TRUE;
  out_balance_ok=FALSE;
  out_conflict=FALSE;
  RETURN;
END IF;


-- Debit the coin
-- Check and update balance of the coin.
UPDATE known_coins kc
  SET
    remaining.frac=(kc.remaining).frac-in_amount_with_fee.frac
       + CASE
         WHEN (kc.remaining).frac < in_amount_with_fee.frac
         THEN 100000000
         ELSE 0
         END,
    remaining.val=(kc.remaining).val-in_amount_with_fee.val
       - CASE
         WHEN (kc.remaining).frac < in_amount_with_fee.frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub
    AND ( ((kc.remaining).val > in_amount_with_fee.val) OR
          ( ((kc.remaining).frac >= in_amount_with_fee.frac) AND
            ((kc.remaining).val >= in_amount_with_fee.val) ) );

IF NOT FOUND
THEN
  -- Insufficient balance.
  out_balance_ok=FALSE;
  out_late=FALSE;
  out_conflict=FALSE;
  RETURN;
END IF;


-- Credit the purse.
UPDATE purse_requests pr
  SET
    balance.frac=(pr.balance).frac+in_amount_without_fee.frac
       - CASE
         WHEN (pr.balance).frac+in_amount_without_fee.frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    balance.val=(pr.balance).val+in_amount_without_fee.val
       + CASE
         WHEN (pr.balance).frac+in_amount_without_fee.frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE purse_pub=in_purse_pub;

out_conflict=FALSE;
out_balance_ok=TRUE;

-- See if we can finish the merge or need to update the trigger time and partner.
SELECT COALESCE(partner_serial_id,0)
      ,reserve_pub
  INTO psi
      ,my_reserve_pub
  FROM exchange.purse_merges
 WHERE purse_pub=in_purse_pub;

IF NOT FOUND
THEN
  -- Purse was not yet merged.  We are done.
  out_late=FALSE;
  RETURN;
END IF;

SELECT
    amount_with_fee
   ,in_reserve_quota
  INTO
    rval
  FROM exchange.purse_requests preq
  WHERE (purse_pub=in_purse_pub)
    AND ( ( ( ((preq.amount_with_fee).val <= (preq.balance).val)
          AND ((preq.amount_with_fee).frac <= (preq.balance).frac) )
         OR ((preq.amount_with_fee).val < (preq.balance).val) ) );
IF NOT FOUND
THEN
  out_late=FALSE;
  RETURN;
END IF;

-- We use rval as workaround as we cannot select
-- directly into the amount due to Postgres limitations.
my_amount := rval.amount_with_fee;
my_in_reserve_quota := rval.in_reserve_quota;

-- Remember how this purse was finished.
INSERT INTO purse_decision
  (purse_pub
  ,action_timestamp
  ,refunded)
VALUES
  (in_purse_pub
  ,in_now
  ,FALSE)
ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Purse already decided, likely expired.
  out_late=TRUE;
  RETURN;
END IF;

out_late=FALSE;

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


IF (0 != psi)
THEN
  -- The taler-exchange-router will take care of this.
  UPDATE purse_actions
     SET action_date=0 --- "immediately"
        ,partner_serial_id=psi
   WHERE purse_pub=in_purse_pub;
ELSE
  -- This is a local reserve, update balance immediately.
  INSERT INTO reserves
    (reserve_pub
    ,current_balance
    ,expiration_date
    ,gc_date)
  VALUES
    (my_reserve_pub
    ,my_amount
    ,in_reserve_expiration
    ,in_reserve_expiration)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    -- Reserve existed, thus UPDATE instead of INSERT.
    UPDATE reserves
      SET
       current_balance.frac=(current_balance).frac+my_amount.frac
        - CASE
          WHEN (current_balance).frac + my_amount.frac >= 100000000
            THEN 100000000
          ELSE 0
          END
      ,current_balance.val=(current_balance).val+my_amount.val
        + CASE
          WHEN (current_balance).frac + my_amount.frac >= 100000000
            THEN 1
          ELSE 0
          END
      ,expiration_date=GREATEST(expiration_date,in_reserve_expiration)
      ,gc_date=GREATEST(gc_date,in_reserve_expiration)
      WHERE reserve_pub=my_reserve_pub;
  END IF;

END IF;


END $$;
