--
-- This file is part of TALER
-- Copyright (C) 2023, 2024 Taler Systems SA
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

DROP FUNCTION IF EXISTS exchange_do_insert_kyc_measure_result;
CREATE FUNCTION exchange_do_insert_kyc_measure_result(
  IN in_process_row INT8,
  IN in_h_payto BYTEA,
  IN in_decision_time INT8,
  IN in_expiration_time_ts INT8,
  IN in_account_properties TEXT,
  IN in_new_rules TEXT,
  IN ina_events TEXT[],
  IN in_to_investigate BOOLEAN,
  IN in_kyc_completed_notify_s TEXT,
  OUT out_ok BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
   my_trigger_outcome_serial INT8;
   my_lmsi INT8;
   my_i INT4;
   ini_event TEXT;
BEGIN

-- Disactivate all previous outcomes.
UPDATE legitimization_outcomes
   SET is_active=FALSE
 WHERE h_payto=in_h_payto
   -- this clause is a minor optimization to avoid
   -- updating outcomes that have long expired.
   AND expiration_time >= in_decision_time;

-- Insert new rules
INSERT INTO legitimization_outcomes
  (h_payto
  ,decision_time
  ,expiration_time
  ,jproperties
  ,to_investigate
  ,jnew_rules)
VALUES
  (in_h_payto
  ,in_decision_time
  ,in_expiration_time_ts
  ,in_account_properties
  ,in_to_investigate
  ,in_new_rules)
RETURNING
  outcome_serial_id
INTO
  my_trigger_outcome_serial;

-- Mark measure as complete
UPDATE legitimization_measures
   SET is_finished=TRUE
 WHERE legitimization_measure_serial_id=
 (SELECT legitimization_measure_serial_id
    FROM legitimization_processes
   WHERE h_payto=in_h_payto
     AND legitimization_process_serial_id=in_process_row);
out_ok = FOUND;

-- Trigger events
FOR i IN 1..COALESCE(array_length(ina_events,1),0)
LOOP
  ini_event = ina_events[i];
  INSERT INTO kyc_events
    (event_timestamp
    ,event_type)
    VALUES
    (in_decision_time
    ,ini_event);
END LOOP;

-- Notify about KYC update
EXECUTE FORMAT (
 'NOTIFY %s'
 ,in_kyc_completed_notify_s);

INSERT INTO kyc_alerts
 (h_payto
 ,trigger_type)
 VALUES
 (in_h_payto,1)
 ON CONFLICT DO NOTHING;

END $$;


COMMENT ON FUNCTION exchange_do_insert_kyc_measure_result(INT8, BYTEA, INT8, INT8, TEXT, TEXT, TEXT[], BOOL, TEXT)
  IS 'Inserts AML program outcome and updates the status of the legitimization process and the AML status for the account';
