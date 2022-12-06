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

CREATE OR REPLACE FUNCTION exchange_do_reserve_open(
  IN in_reserve_pub BYTEA,
  IN in_total_paid_val INT8,
  IN in_total_paid_frac INT4,
  IN in_reserve_payment_val INT8,
  IN in_reserve_payment_frac INT4,
  IN in_min_purse_limit INT4,
  IN in_default_purse_limit INT4,
  IN in_reserve_sig BYTEA,
  IN in_desired_expiration INT8,
  IN in_reserve_gc_delay INT8,
  IN in_now INT8,
  IN in_open_fee_val INT8,
  IN in_open_fee_frac INT4,
  OUT out_open_cost_val INT8,
  OUT out_open_cost_frac INT4,
  OUT out_final_expiration INT8,
  OUT out_no_funds BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  my_balance_val INT8;
DECLARE
  my_balance_frac INT4;
DECLARE
  my_cost_val INT8;
DECLARE
  my_cost_tmp INT8;
DECLARE
  my_cost_frac INT4;
DECLARE
  my_years_tmp INT4;
DECLARE
  my_years INT4;
DECLARE
  my_needs_update BOOL;
DECLARE
  my_purses_allowed INT8;
DECLARE
  my_expiration_date INT8;
DECLARE
  my_reserve_expiration INT8;
BEGIN

-- FIXME: use SELECT FOR UPDATE?
SELECT
  purses_allowed
 ,expiration_date
 ,current_balance_val
 ,current_balance_frac
INTO
  my_purses_allowed
 ,my_reserve_expiration
 ,my_balance_val
 ,my_balance_frac
FROM reserves
WHERE
  reserve_pub=in_reserve_pub;

IF NOT FOUND
THEN
  -- FIXME: do we need to set a 'not found'?
  RAISE NOTICE 'reserve not found';
  RETURN;
END IF;

-- Do not allow expiration time to start in the past already
IF (my_reserve_expiration < in_now)
THEN
  my_expiration_date = in_now;
ELSE
  my_expiration_date = my_reserve_expiration;
END IF;

my_cost_val = 0;
my_cost_frac = 0;
my_needs_update = FALSE;
my_years = 0;

-- Compute years based on desired expiration time
IF (my_expiration_date < in_desired_expiration)
THEN
  my_years = (31535999999999 + in_desired_expiration - my_expiration_date) / 31536000000000;
  my_purses_allowed = in_default_purse_limit;
  my_expiration_date = my_expiration_date + 31536000000000 * my_years;
END IF;

-- Increase years based on purses requested
IF (my_purses_allowed < in_min_purse_limit)
THEN
  my_years = (31535999999999 + in_desired_expiration - in_now) / 31536000000000;
  my_expiration_date = in_now + 31536000000000 * my_years;
  my_years_tmp = (in_min_purse_limit + in_default_purse_limit - my_purses_allowed - 1) / in_default_purse_limit;
  my_years = my_years + my_years_tmp;
  my_purses_allowed = my_purses_allowed + (in_default_purse_limit * my_years_tmp);
END IF;


-- Compute cost based on annual fees
IF (my_years > 0)
THEN
  my_cost_val = my_years * in_open_fee_val;
  my_cost_tmp = my_years * in_open_fee_frac / 100000000;
  IF (CAST (my_cost_val + my_cost_tmp AS INT8) < my_cost_val)
  THEN
    out_open_cost_val=9223372036854775807;
    out_open_cost_frac=2147483647;
    out_final_expiration=my_expiration_date;
    out_no_funds=FALSE;
    RAISE NOTICE 'arithmetic issue computing amount';
  RETURN;
  END IF;
  my_cost_val = CAST (my_cost_val + my_cost_tmp AS INT8);
  my_cost_frac = my_years * in_open_fee_frac % 100000000;
  my_needs_update = TRUE;
END IF;

-- check if we actually have something to do
IF NOT my_needs_update
THEN
  out_final_expiration = my_reserve_expiration;
  out_open_cost_val = 0;
  out_open_cost_frac = 0;
  out_no_funds=FALSE;
  RAISE NOTICE 'no change required';
  RETURN;
END IF;

-- Check payment (coins and reserve) would be sufficient.
IF ( (in_total_paid_val < my_cost_val) OR
     ( (in_total_paid_val = my_cost_val) AND
       (in_total_paid_frac < my_cost_frac) ) )
THEN
  out_open_cost_val = my_cost_val;
  out_open_cost_frac = my_cost_frac;
  out_no_funds=FALSE;
  -- We must return a failure, which is indicated by
  -- the expiration being below the desired expiration.
  IF (my_reserve_expiration >= in_desired_expiration)
  THEN
    -- This case is relevant especially if the purse
    -- count was to be increased and the payment was
    -- insufficient to cover this for the full period.
    RAISE NOTICE 'forcing low expiration time';
    out_final_expiration = 0;
  ELSE
    out_final_expiration = my_reserve_expiration;
  END IF;
  RAISE NOTICE 'amount paid too low';
  RETURN;
END IF;

-- Check reserve balance is sufficient.
IF (my_balance_val > in_reserve_payment_val)
THEN
  IF (my_balance_frac >= in_reserve_payment_frac)
  THEN
    my_balance_val=my_balance_val - in_reserve_payment_val;
    my_balance_frac=my_balance_frac - in_reserve_payment_frac;
  ELSE
    my_balance_val=my_balance_val - in_reserve_payment_val - 1;
    my_balance_frac=my_balance_frac + 100000000 - in_reserve_payment_frac;
  END IF;
ELSE
  IF (my_balance_val = in_reserve_payment_val) AND (my_balance_frac >= in_reserve_payment_frac)
  THEN
    my_balance_val=0;
    my_balance_frac=my_balance_frac - in_reserve_payment_frac;
  ELSE
    out_final_expiration = my_reserve_expiration;
    out_open_cost_val = my_cost_val;
    out_open_cost_frac = my_cost_frac;
    out_no_funds=TRUE;
    RAISE NOTICE 'reserve balance too low';
  RETURN;
  END IF;
END IF;

UPDATE reserves SET
  current_balance_val=my_balance_val
 ,current_balance_frac=my_balance_frac
 ,gc_date=my_reserve_expiration + in_reserve_gc_delay
 ,expiration_date=my_expiration_date
 ,purses_allowed=my_purses_allowed
WHERE
 reserve_pub=in_reserve_pub;

out_final_expiration=my_expiration_date;
out_open_cost_val = my_cost_val;
out_open_cost_frac = my_cost_frac;
out_no_funds=FALSE;
RETURN;

END $$;
