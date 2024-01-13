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

--------------------------------------------------------------
-- Taler amounts and helper functions
-------------------------------------------------------------

CREATE OR REPLACE FUNCTION amount_normalize(
    IN amount taler_amount
  ,OUT normalized taler_amount
)
LANGUAGE plpgsql
AS $$
BEGIN
  normalized.val = amount.val + amount.frac / 100000000;
  normalized.frac = amount.frac % 100000000;
END $$;

COMMENT ON FUNCTION amount_normalize
  IS 'Returns the normalized amount by adding to the .val the value of (.frac / 100000000) and removing the modulus 100000000 from .frac.';

CREATE OR REPLACE FUNCTION amount_add(
   IN a taler_amount
  ,IN b taler_amount
  ,OUT sum taler_amount
)
LANGUAGE plpgsql
AS $$
BEGIN
  sum = (a.val + b.val, a.frac + b.frac);
  CALL amount_normalize(sum ,sum);

  IF (sum.val > (1<<52))
  THEN
    RAISE EXCEPTION 'addition overflow';
  END IF;
END $$;

COMMENT ON FUNCTION amount_add
  IS 'Returns the normalized sum of two amounts. It raises an exception when the resulting .val is larger than 2^52';

CREATE OR REPLACE FUNCTION amount_left_minus_right(
  IN  l taler_amount
 ,IN  r taler_amount
 ,OUT diff taler_amount
 ,OUT ok BOOLEAN
)
LANGUAGE plpgsql
AS $$
BEGIN

IF (l.val > r.val)
THEN
  ok = TRUE;
  IF (l.frac >= r.frac)
  THEN
    diff.val  = l.val  - r.val;
    diff.frac = l.frac - r.frac;
  ELSE
    diff.val  = l.val  - r.val - 1;
    diff.frac = l.frac + 100000000 - r.frac;
  END IF;
ELSE
  IF (l.val = r.val) AND (l.frac >= r.frac)
  THEN
    diff.val  = 0;
    diff.frac = l.frac - r.frac;
    ok = TRUE;
  ELSE
    diff = (-1, -1);
    ok = FALSE;
  END IF;
END IF;

RETURN;
END $$;

COMMENT ON FUNCTION amount_left_minus_right
  IS 'Subtracts the right amount from the left and returns the difference and TRUE, if the left amount is larger than the right, or an invalid amount and FALSE otherwise.';
