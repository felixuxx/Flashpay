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

CREATE OR REPLACE FUNCTION exchange_do_reserve_purse(
  IN in_purse_pub BYTEA,
  IN in_merge_sig BYTEA,
  IN in_merge_timestamp INT8,
  IN in_reserve_expiration INT8,
  IN in_reserve_gc INT8,
  IN in_reserve_sig BYTEA,
  IN in_reserve_quota BOOLEAN,
  IN in_purse_fee_val INT8,
  IN in_purse_fee_frac INT4,
  IN in_reserve_pub BYTEA,
  IN in_wallet_h_payto BYTEA,
  OUT out_no_funds BOOLEAN,
  OUT out_no_reserve BOOLEAN,
  OUT out_conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN

-- Store purse merge signature, checks for purse_pub uniqueness
INSERT INTO exchange.purse_merges
    (partner_serial_id
    ,reserve_pub
    ,purse_pub
    ,merge_sig
    ,merge_timestamp)
  VALUES
    (NULL
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
     out_no_reserve=FALSE;
     out_no_funds=FALSE;
     RETURN;
  END IF;

  -- "success"
  out_conflict=FALSE;
  out_no_funds=FALSE;
  out_no_reserve=FALSE;
  RETURN;
END IF;
out_conflict=FALSE;

PERFORM
  FROM exchange.reserves
 WHERE reserve_pub=in_reserve_pub;

out_no_reserve = NOT FOUND;

IF (in_reserve_quota)
THEN
  -- Increment active purses per reserve (and check this is allowed)
  IF (out_no_reserve)
  THEN
    out_no_funds=TRUE;
    RETURN;
  END IF;
  UPDATE exchange.reserves
     SET purses_active=purses_active+1
   WHERE reserve_pub=in_reserve_pub
     AND purses_active < purses_allowed;
  IF NOT FOUND
  THEN
    out_no_funds=TRUE;
    RETURN;
  END IF;
ELSE
  --  UPDATE reserves balance (and check if balance is enough to pay the fee)
  IF (out_no_reserve)
  THEN
    IF ( (0 != in_purse_fee_val) OR
         (0 != in_purse_fee_frac) )
    THEN
      out_no_funds=TRUE;
      RETURN;
    END IF;
    INSERT INTO exchange.reserves
      (reserve_pub
      ,expiration_date
      ,gc_date)
    VALUES
      (in_reserve_pub
      ,in_reserve_expiration
      ,in_reserve_gc);
  ELSE
    UPDATE exchange.reserves
      SET
        current_balance_frac=current_balance_frac-in_purse_fee_frac
         + CASE
         WHEN current_balance_frac < in_purse_fee_frac
         THEN 100000000
         ELSE 0
         END,
       current_balance_val=current_balance_val-in_purse_fee_val
         - CASE
         WHEN current_balance_frac < in_purse_fee_frac
         THEN 1
         ELSE 0
         END
      WHERE reserve_pub=in_reserve_pub
        AND ( (current_balance_val > in_purse_fee_val) OR
              ( (current_balance_frac >= in_purse_fee_frac) AND
                (current_balance_val >= in_purse_fee_val) ) );
    IF NOT FOUND
    THEN
      out_no_funds=TRUE;
      RETURN;
    END IF;
  END IF;
END IF;

out_no_funds=FALSE;


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

END $$;

COMMENT ON FUNCTION exchange_do_reserve_purse(BYTEA, BYTEA, INT8, INT8, INT8, BYTEA, BOOLEAN, INT8, INT4, BYTEA, BYTEA)
  IS 'Create a purse for a reserve.';
