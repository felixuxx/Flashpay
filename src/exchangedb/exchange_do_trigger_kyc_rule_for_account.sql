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

DROP FUNCTION IF EXISTS exchange_do_trigger_kyc_rule_for_account;

CREATE FUNCTION exchange_do_trigger_kyc_rule_for_account(
  IN in_h_payto BYTEA,
  IN in_account_pub BYTEA, -- can be NULL
  IN in_merchant_pub BYTEA, -- can be NULL
  IN in_payto_uri TEXT, -- can be NULL
  IN in_now INT8,
  IN in_jmeasures TEXT,
  IN in_display_priority INT4,
  OUT out_legitimization_measure_serial_id INT8,
  OUT out_bad_kyc_auth BOOL)
LANGUAGE plpgsql
AS $$
DECLARE
  my_rec RECORD;
  my_access_token BYTEA;
  my_account_pub BYTEA;
BEGIN
-- Note: in_payto_uri is allowed to be NULL *if*
-- in_h_payto is already in wire_targets

SELECT
   access_token
  ,account_pub
INTO
  my_rec
FROM wire_targets
  WHERE wire_target_h_payto=in_h_payto;

IF FOUND
THEN
  -- Extract details, determine if KYC auth matches.
  my_access_token = my_rec.access_token;
  my_account_pub = my_rec.account_pub;
  IF in_merchant_pub IS NULL
  THEN
    out_bad_kyc_auth = FALSE;
  ELSE
    out_bad_kyc_auth = (my_account_pub = in_merchant_pub);
  END IF;
ELSE
  -- No constraint on merchant_pub, just create
  -- the wire_target.
  INSERT INTO wire_targets
    (payto_uri
    ,wire_target_h_payto
    ,target_pub)
  VALUES
    (in_payto_uri
    ,in_h_payto
    ,in_account_pub)
  RETURNING
    access_token
  INTO my_access_token;
  out_bad_kyc_auth=TRUE;
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
END IF;

END $$;
