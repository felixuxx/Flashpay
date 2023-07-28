--
-- This file is part of TALER
-- Copyright (C) 2023 Taler Systems SA
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
-- @author Özgür Kesim

CREATE OR REPLACE FUNCTION exchange_do_age_withdraw(
  IN amount_with_fee taler_amount,
  IN rpub BYTEA,
  IN rsig BYTEA,
  IN now INT8,
  IN min_reserve_gc INT8,
  IN h_commitment BYTEA,
  IN maximum_age_committed INT2, -- in years ϵ [0,1..)
  IN noreveal_index INT2,
  IN blinded_evs BYTEA[],
  IN denom_serials INT8[],
  IN denom_sigs BYTEA[],
  OUT reserve_found BOOLEAN,
  OUT balance_ok BOOLEAN,
  OUT age_ok BOOLEAN,
  OUT required_age INT2, -- in years ϵ [0,1..)
  OUT reserve_birthday INT4,
  OUT conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  reserve_gc INT8;
  difference RECORD;
  balance  taler_amount;
  new_balance taler_amount;
  not_before date;
  earliest_date date;
BEGIN
-- Shards: reserves by reserve_pub (SELECT)
--         reserves_out (INSERT, with CONFLICT detection) by wih
--         reserves by reserve_pub (UPDATE)
--         reserves_in by reserve_pub (SELECT)
--         wire_targets by wire_target_h_payto

SELECT
   current_balance
  ,gc_date
  ,birthday
 INTO
   balance.val
  ,balance.frac
  ,reserve_gc
  ,reserve_birthday
  FROM exchange.reserves
 WHERE reserves.reserve_pub=rpub;

IF NOT FOUND
THEN
  reserve_found=FALSE;
  age_ok = FALSE;
  required_age=-1;
  conflict=FALSE;
  balance_ok=FALSE;
  RETURN;
END IF;

reserve_found = TRUE;
conflict=FALSE;  -- not really yet determined

-- Check age requirements
IF (reserve_birthday <> 0)
THEN
  not_before=date '1970-01-01' + reserve_birthday;
  earliest_date = current_date - make_interval(maximum_age_committed);
  --
  -- 1970-01-01 + birthday == not_before                 now
  --     |                     |                          |
  -- <.......not allowed......>[<.....allowed range......>]
  --     |                     |                          |
  -- ____*_____________________*_________*________________*  timeline
  --                                     |
  --                            earliest_date ==
  --                                now - maximum_age_committed*year
  --
  IF (earliest_date < not_before)
  THEN
    required_age = extract(year from age(current_date, not_before));
    age_ok = FALSE;
    balance_ok=TRUE; -- NOT REALLY
    RETURN;
  END IF;
END IF;

age_ok = TRUE;
required_age=0;

-- Check reserve balance is sufficient.
SELECT *
INTO
  difference
FROM
  amount_left_minus_right(
     balance
    ,amount_with_fee);

balance_ok = difference.ok;

IF NOT balance_ok
THEN
  RETURN;
END IF;

new_balance = difference.diff;

-- Calculate new expiration dates.
min_reserve_gc=GREATEST(min_reserve_gc,reserve_gc);

-- Update reserve balance.
UPDATE reserves SET
  gc_date=min_reserve_gc
 ,current_balance=new_balance
WHERE
  reserves.reserve_pub=rpub;

-- Write the commitment into the age-withdraw table
INSERT INTO exchange.age_withdraw
  (h_commitment
  ,max_age
  ,amount_with_fee
  ,reserve_pub
  ,reserve_sig
  ,noreveal_index
  ,denom_serials
  ,h_blind_evs
  ,denom_sigs)
VALUES
  (h_commitment
  ,maximum_age_committed
  ,amount_with_fee
  ,rpub
  ,rsig
  ,noreveal_index
  ,denom_serials
  ,blinded_evs
  ,denom_sigs)
ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- Signal a conflict so that the caller
  -- can fetch the actual data from the DB.
  conflict=TRUE;
  RETURN;
ELSE
  conflict=FALSE;
END IF;

END $$;

COMMENT ON FUNCTION exchange_do_age_withdraw(taler_amount, BYTEA, BYTEA, INT8, INT8, BYTEA, INT2, INT2, BYTEA[], INT8[], BYTEA[])
  IS 'Checks whether the reserve has sufficient balance for an age-withdraw operation (or the request is repeated and was previously approved) and that age requirements are met. If so updates the database with the result. Includes storing the blinded planchets and denomination signatures, or signaling conflict';
