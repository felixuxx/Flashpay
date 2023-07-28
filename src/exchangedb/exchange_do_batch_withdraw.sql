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
  IN amount taler_amount,
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
  reserve RECORD;
  balance taler_amount;
  not_before date;
BEGIN
-- Shards: reserves by reserve_pub (SELECT)
--         reserves_out (INSERT, with CONFLICT detection) by wih
--         reserves by reserve_pub (UPDATE)
--         reserves_in by reserve_pub (SELECT)
--         wire_targets by wire_target_h_payto


SELECT *
  INTO reserve
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

ruuid = reserve.reserve_uuid;

-- Check if age requirements are present
IF ((NOT do_age_check) OR (reserve.birthday = 0))
THEN
  age_ok = TRUE;
  allowed_maximum_age = -1;
ELSE
  -- Age requirements are formally not met:  The exchange is setup to support
  -- age restrictions (do_age_check == TRUE) and the reserve has a
  -- birthday set (reserve_birthday != 0), but the client called the
  -- batch-withdraw endpoint instead of the age-withdraw endpoint, which it
  -- should have.
  not_before=date '1970-01-01' + reserve.birthday;
  allowed_maximum_age = extract(year from age(current_date, not_before));

  reserve_found=TRUE;
  balance_ok=FALSE;
  age_ok = FALSE;
  RETURN;
END IF;

balance = reserve.current_balance;

-- Check reserve balance is sufficient.
IF (balance.val > amount.val)
THEN
  IF (balance.frac >= amount.frac)
  THEN
    balance.val=balance.val - amount.val;
    balance.frac=balance.frac - amount.frac;
  ELSE
    balance.val=balance.val - amount.val - 1;
    balance.frac=balance.frac + 100000000 - amount.frac;
  END IF;
ELSE
  IF (balance.val = amount.val) AND (balance.frac >= amount.frac)
  THEN
    balance.val=0;
    balance.frac=balance.frac - amount.frac;
  ELSE
    balance_ok=FALSE;
    RETURN;
  END IF;
END IF;

-- Calculate new expiration dates.
min_reserve_gc=GREATEST(min_reserve_gc,reserve.gc_date);

-- Update reserve balance.
UPDATE reserves SET
  gc_date=min_reserve_gc
 ,current_balance=balance
WHERE
  reserves.reserve_pub=rpub;

reserve_found=TRUE;
balance_ok=TRUE;

END $$;

COMMENT ON FUNCTION exchange_do_batch_withdraw(taler_amount, BYTEA, INT8, INT8, BOOLEAN)
  IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and that age requirements are formally met. If so updates the database with the result. Excludes storing the planchets.';

