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
  IN amount_val INT8,
  IN amount_frac INT4,
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
  OUT conflict BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  reserve_gc INT8;
  reserve_val INT8;
  reserve_frac INT4;
  reserve_birthday INT4;
  not_before date;
  earliest_date date;
BEGIN
-- Shards: reserves by reserve_pub (SELECT)
--         reserves_out (INSERT, with CONFLICT detection) by wih
--         reserves by reserve_pub (UPDATE)
--         reserves_in by reserve_pub (SELECT)
--         wire_targets by wire_target_h_payto

SELECT
   current_balance_val
  ,current_balance_frac
  ,gc_date
  ,birthday
 INTO
   reserve_val
  ,reserve_frac
  ,reserve_gc
  ,reserve_birthday
  FROM exchange.reserves
 WHERE reserves.reserve_pub=rpub;

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
  age_ok=FALSE;
  required_age=0;
  conflict=FALSE;
  RETURN;
END IF;


-- Check age requirements
IF ((maximum_age_committed = 0) OR (reserve_birthday = 0))
THEN
  -- No commitment to a non-zero age was provided or the reserve is marked as
  -- having no age restriction. We can simply pass.
  age_ok = OK;
ELSE 
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
    reserve_found = TRUE;
    balance_ok = FALSE;
    age_ok = FALSE;
    required_age = extract(year from age(not_before, current_date)) + 1;
    RETURN;
  END IF;
END IF;

-- Check reserve balance is sufficient.
IF (reserve_val > amount_val)
THEN
  IF (reserve_frac >= amount_frac)
  THEN
    reserve_val=reserve_val - amount_val;
    reserve_frac=reserve_frac - amount_frac;
  ELSE
    reserve_val=reserve_val - amount_val - 1;
    reserve_frac=reserve_frac + 100000000 - amount_frac;
  END IF;
ELSE
  IF (reserve_val = amount_val) AND (reserve_frac >= amount_frac)
  THEN
    reserve_val=0;
    reserve_frac=reserve_frac - amount_frac;
  ELSE
    balance_ok=FALSE;
    RETURN;
  END IF;
END IF;

-- Calculate new expiration dates.
min_reserve_gc=GREATEST(min_reserve_gc,reserve_gc);

-- Update reserve balance.
UPDATE reserves SET
  gc_date=min_reserve_gc
 ,current_balance_val=reserve_val
 ,current_balance_frac=reserve_frac
WHERE
  reserves.reserve_pub=rpub;

reserve_found=TRUE;
balance_ok=TRUE;

-- Write the commitment into the age-withdraw table
INSERT INTO exchange.age_withdraw
  (h_commitment
  ,max_age
  ,reserve_pub
  ,reserve_sig
  ,noreveal_index
  ,denomination_serials
  ,h_blind_evs
  ,denom_sigs)
VALUES
  (h_commitment
  ,maximum_age_committed
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

COMMENT ON FUNCTION exchange_do_age_withdraw(INT8, INT4, BYTEA, BYTEA, INT8, INT8, BYTEA, INT2, INT2, BYTEA[], INT8[], BYTEA[])
  IS 'Checks whether the reserve has sufficient balance for an age-withdraw operation (or the request is repeated and was previously approved) and that age requirements are met. If so updates the database with the result. Includes storing the blinded planchets and denomination signatures, or signaling conflict';

