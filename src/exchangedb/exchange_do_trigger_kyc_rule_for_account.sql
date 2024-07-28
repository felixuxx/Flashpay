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

CREATE OR REPLACE FUNCTION exchange_do_trigger_kyc_rule_for_account(
  IN in_h_payto BYTEA,
  IN in_account_pub BYTEA, -- can be NULL
  IN in_payto_uri TEXT, -- can be NULL
  IN in_now INT8,
  IN in_jmeasures TEXT,
  IN in_display_priority INT4,
  OUT out_legitimization_measure_serial_id INT8)
LANGUAGE plpgsql
AS $$
DECLARE
  my_access_token BYTEA;
BEGIN
-- Note: in_payto_uri is allowed to be NULL *if*
-- in_h_payto is already in wire_targets
SELECT
  access_token
INTO
  my_access_token
FROM wire_targets
  WHERE wire_target_h_payto=in_h_payto;

IF NOT FOUND
THEN
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
END IF;

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

END $$;
