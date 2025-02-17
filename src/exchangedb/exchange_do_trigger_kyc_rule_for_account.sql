--
-- This file is part of TALER
-- Copyright (C) 2014--2024 Taler Systems SA
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

DROP FUNCTION IF EXISTS exchange_do_trigger_kyc_rule_for_account;

CREATE FUNCTION exchange_do_trigger_kyc_rule_for_account(
  IN in_h_normalized_payto BYTEA,
  IN in_account_pub BYTEA, -- can be NULL, if given, should be SET
  IN in_merchant_pub BYTEA, -- can be NULL
  IN in_payto_uri TEXT, -- can be NULL
  IN in_h_full_payto BYTEA,
  IN in_now INT8,
  IN in_jmeasures TEXT,
  IN in_display_priority INT4,
  IN in_notify_s TEXT,
  OUT out_legitimization_measure_serial_id INT8,
  OUT out_bad_kyc_auth BOOL)
LANGUAGE plpgsql
AS $$
DECLARE
  my_rec RECORD;
  my_access_token BYTEA;
  my_account_pub BYTEA;
  my_reserve_pub BYTEA;
BEGIN
-- Note: in_payto_uri is allowed to be NULL *if*
-- in_h_normalized_payto is already in wire_targets


SELECT
   access_token
  ,target_pub
INTO
  my_rec
FROM wire_targets
  WHERE h_normalized_payto=in_h_normalized_payto;

IF FOUND
THEN
  -- Extract details, determine if KYC auth matches.
  my_access_token = my_rec.access_token;
  my_account_pub = my_rec.target_pub;
  out_bad_kyc_auth = COALESCE ((my_account_pub != in_merchant_pub), TRUE);
ELSE
  -- No constraint on merchant_pub, just create
  -- the wire_target.
  INSERT INTO wire_targets
    (payto_uri
    ,wire_target_h_payto
    ,h_normalized_payto
    ,target_pub)
  VALUES
    (in_payto_uri
    ,in_h_full_payto
    ,in_h_normalized_payto
    ,in_account_pub)
  RETURNING
    access_token
  INTO my_access_token;
  out_bad_kyc_auth=TRUE;
END IF;

IF out_bad_kyc_auth
THEN
  -- Check reserve_in wire transfers, we also
  -- allow those reserve public keys for authentication!
  PERFORM FROM reserves_in
    WHERE wire_source_h_payto IN (
      SELECT wire_target_h_payto
        FROM wire_targets
       WHERE h_normalized_payto=in_h_normalized_payto
      )
      AND reserve_pub = in_merchant_pub
   ORDER BY execution_date DESC;
  IF FOUND
  THEN
    out_bad_kyc_auth = FALSE;
  END IF;
END IF;

-- First check if a perfectly equivalent legi measure
-- already exists, to avoid creating tons of duplicates.
UPDATE legitimization_measures
   SET display_priority=GREATEST(in_display_priority,display_priority)
 WHERE access_token=my_access_token
   AND jmeasures=in_jmeasures
   AND NOT is_finished
 RETURNING legitimization_measure_serial_id
  INTO out_legitimization_measure_serial_id;

IF NOT FOUND
THEN
  INSERT INTO legitimization_measures
    (access_token
    ,start_time
    ,jmeasures
    ,display_priority)
    VALUES
    (my_access_token
    ,in_now
    ,in_jmeasures
    ,in_display_priority)
    RETURNING
      legitimization_measure_serial_id
    INTO
      out_legitimization_measure_serial_id;

  -- mark all other active measures finished!
  UPDATE legitimization_measures
    SET is_finished=TRUE
    WHERE access_token=my_access_token
      AND NOT is_finished
      AND legitimization_measure_serial_id != out_legitimization_measure_serial_id;
END IF;

EXECUTE FORMAT (
   'NOTIFY %s'
  ,in_notify_s);


END $$;
