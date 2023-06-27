--
-- This file is part of TALER
-- Copyright (C) 2014--2023 Taler Systems SA
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
-- @author Christian Grothoff
-- @author Özgür Kesim

CREATE OR REPLACE FUNCTION exchange_do_batch_withdraw(
  IN amount_val INT8,
  IN amount_frac INT4,
  IN rpub BYTEA,
  IN now INT8,
  IN min_reserve_gc INT8,
  IN do_age_check BOOLEAN,
  OUT reserve_found BOOLEAN,
  OUT balance_ok BOOLEAN,
  OUT age_ok BOOLEAN,
  OUT allowed_maximum_age INT2, -- in years
  OUT ruuid INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  reserve_gc INT8;
  reserve_val INT8;
  reserve_frac INT4;
  reserve_birthday INT4;
  not_before date;
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
  ,reserve_uuid
 INTO
   reserve_val
  ,reserve_frac
  ,reserve_gc
  ,reserve_birthday
  ,ruuid
  FROM exchange.reserves
 WHERE reserves.reserve_pub=rpub;

IF NOT FOUND
THEN
  -- reserve unknown
  reserve_found=FALSE;
  balance_ok=FALSE;
  age_ok=FALSE;
  allowed_maximum_age=0;
  ruuid=2;
  RETURN;
END IF;


-- Check if age requirements are present
IF ((NOT do_age_check) OR (reserve_birthday = 0))
THEN
  age_ok = TRUE;
  allowed_maximum_age = -1;
ELSE
  -- Age requirements are formally not met:  The exchange is setup to support
  -- age restrictions (do_age_check == TRUE) and the reserve has a
  -- birthday set (reserve_birthday != 0), but the client called the
  -- batch-withdraw endpoint instead of the age-withdraw endpoint, which it
  -- should have.
  not_before=date '1970-01-01' + reserve_birthday;
  allowed_maximum_age = extract(year from age(current_date, not_before));

  reserve_found=TRUE;
  balance_ok=FALSE;
  age_ok = FALSE;
  RETURN;
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

END $$;

COMMENT ON FUNCTION exchange_do_batch_withdraw(INT8, INT4, BYTEA, INT8, INT8, BOOLEAN)
  IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and that age requirements are formally met. If so updates the database with the result. Excludes storing the planchets.';

