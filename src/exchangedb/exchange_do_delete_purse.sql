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

CREATE OR REPLACE FUNCTION exchange_do_delete_purse(
  IN in_purse_pub BYTEA,
  IN in_purse_sig BYTEA,
  IN in_now INT8,
  OUT out_decided BOOLEAN,
  OUT out_found BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  my_deposit record;
DECLARE
  my_in_reserve_quota BOOLEAN;
BEGIN

SELECT COUNT(*) FROM purse_decision
  WHERE purse_pub=in_purse_pub;
IF FOUND
THEN
  out_found=TRUE;
  out_decided=TRUE;
  RETURN;
END IF;
out_decided=FALSE;

SELECT in_reserve_quota
  INTO my_in_reserve_quota
  FROM exchange.purse_requests
 WHERE purse_pub=in_purse_pub;
out_found=FOUND;
IF NOT FOUND
THEN
  RETURN;
END IF;

-- store reserve deletion
INSERT INTO purse_deletion
  (purse_pub
  ,purse_sig)
VALUES
  (in_purse_pub
  ,in_purse_sig)
ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  RETURN;
END IF;

-- store purse decision
INSERT INTO purse_decision
  (purse_pub
  ,action_timestamp
  ,refunded)
VALUES
  (in_purse_pub
  ,in_now
  ,TRUE);

-- update purse quota at reserve
IF (my_in_reserve_quota)
THEN
  UPDATE reserves
    SET purses_active=purses_active-1
  WHERE reserve_pub IN
    (SELECT reserve_pub
       FROM exchange.purse_merges
      WHERE purse_pub=in_purse_pub
     LIMIT 1);
END IF;

-- restore balance to each coin deposited into the purse
FOR my_deposit IN
  SELECT coin_pub
        ,amount_with_fee_val
        ,amount_with_fee_frac
    FROM exchange.purse_deposits
  WHERE purse_pub = in_purse_pub
LOOP
  UPDATE exchange.known_coins SET
    remaining_frac=remaining_frac+my_deposit.amount_with_fee_frac
     - CASE
       WHEN remaining_frac+my_deposit.amount_with_fee_frac >= 100000000
       THEN 100000000
       ELSE 0
       END,
    remaining_val=remaining_val+my_deposit.amount_with_fee_val
     + CASE
       WHEN remaining_frac+my_deposit.amount_with_fee_frac >= 100000000
       THEN 1
       ELSE 0
       END
    WHERE coin_pub = my_deposit.coin_pub;
END LOOP;


END $$;

COMMENT ON FUNCTION exchange_do_delete_purse(BYTEA,BYTEA,INT8)
  IS 'Delete a previously undecided purse and refund the coins (if any).';
