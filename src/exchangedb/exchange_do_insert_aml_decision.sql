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

CREATE OR REPLACE FUNCTION exchange_do_insert_aml_decision(
  IN in_h_payto BYTEA,
  IN in_new_threshold_val INT8,
  IN in_new_threshold_frac INT4,
  IN in_new_status INT4,
  IN in_decision_time INT8,
  IN in_justification VARCHAR,
  IN in_decider_pub BYTEA,
  IN in_decider_sig BYTEA,
  IN in_notify_s VARCHAR,
  IN in_kyc_requirements VARCHAR,
  OUT out_invalid_officer BOOLEAN,
  OUT out_last_date INT8)
LANGUAGE plpgsql
AS $$
BEGIN
-- Check officer is eligible to make decisions.
PERFORM
  FROM exchange.aml_staff
  WHERE decider_pub=in_decider_pub
    AND is_active
    AND NOT read_only;
IF NOT FOUND
THEN
  out_invalid_officer=TRUE;
  out_last_date=0;
  RETURN;
END IF;
out_invalid_officer=FALSE;

-- Check no more recent decision exists.
SELECT decision_time
  INTO out_last_date
  FROM exchange.aml_history
  WHERE h_payto=in_h_payto
  ORDER BY decision_time DESC;
IF FOUND
THEN
  IF out_last_date >= in_decision_time
  THEN
    -- Refuse to insert older decision.
    RETURN;
  END IF;
  UPDATE exchange.aml_status
    SET threshold_val=in_new_threshold_val
       ,threshold_frac=in_new_threshold_frac
       ,status=in_new_status
   WHERE h_payto=in_h_payto;
  ASSERT FOUND, 'cannot have AML decision history but no AML status';
ELSE
  out_last_date = 0;
  INSERT INTO exchange.aml_status
    (h_payto
    ,threshold_val
    ,threshold_frac
    ,status)
    VALUES
    (in_h_payto
    ,in_new_threshold_val
    ,in_new_threshold_frac
    ,in_new_status);
END IF;


INSERT INTO exchange.aml_history
  (h_payto
  ,new_threshold_val
  ,new_threshold_frac
  ,new_status
  ,decision_time
  ,justification
  ,kyc_requirements
  ,decider_pub
  ,decider_sig
  ) VALUES
  (in_h_payto
  ,in_new_threshold_val
  ,in_new_threshold_frac
  ,in_new_status
  ,in_decision_time
  ,in_justification
  ,in_kyc_requirements
  ,in_decider_pub
  ,in_decider_sig);


-- wake up taler-exchange-aggregator
IF 0 = in_new_status
THEN
  INSERT INTO kyc_alerts
    (h_payto
    ,trigger_type)
    VALUES
    (in_h_payto,1);

   EXECUTE FORMAT (
     'NOTIFY %s'
    ,in_notify_s);

END IF;


END $$;


COMMENT ON FUNCTION exchange_do_insert_aml_decision(BYTEA, INT8, INT4, INT4, INT8, VARCHAR, BYTEA, BYTEA, VARCHAR, VARCHAR)
  IS 'Checks whether the AML officer is eligible to make AML decisions and if so inserts the decision into the table';
