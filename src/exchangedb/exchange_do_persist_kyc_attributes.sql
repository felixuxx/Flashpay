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

DROP FUNCTION IF EXISTS exchange_do_persist_kyc_attributes;
CREATE FUNCTION exchange_do_persist_kyc_attributes(
  IN in_process_row INT8,
  IN in_h_payto BYTEA,
  IN in_birthday INT4,
  IN in_provider_name TEXT,
  IN in_provider_account_id TEXT,  -- can be NULL
  IN in_provider_legitimization_id TEXT, -- can be NULL
  IN in_collection_time_ts INT8,
  IN in_expiration_time INT8, -- not rounded
  IN in_expiration_time_ts INT8, -- rounded to timestamp
  IN in_enc_attributes BYTEA,
  IN in_kyc_completed_notify_s TEXT,
  OUT out_ok BOOLEAN) -- set to true if we had a legi process matching in_process_row and in_provider_name for this account
LANGUAGE plpgsql
AS $$
BEGIN

INSERT INTO kyc_attributes
  (h_payto
  ,collection_time
  ,expiration_time
  ,encrypted_attributes
  ,legitimization_serial
 ) VALUES
  (in_h_payto
  ,in_collection_time_ts
  ,in_expiration_time_ts
  ,in_enc_attributes
  ,in_process_row);

UPDATE legitimization_processes
  SET provider_user_id=in_provider_account_id
     ,provider_legitimization_id=in_provider_legitimization_id
     ,expiration_time=GREATEST(expiration_time,in_expiration_time)
     ,finished=TRUE
 WHERE h_payto=in_h_payto
   AND legitimization_process_serial_id=in_process_row
   AND provider_name=in_provider_name;
out_ok=FOUND;

UPDATE reserves
   SET birthday=in_birthday
 WHERE (reserve_pub IN
    (SELECT reserve_pub
       FROM reserves_in
      WHERE wire_source_h_payto IN
        (SELECT wire_source_h_payto
           FROM wire_targets
          WHERE h_normalized_payto=in_h_payto) ) )
-- The next 3 clauses primarily serve to limit
-- unnecessary updates for reserves we do not
-- care about anymore.
  AND ( ((current_balance).frac > 0) OR
        ((current_balance).val > 0 ) )
  AND (expiration_date > in_collection_time_ts);


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


COMMENT ON FUNCTION exchange_do_persist_kyc_attributes(INT8, BYTEA, INT4, TEXT, TEXT, TEXT, INT8, INT8, INT8, BYTEA, TEXT)
  IS 'Inserts new KYC attributes and updates the status of the legitimization process';
