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

CREATE OR REPLACE FUNCTION exchange_do_purse_merge(
  IN in_purse_pub BYTEA,
  IN in_merge_sig BYTEA,
  IN in_merge_timestamp INT8,
  IN in_reserve_sig BYTEA,
  IN in_partner_url VARCHAR,
  IN in_reserve_pub BYTEA,
  IN in_wallet_h_payto BYTEA,
  IN in_expiration_date INT8,
  OUT out_no_partner BOOLEAN,
  OUT out_no_balance BOOLEAN,
  OUT out_conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  my_amount_val INT8;
DECLARE
  my_amount_frac INT4;
DECLARE
  my_purse_fee_val INT8;
DECLARE
  my_purse_fee_frac INT4;
DECLARE
  my_partner_serial_id INT8;
DECLARE
  my_in_reserve_quota BOOLEAN;
BEGIN


IF in_partner_url IS NULL
THEN
  my_partner_serial_id=NULL;
ELSE
  SELECT
    partner_serial_id
  INTO
    my_partner_serial_id
  FROM exchange.partners
  WHERE partner_base_url=in_partner_url
    AND start_date <= in_merge_timestamp
    AND end_date > in_merge_timestamp;
  IF NOT FOUND
  THEN
    out_no_partner=TRUE;
    out_conflict=FALSE;
    RETURN;
  END IF;
END IF;

out_no_partner=FALSE;


-- Check purse is 'full'.
SELECT amount_with_fee_val
      ,amount_with_fee_frac
      ,purse_fee_val
      ,purse_fee_frac
      ,in_reserve_quota
  INTO my_amount_val
      ,my_amount_frac
      ,my_purse_fee_val
      ,my_purse_fee_frac
      ,my_in_reserve_quota
  FROM exchange.purse_requests
  WHERE purse_pub=in_purse_pub
    AND balance_val >= amount_with_fee_val
    AND ( (balance_frac >= amount_with_fee_frac) OR
          (balance_val > amount_with_fee_val) );
IF NOT FOUND
THEN
  out_no_balance=TRUE;
  out_conflict=FALSE;
  RETURN;
END IF;
out_no_balance=FALSE;

-- Store purse merge signature, checks for purse_pub uniqueness
INSERT INTO exchange.purse_merges
    (partner_serial_id
    ,reserve_pub
    ,purse_pub
    ,merge_sig
    ,merge_timestamp)
  VALUES
    (my_partner_serial_id
    ,in_reserve_pub
    ,in_purse_pub
    ,in_merge_sig
    ,in_merge_timestamp)
  ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Idempotency check: see if an identical record exists.
  -- Note that by checking 'merge_sig', we implicitly check
  -- identity over everything that the signature covers.
  PERFORM
  FROM exchange.purse_merges
  WHERE purse_pub=in_purse_pub
     AND merge_sig=in_merge_sig;
  IF NOT FOUND
  THEN
     -- Purse was merged, but to some other reserve. Not allowed.
     out_conflict=TRUE;
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  RETURN;
END IF;


-- Remember how this purse was finished. This will conflict
-- if the purse was already decided previously.
INSERT INTO purse_decision
  (purse_pub
  ,action_timestamp
  ,refunded)
VALUES
  (in_purse_pub
  ,in_merge_timestamp
  ,FALSE)
ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Purse was already decided (possibly deleted or merged differently).
  out_conflict=TRUE;
  RETURN;
END IF;

out_conflict=FALSE;


-- Initialize reserve, if not yet exists.
INSERT INTO reserves
  (reserve_pub
  ,expiration_date
  ,gc_date)
  VALUES
  (in_reserve_pub
  ,in_expiration_date
  ,in_expiration_date)
  ON CONFLICT DO NOTHING;


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

-- Store account merge signature.
INSERT INTO exchange.account_merges
  (reserve_pub
  ,reserve_sig
  ,purse_pub
  ,wallet_h_payto)
  VALUES
  (in_reserve_pub
  ,in_reserve_sig
  ,in_purse_pub
  ,in_wallet_h_payto);

-- If we need a wad transfer, mark purse ready for it.
IF (0 != my_partner_serial_id)
THEN
  -- The taler-exchange-router will take care of this.
  UPDATE purse_actions
     SET action_date=0 --- "immediately"
        ,partner_serial_id=my_partner_serial_id
   WHERE purse_pub=in_purse_pub;
ELSE
  -- This is a local reserve, update reserve balance immediately.

  -- Refund the purse fee, by adding it to the purse value:
  my_amount_val = my_amount_val + my_purse_fee_val;
  my_amount_frac = my_amount_frac + my_purse_fee_frac;
  -- normalize result
  my_amount_val = my_amount_val + my_amount_frac / 100000000;
  my_amount_frac = my_amount_frac % 100000000;

  UPDATE exchange.reserves
  SET
    current_balance_frac=current_balance_frac+my_amount_frac
       - CASE
         WHEN current_balance_frac + my_amount_frac >= 100000000
         THEN 100000000
         ELSE 0
         END,
    current_balance_val=current_balance_val+my_amount_val
       + CASE
         WHEN current_balance_frac + my_amount_frac >= 100000000
         THEN 1
         ELSE 0
         END
  WHERE reserve_pub=in_reserve_pub;

END IF;

RETURN;

END $$;

COMMENT ON FUNCTION exchange_do_purse_merge(BYTEA, BYTEA, INT8, BYTEA, VARCHAR, BYTEA, BYTEA, INT8)
  IS 'Checks that the partner exists, the purse has not been merged with a different reserve and that the purse is full. If so, persists the merge data and either merges the purse with the reserve or marks it as ready for the taler-exchange-router. Caller MUST abort the transaction on failures so as to not persist data by accident.';

