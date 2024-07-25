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

DROP FUNCTION IF EXISTS exchange_do_insert_kyc_attributes;
CREATE FUNCTION exchange_do_insert_kyc_attributes(
  IN in_process_row INT8,
  IN in_h_payto BYTEA,
  IN in_birthday INT4,
  IN in_provider_name TEXT,
  IN in_provider_account_id TEXT,
  IN in_provider_legitimization_id TEXT,
  IN in_collection_time_ts INT8,
  IN in_expiration_time INT8,
  IN in_expiration_time_ts INT8,
  IN in_account_properties TEXT,
  IN in_new_rules TEXT,
  IN ina_events TEXT[],
  IN in_enc_attributes BYTEA,
  IN in_to_investigate BOOLEAN,
  IN in_kyc_completed_notify_s TEXT,
  OUT out_ok BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
   orig_reserve_pub BYTEA;
   orig_reserve_found BOOLEAN;
   my_trigger_outcome_serial INT8;
   my_lmsi INT8;
   my_i INT4;
   ini_event TEXT;
BEGIN

INSERT INTO legitimization_outcomes
  (h_payto
  ,decision_time
  ,expiration_time
  ,jproperties
  ,to_investigate
  ,jnew_rules)
VALUES
  (in_h_payto
  ,in_collection_time_ts
  ,in_expiration_time_ts
  ,in_account_properties
  ,in_to_investigate
  ,in_new_rules)
RETURNING
  outcome_serial_id
INTO
  my_trigger_outcome_serial;

INSERT INTO kyc_attributes
  (h_payto
  ,collection_time
  ,expiration_time
  ,encrypted_attributes
  ,legitimization_serial
  ,trigger_outcome_serial
 ) VALUES
  (in_h_payto
  ,in_collection_time_ts
  ,in_expiration_time_ts
  ,in_enc_attributes
  ,in_process_row
  ,my_trigger_outcome_serial);

UPDATE legitimization_processes
  SET provider_user_id=in_provider_account_id
     ,provider_legitimization_id=in_provider_legitimization_id
     ,expiration_time=GREATEST(expiration_time,in_expiration_time)
     ,finished=TRUE
 WHERE h_payto=in_h_payto
   AND legitimization_process_serial_id=in_process_row
   AND provider_name=in_provider_name
 RETURNING legitimization_measure_serial_id
  INTO my_lmsi;
out_ok = FOUND;

IF out_ok
THEN
  UPDATE legitimization_measures
     SET is_finished=TRUE
   WHERE legitimization_measure_serial_id=my_lmsi;
END IF;

-- If the h_payto refers to a reserve in the original requirements
-- update the originating reserve's birthday.
SELECT reserve_pub
  INTO orig_reserve_pub
  FROM exchange.legitimization_requirements
 WHERE h_payto=in_h_payto
   AND NOT reserve_pub IS NULL;
orig_reserve_found = FOUND;

IF orig_reserve_found
THEN
  UPDATE exchange.reserves
     SET birthday=in_birthday
   WHERE reserve_pub=orig_reserve_pub;
END IF;

IF in_to_investigate
THEN
  INSERT INTO exchange.aml_status
    (h_payto
    ,status)
   VALUES
    (in_h_payto
    ,1)
  ON CONFLICT (h_payto) DO
    UPDATE SET status=EXCLUDED.status | 1;
END IF;

FOR i IN 1..array_length(ina_events,1)
LOOP
  ini_event = ina_events[i];
  INSERT INTO kyc_events
    (event_timestamp
    ,event_type)
    VALUES
    (in_collection_time_ts
    ,ini_event);
END LOOP;

EXECUTE FORMAT (
 'NOTIFY %s'
 ,in_kyc_completed_notify_s);


INSERT INTO kyc_alerts
 (h_payto
 ,trigger_type)
 VALUES
 (in_h_payto,1);


END $$;


COMMENT ON FUNCTION exchange_do_insert_kyc_attributes(INT8, BYTEA, INT4, TEXT, TEXT, TEXT, INT8, INT8, INT8, TEXT, TEXT, TEXT[], BYTEA, BOOL, TEXT)
  IS 'Inserts new KYC attributes and updates the status of the legitimization process and the AML status for the account';
