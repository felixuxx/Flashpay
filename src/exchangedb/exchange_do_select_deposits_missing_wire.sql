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
-- @author: Christian Grothoff

CREATE OR REPLACE FUNCTION exchange_do_select_deposits_missing_wire(
  IN in_min_serial_id INT8)
RETURNS SETOF exchange_do_select_deposits_missing_wire_return_type
LANGUAGE plpgsql
AS $$
DECLARE
  missing CURSOR
  FOR
  SELECT
    batch_deposit_serial_id
   ,wire_target_h_payto
   ,wire_deadline
    FROM batch_deposits
    WHERE batch_deposit_serial_id > in_min_serial_id;
DECLARE
  my_total_val INT8; -- all deposits without wire
DECLARE
  my_total_frac INT8; -- all deposits without wire (fraction, not normalized)
DECLARE
  my_total taler_amount; -- amount that was originally deposited
DECLARE
  my_batch_record RECORD;
DECLARE
  i RECORD;
BEGIN

OPEN missing;
LOOP
  FETCH NEXT FROM missing INTO i;
  EXIT WHEN NOT FOUND;

  SELECT
    SUM((cdep.amount_with_fee).val) AS total_val
   ,SUM((cdep.amount_with_fee).frac::INT8) AS total_frac
    INTO
      my_batch_record
    FROM coin_deposits cdep
    WHERE cdep.batch_deposit_serial_id = i.batch_deposit_serial_id;

  my_total_val=my_batch_record.total_val;
  my_total_frac=my_batch_record.total_frac;

  -- Normalize total amount
  my_total.val = my_total_val + my_total_frac / 100000000;
  my_total.frac = my_total_frac % 100000000;
  RETURN NEXT (
       i.batch_deposit_serial_id
      ,my_total
      ,i.wire_target_h_payto
      ,i.wire_deadline);

END LOOP;
CLOSE missing;
RETURN;
END $$;
