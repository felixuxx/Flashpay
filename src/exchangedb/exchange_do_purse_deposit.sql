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
  IN in_amount_with_fee_val INT8,
  IN in_amount_with_fee_frac INT4,
  IN in_coin_pub BYTEA,
  IN in_coin_sig BYTEA,
  IN in_amount_without_fee_val INT8,
  IN in_amount_without_fee_frac INT4,
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
  my_amount_val INT8; -- total in purse
DECLARE
  my_amount_frac INT4; -- total in purse
DECLARE
  was_paid BOOLEAN;
DECLARE
  my_in_reserve_quota BOOLEAN;
DECLARE
  my_reserve_pub BYTEA;
BEGIN

-- Store the deposit request.
INSERT INTO exchange.purse_deposits
  (partner_serial_id
  ,purse_pub
  ,coin_pub
  ,amount_with_fee_val
  ,amount_with_fee_frac
  ,coin_sig)
  VALUES
  (in_partner_id
  ,in_purse_pub
  ,in_coin_pub
  ,in_amount_with_fee_val
  ,in_amount_with_fee_frac
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
    AND coin_sig = in_cion_sig;
  IF NOT FOUND
  THEN
    -- Deposit exists, but with differences. Not allowed.
    out_balance_ok=FALSE;
    out_late=FALSE;
    out_conflict=TRUE;
    RETURN;
  END IF;
END IF;


-- Debit the coin
-- Check and update balance of the coin.
UPDATE known_coins
  SET
    remaining_frac=remaining_frac-in_amount_with_fee_frac
       + CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 100000000
         ELSE 0
         END,
    remaining_val=remaining_val-in_amount_with_fee_val
       - CASE
         WHEN remaining_frac < in_amount_with_fee_frac
         THEN 1
         ELSE 0
         END
  WHERE coin_pub=in_coin_pub
    AND ( (remaining_val > in_amount_with_fee_val) OR
          ( (remaining_frac >= in_amount_with_fee_frac) AND
            (remaining_val >= in_amount_with_fee_val) ) );

IF NOT FOUND
THEN
  -- Insufficient balance.
  out_balance_ok=FALSE;
  out_late=FALSE;
  out_conflict=FALSE;
  RETURN;
END IF;


-- Credit the purse.
UPDATE purse_requests
  SET
    balance_frac=balance_frac+in_amount_without_fee_frac
       - CASE
         WHEN balance_frac+in_amount_without_fee_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    balance_val=balance_val+in_amount_without_fee_val
       + CASE
         WHEN balance_frac+in_amount_without_fee_frac >= 100000000
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
    amount_with_fee_val
   ,amount_with_fee_frac
   ,in_reserve_quota
  INTO
    my_amount_val
   ,my_amount_frac
   ,my_in_reserve_quota
  FROM exchange.purse_requests
  WHERE (purse_pub=in_purse_pub)
    AND ( ( ( (amount_with_fee_val <= balance_val)
          AND (amount_with_fee_frac <= balance_frac) )
         OR (amount_with_fee_val < balance_val) ) );
IF NOT FOUND
THEN
  out_late=FALSE;
  RETURN;
END IF;

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
    ,current_balance_frac
    ,current_balance_val
    ,expiration_date
    ,gc_date)
  VALUES
    (my_reserve_pub
    ,my_amount_frac
    ,my_amount_val
    ,in_reserve_expiration
    ,in_reserve_expiration)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    -- Reserve existed, thus UPDATE instead of INSERT.
    UPDATE reserves
      SET
       current_balance_frac=current_balance_frac+my_amount_frac
        - CASE
          WHEN current_balance_frac + my_amount_frac >= 100000000
            THEN 100000000
          ELSE 0
          END
      ,current_balance_val=current_balance_val+my_amount_val
        + CASE
          WHEN current_balance_frac + my_amount_frac >= 100000000
            THEN 1
          ELSE 0
          END
      ,expiration_date=GREATEST(expiration_date,in_reserve_expiration)
      ,gc_date=GREATEST(gc_date,in_reserve_expiration)
      WHERE reserve_pub=my_reserve_pub;
  END IF;

END IF;


END $$;
