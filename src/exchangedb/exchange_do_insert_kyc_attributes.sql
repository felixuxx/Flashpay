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

CREATE OR REPLACE FUNCTION exchange_do_insert_kyc_attributes(
  IN in_process_row INT8,
  IN in_h_payto BYTEA,
  IN in_kyc_prox BYTEA,
  IN in_provider_section VARCHAR,
  IN in_birthday INT4,
  IN in_provider_account_id VARCHAR,
  IN in_provider_legitimization_id VARCHAR,
  IN in_collection_time_ts INT8,
  IN in_expiration_time INT8,
  IN in_expiration_time_ts INT8,
  IN in_enc_attributes BYTEA,
  IN in_require_aml BOOLEAN,
  IN in_kyc_completed_notify_s VARCHAR,
  OUT out_ok BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN

INSERT INTO exchange.kyc_attributes
  (h_payto
  ,kyc_prox
  ,provider
  ,collection_time
  ,expiration_time
  ,encrypted_attributes
 ) VALUES
  (in_h_payto
  ,in_kyc_prox
  ,in_provider_section
  ,in_collection_time_ts
  ,in_expiration_time_ts
  ,in_enc_attributes);

-- FIXME-Oec: modify to 'return' the reserve_pub here
-- (requires of course to modify other code to store
-- the reserve pub in the right table in the first place)
UPDATE exchange.legitimization_processes
  SET provider_user_id=in_provider_account_id
     ,provider_legitimization_id=in_provider_legitimization_id
     ,expiration_time=GREATEST(expiration_time,in_expiration_time)
 WHERE h_payto=in_h_payto
   AND legitimization_process_serial_id=in_process_row
   AND provider_section=in_provider_section;
out_ok = FOUND;

-- FIXME-Oec: update exchange reserve table to store in_birthday here!
-- UPDATE exchange.reserves SET birthday=in_birthday WHERE reserve_pub=X;

IF in_require_aml
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

-- Wake up everyone who might care...
PERFORM pg_notify (in_kyc_completed_notify_s, NULL);

INSERT INTO kyc_alerts
 (h_payto
 ,trigger_type)
 VALUES
 (in_h_payto,1);


END $$;


COMMENT ON FUNCTION exchange_do_insert_kyc_attributes(INT8, BYTEA, BYTEA, VARCHAR, INT4, VARCHAR, VARCHAR, INT8, INT8, INT8, BYTEA, BOOL, VARCHAR)
  IS 'Inserts new KYC attributes and updates the status of the legitimization process and the AML status for the account';
