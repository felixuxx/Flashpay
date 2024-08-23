--
-- This file is part of TALER
-- Copyright (C) 2024 Taler Systems SA
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

DROP FUNCTION IF EXISTS auditor_do_get_balance;
CREATE OR REPLACE FUNCTION auditor_do_get_balance(
  IN in_keys TEXT[])
RETURNS SETOF taler_amount
LANGUAGE plpgsql
AS $$
DECLARE
  my_key TEXT;
  my_rec RECORD;
  my_val taler_amount;
BEGIN
  FOREACH my_key IN ARRAY in_keys
  LOOP
    SELECT (ab.balance_value).val
          ,(ab.balance_value).frac
      INTO my_rec
      FROM auditor_balances ab
      WHERE balance_key=my_key;
    IF FOUND
    THEN
        my_val.val = my_rec.val;
        my_val.frac = my_rec.frac;
        RETURN NEXT my_val;
    ELSE
        RETURN NEXT NULL;
    END IF;
  END LOOP;
END $$;

COMMENT ON FUNCTION auditor_do_get_balance(TEXT[])
  IS 'Finds all balances associated with the array of keys given as the argument and returns them in order';
