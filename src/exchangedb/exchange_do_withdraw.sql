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


CREATE OR REPLACE FUNCTION exchange_do_withdraw(
  IN cs_nonce BYTEA,
  IN amount taler_amount,
  IN h_denom_pub BYTEA,
  IN rpub BYTEA,
  IN reserve_sig BYTEA,
  IN h_coin_envelope BYTEA,
  IN denom_sig BYTEA,
  IN now INT8,
  IN min_reserve_gc INT8,
  IN do_age_check BOOLEAN,
  OUT reserve_found BOOLEAN,
  OUT balance_ok BOOLEAN,
  OUT nonce_ok BOOLEAN,
  OUT age_ok BOOLEAN,
  OUT allowed_maximum_age INT2, -- in years
  OUT ruuid INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  reserve_gc INT8;
  denom_serial INT8;
  reserve taler_amount;
  reserve_birthday INT4;
  not_before date;
BEGIN
-- Shards: reserves by reserve_pub (SELECT)
--         reserves_out (INSERT, with CONFLICT detection) by wih
--         reserves by reserve_pub (UPDATE)
--         reserves_in by reserve_pub (SELECT)
--         wire_targets by wire_target_h_payto

SELECT denominations_serial
  INTO denom_serial
  FROM exchange.denominations
 WHERE denom_pub_hash=h_denom_pub;

IF NOT FOUND
THEN
  -- denomination unknown, should be impossible!
  reserve_found=FALSE;
  balance_ok=FALSE;
  age_ok=FALSE;
  allowed_maximum_age=0;
  ruuid=0;
  ASSERT false, 'denomination unknown';
  RETURN;
END IF;


SELECT
   current_balance
  ,gc_date
  ,birthday
  ,reserve_uuid
 INTO
   reserve.val
  ,reserve.frac
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
  nonce_ok=TRUE;
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
  nonce_ok=TRUE; -- we do not really know
  balance_ok=TRUE;-- we do not really know
  age_ok = FALSE;
  RETURN;
END IF;

-- We optimistically insert, and then on conflict declare
-- the query successful due to idempotency.
INSERT INTO exchange.reserves_out
  (h_blind_ev
  ,denominations_serial
  ,denom_sig
  ,reserve_uuid
  ,reserve_sig
  ,execution_date
  ,amount_with_fee_val
  ,amount_with_fee_frac)
VALUES
  (h_coin_envelope
  ,denom_serial
  ,denom_sig
  ,ruuid
  ,reserve_sig
  ,now
  ,amount.val
  ,amount.frac)
ON CONFLICT DO NOTHING;

IF NOT FOUND
THEN
  -- idempotent query, all constraints must be satisfied
  reserve_found=TRUE;
  balance_ok=TRUE;
  nonce_ok=TRUE;
  RETURN;
END IF;

-- Check reserve balance is sufficient.
IF (reserve.val > amount.val)
THEN
  IF (reserve.frac >= amount.frac)
  THEN
    reserve.val=reserve.val - amount.val;
    reserve.frac=reserve.frac - amount.frac;
  ELSE
    reserve.val=reserve.val - amount.val - 1;
    reserve.frac=reserve.frac + 100000000 - amount.frac;
  END IF;
ELSE
  IF (reserve.val = amount.val) AND (reserve.frac >= amount.frac)
  THEN
    reserve.val=0;
    reserve.frac=reserve.frac - amount.frac;
  ELSE
    reserve_found=TRUE;
    nonce_ok=TRUE; -- we do not really know
    balance_ok=FALSE;
    RETURN;
  END IF;
END IF;

-- Calculate new expiration dates.
min_reserve_gc=GREATEST(min_reserve_gc,reserve_gc);

-- Update reserve balance.
UPDATE reserves SET
  gc_date=min_reserve_gc
 ,current_balance=reserve
WHERE
  reserves.reserve_pub=rpub;

reserve_found=TRUE;
balance_ok=TRUE;



-- Special actions needed for a CS withdraw?
IF NOT NULL cs_nonce
THEN
  -- Cache CS signature to prevent replays in the future
  -- (and check if cached signature exists at the same time).
  INSERT INTO exchange.cs_nonce_locks
    (nonce
    ,max_denomination_serial
    ,op_hash)
  VALUES
    (cs_nonce
    ,denom_serial
    ,h_coin_envelope)
  ON CONFLICT DO NOTHING;

  IF NOT FOUND
  THEN
    -- See if the existing entry is identical.
    SELECT 1
      FROM exchange.cs_nonce_locks
     WHERE nonce=cs_nonce
       AND op_hash=h_coin_envelope;
    IF NOT FOUND
    THEN
      reserve_found=FALSE;
      balance_ok=FALSE;
      nonce_ok=FALSE;
      RETURN;
    END IF;
  END IF;
ELSE
  nonce_ok=TRUE; -- no nonce, hence OK!
END IF;

END $$;

COMMENT ON FUNCTION exchange_do_withdraw(BYTEA, taler_amount, BYTEA, BYTEA, BYTEA, BYTEA, BYTEA, INT8, INT8, BOOLEAN)
  IS 'Checks whether the reserve has sufficient balance for a withdraw operation (or the request is repeated and was previously approved) and if the age requirements are formally met.  If so updates the database with the result';

