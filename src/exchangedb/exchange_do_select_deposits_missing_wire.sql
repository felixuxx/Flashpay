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

--CREATE TYPE exchange_do_select_deposits_missing_wire_return_type
--  AS
--  (
--    total_amount taler_amount,
--    payto_uri TEXT,
--    kyc_pending TEXT,
--    wire_deadline INT8,
--    aml_status INT4
--  );

-- FIXME: this function is not working as intended at all yet, work in progress!

CREATE OR REPLACE FUNCTION exchange_do_select_deposits_missing_wire(
  IN in_start_date INT8,
  IN in_end_date INT8)
RETURNS SETOF exchange_do_select_deposits_missing_wire_return_type
LANGUAGE plpgsql
AS $$
DECLARE
  missing CURSOR
  FOR
  SELECT
    bdep.batch_deposit_serial_id
   ,bdep.wire_target_h_payto
   ,bdep.wire_deadline
    FROM batch_deposits bdep
    WHERE bdep.wire_deadline >= in_start_date
      AND bdep.wire_deadline < in_end_date
      AND NOT EXISTS (SELECT 1
        FROM aggregation_tracking atr
        WHERE (atr.batch_deposit_serial_id = bdep.batch_deposit_serial_id));
DECLARE
  my_earliest_deadline INT8; -- earliest deadline that was missed
DECLARE
  my_total_val INT8; -- all deposits without wire
DECLARE
  my_total_frac INT8; -- all deposits without wire (fraction, not normalized)
DECLARE
  my_refund_val INT8; -- all refunds without wire
DECLARE
  my_refund_frac INT8; -- all refunds without wire (fraction, not normalized)
DECLARE
  my_wire_target_h_payto BYTEA; -- hash of the target account
DECLARE
  my_payto_uri TEXT; -- the target account
DECLARE
  my_kyc_pending TEXT; -- pending KYC operations
DECLARE
  my_required_checks TEXT[];
DECLARE
  my_aml_status INT4; -- AML status (0: normal)
DECLARE
  my_total taler_amount; -- amount that was originally deposited
DECLARE
  my_batch_record RECORD;
DECLARE
  my_aml_data RECORD;
DECLARE
  my_aml_threshold taler_amount; -- threshold above which AML is triggered
DECLARE
  i RECORD;
BEGIN

OPEN missing;
LOOP
  FETCH NEXT FROM missing INTO i;
  EXIT WHEN NOT FOUND;

  IF ( (my_earliest_deadline IS NULL) OR
       (my_earliest_deadline > i.wire_deadline) )
  THEN
    my_earliest_deadline = i.wire_deadline;
  END IF;
  SELECT
    SUM((cdep.amount_with_fee).val) AS total_val
   ,SUM((cdep.amount_with_fee).frac::INT8) AS total_frac
   ,SUM((r.amount_with_fee).val) AS refund_val
   ,SUM((r.amount_with_fee).frac::INT8) AS refund_frac
    INTO
      my_batch_record
    FROM coin_deposits cdep
    LEFT JOIN refunds r
      ON ( (r.coin_pub = cdep.coin_pub) AND
           (r.batch_deposit_serial_id = cdep.batch_deposit_serial_id) )
    WHERE cdep.batch_deposit_serial_id = i.batch_deposit_serial_id;
--    GROUP BY bdep.wire_target_h_payto; -- maybe use temporary table intead of cursor, or accumulate C-side?

  my_total_val=my_batch_record.total_val;
  my_total_frac=my_batch_record.total_frac;
  my_refund_val=my_batch_record.refund_val;
  my_refund_frac=my_batch_record.refund_frac;

  RAISE WARNING 'tval: %', my_total_val;
  RAISE WARNING 'tfrac: %', my_total_frac;
  RAISE WARNING 'rval: %', my_refund_val;
  RAISE WARNING 'rfrac: %', my_refund_frac;

  IF my_refund_val IS NOT NULL
  THEN
    -- subtract refunds from total
    my_total_val = my_total_val - my_refund_val;
    -- note: frac could go negative here, that's OK
    my_total_frac = my_total_frac - my_refund_frac;
  END IF;
  -- Normalize total amount
  IF my_total_frac < 0
  THEN
    my_total.val = my_total_val - 1 + my_total_frac / 100000000;
    my_total.frac = 100000000 + my_total_frac % 100000000;
  ELSE
    my_total.val = my_total_val + my_total_frac / 100000000;
    my_total.frac = my_total_frac % 100000000;
  END IF;
  RAISE WARNING 'val: %', my_total.val;
  RAISE WARNING 'frac: %', my_total.frac;
  ASSERT my_total.frac >= 0, 'Normalized amount fraction must be non-negative';
  ASSERT my_total.frac < 100000000, 'Normalized amount fraction must be below 100000000';

  IF (my_total.val < 0)
  THEN
    -- Refunds above deposits. That's a problem, but not one for this auditor pass.
    CONTINUE;
  END IF;

  -- Note: total amount here is NOT the exact amount due for the
  -- wire transfer, as we did not consider deposit, refund and wire fees.
  -- The amount given in the report is thus ONLY indicative of the non-refunded
  -- gross amount, not the net transfer amount.

  IF 0 = my_total_val + my_total_frac
  THEN
    -- full refund, skip report entirely
    CONTINUE;
  END IF;

  -- Fetch payto URI
  -- NOTE: we want to group by my_wire_target_h_payto and not do this repeatedly per batch deposit!
  my_payto_uri = NULL;
  SELECT payto_uri
    INTO my_payto_uri
    FROM wire_targets
   WHERE wire_target_h_payto=my_wire_target_h_payto;

  -- Get last AML decision
  SELECT
      new_threshold
     ,kyc_requirements
     ,new_status
    INTO
     my_aml_data
     FROM aml_history
    WHERE h_payto=my_wire_target_h_payto
    ORDER BY aml_history_serial_id -- get last decision
      DESC LIMIT 1;
  IF FOUND
  THEN
    my_aml_threshold=my_aml_data.new_threshold;
    my_kyc_pending=my_aml_data.kyc_requirements;
    my_aml_status=my_aml_data.kyc_status;
  ELSE
    my_aml_threshold=NULL;
    my_kyc_pending=NULL;
    my_aml_status=0;
  END IF;
  IF 0 != my_aml_status
  THEN
    RETURN NEXT (
       my_total
      ,my_payto_uri
      ,my_kyc_pending
      ,my_earliest_deadline
      ,my_aml_status
      ,NULL);
  END IF;

  -- Check KYC status
  SELECT string_to_array (required_checks, ' ')
    INTO my_required_checks
    FROM legitimization_requirements
    WHERE h_payto=my_wire_target_h_payto;


--  PERFORM -- provider
--    FROM kyc_attributes
--    WHERE legitimization_serial=my_legitimization_serial;
  -- FIXME: can't tell if providers cover all required checks from DB!!!
  -- Idea: expand kyc_attributes table with list of satisfied checks!??!

    RETURN NEXT (
       my_total
      ,my_payto_uri
      ,my_kyc_pending
      ,my_earliest_deadline
      ,my_aml_status
      ,NULL::taler_amount);

END LOOP;
CLOSE missing;
RETURN;
END $$;
