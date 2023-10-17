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
  IN in_total_paid taler_amount,
  IN in_reserve_payment taler_amount,
  IN in_min_purse_limit INT4,
  IN in_default_purse_limit INT4,
  IN in_reserve_sig BYTEA,
  IN in_desired_expiration INT8,
  IN in_reserve_gc_delay INT8,
  IN in_now INT8,
  IN in_open_fee taler_amount,
  OUT out_open_cost taler_amount,
  OUT out_final_expiration INT8,
  OUT out_no_reserve BOOLEAN,
  OUT out_no_funds BOOLEAN,
  OUT out_reserve_balance taler_amount)
LANGUAGE plpgsql
AS $$
DECLARE
  my_balance taler_amount;
  my_cost taler_amount;
  my_cost_tmp INT8;
  my_years_tmp INT4;
  my_years INT4;
  my_needs_update BOOL;
  my_expiration_date INT8;
  reserve RECORD;
BEGIN

SELECT current_balance
      ,expiration_time
      ,purses_allowed
  INTO reserve
  FROM reserves
 WHERE reserve_pub=in_reserve_pub;

IF NOT FOUND
THEN
  RAISE NOTICE 'reserve not found';
  out_no_reserve = TRUE;
  out_no_funds = TRUE;
  out_reserve_balance.val = 0;
  out_reserve_balance.frac = 0;
  out_open_cost.val = 0;
  out_open_cost.frac = 0;
  out_final_expiration = 0;
  RETURN;
END IF;

out_no_reserve = FALSE;
out_reserve_balance = reserve.current_balance;

-- Do not allow expiration time to start in the past already
IF (reserve.expiration_date < in_now)
THEN
  my_expiration_date = in_now;
ELSE
  my_expiration_date = reserve.expiration_date;
END IF;

my_cost.val = 0;
my_cost.frac = 0;
my_needs_update = FALSE;
my_years = 0;

-- Compute years based on desired expiration time
IF (my_expiration_date < in_desired_expiration)
THEN
  my_years = (31535999999999 + in_desired_expiration - my_expiration_date) / 31536000000000;
  reserve.purses_allowed = in_default_purse_limit;
  my_expiration_date = my_expiration_date + 31536000000000 * my_years;
END IF;

-- Increase years based on purses requested
IF (reserve.purses_allowed < in_min_purse_limit)
THEN
  my_years = (31535999999999 + in_desired_expiration - in_now) / 31536000000000;
  my_expiration_date = in_now + 31536000000000 * my_years;
  my_years_tmp = (in_min_purse_limit + in_default_purse_limit - reserve.purses_allowed - 1) / in_default_purse_limit;
  my_years = my_years + my_years_tmp;
  reserve.purses_allowed = reserve.purses_allowed + (in_default_purse_limit * my_years_tmp);
END IF;


-- Compute cost based on annual fees
IF (my_years > 0)
THEN
  my_cost.val = my_years * in_open_fee.val;
  my_cost_tmp = my_years * in_open_fee.frac / 100000000;
  IF (CAST (my_cost.val + my_cost_tmp AS INT8) < my_cost.val)
  THEN
    out_open_cost.val=9223372036854775807;
    out_open_cost.frac=2147483647;
    out_final_expiration=my_expiration_date;
    out_no_funds=FALSE;
    RAISE NOTICE 'arithmetic issue computing amount';
  RETURN;
  END IF;
  my_cost.val = CAST (my_cost.val + my_cost_tmp AS INT8);
  my_cost.frac = my_years * in_open_fee.frac % 100000000;
  my_needs_update = TRUE;
END IF;

-- check if we actually have something to do
IF NOT my_needs_update
THEN
  out_final_expiration = reserve.expiration_date;
  out_open_cost.val = 0;
  out_open_cost.frac = 0;
  out_no_funds=FALSE;
  RAISE NOTICE 'no change required';
  RETURN;
END IF;

-- Check payment (coins and reserve) would be sufficient.
IF ( (in_total_paid.val < my_cost.val) OR
     ( (in_total_paid.val = my_cost.val) AND
       (in_total_paid.frac < my_cost.frac) ) )
THEN
  out_open_cost.val = my_cost.val;
  out_open_cost.frac = my_cost.frac;
  out_no_funds=FALSE;
  -- We must return a failure, which is indicated by
  -- the expiration being below the desired expiration.
  IF (reserve.expiration_date >= in_desired_expiration)
  THEN
    -- This case is relevant especially if the purse
    -- count was to be increased and the payment was
    -- insufficient to cover this for the full period.
    RAISE NOTICE 'forcing low expiration time';
    out_final_expiration = 0;
  ELSE
    out_final_expiration = reserve.expiration_date;
  END IF;
  RAISE NOTICE 'amount paid too low';
  RETURN;
END IF;

-- Check reserve balance is sufficient.
IF (out_reserve_balance.val > in_reserve_payment.val)
THEN
  IF (out_reserve_balance.frac >= in_reserve_payment.frac)
  THEN
    my_balance.val=out_reserve_balance.val - in_reserve_payment.val;
    my_balance.frac=out_reserve_balance.frac - in_reserve_payment.frac;
  ELSE
    my_balance.val=out_reserve_balance.val - in_reserve_payment.val - 1;
    my_balance.frac=out_reserve_balance.frac + 100000000 - in_reserve_payment.frac;
  END IF;
ELSE
  IF (out_reserve_balance.val = in_reserve_payment.val) AND (out_reserve_balance.frac >= in_reserve_payment.frac)
  THEN
    my_balance.val=0;
    my_balance.frac=out_reserve_balance.frac - in_reserve_payment.frac;
  ELSE
    out_final_expiration = reserve.expiration_date;
    out_open_cost.val = my_cost.val;
    out_open_cost.frac = my_cost.frac;
    out_no_funds=TRUE;
    RAISE NOTICE 'reserve balance too low';
  RETURN;
  END IF;
END IF;

UPDATE reserves SET
  current_balance=my_balance
 ,gc_date=reserve.expiration_date + in_reserve_gc_delay
 ,expiration_date=my_expiration_date
 ,purses_allowed=reserve.purses_allowed
WHERE
 reserve_pub=in_reserve_pub;

out_final_expiration=my_expiration_date;
out_open_cost = my_cost;
out_no_funds=FALSE;
RETURN;

END $$;
