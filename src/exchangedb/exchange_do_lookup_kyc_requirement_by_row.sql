--
-- This file is part of TALER
-- Copyright (C) 2024 Taler Systems SA
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

CREATE OR REPLACE FUNCTION exchange_do_lookup_kyc_requirement_by_row(
  IN in_legitimization_serial_id INT8,
  OUT out_account_pub BYTEA,  -- NULL allowed
  OUT out_reserve_pub BYTEA, -- NULL allowed
  OUT out_access_token BYTEA, -- NULL if 'out_not_found'
  OUT out_jrules TEXT, -- NULL allowed
  OUT out_not_found BOOLEAN,
  OUT out_aml_review BOOLEAN, -- NULL allowed
  OUT out_kyc_required BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  my_h_payto BYTEA;
  my_wtrec RECORD;
  my_lorec RECORD;
BEGIN

-- Find the access token.
SELECT access_token
  INTO out_access_token
  FROM legitimization_measures
 WHERE legitimization_measure_serial_id=in_legitimization_serial_id;

IF NOT FOUND
THEN
  out_not_found = TRUE;
  out_kyc_required = FALSE;
  RETURN;
END IF;
out_not_found = FALSE;

-- Find the payto hash and the current account public key.
SELECT target_pub
      ,wire_target_h_payto
  INTO my_wtrec
  FROM wire_targets
 WHERE access_token=out_access_token;

out_account_pub = my_wtrec.target_pub;
my_h_payto = my_wtrec.wire_target_h_payto;

-- Check if there are active measures for the account.
SELECT NOT is_finished
  INTO out_kyc_required
  FROM legitimization_measures
 WHERE access_token=out_access_token
 ORDER BY start_time DESC
 LIMIT 1;

IF NOT FOUND
THEN
  out_kyc_required=TRUE;
END IF;

-- Get currently applicable rules.
-- Only one should ever be active per account.
SELECT jnew_rules
      ,to_investigate
  INTO my_lorec
  FROM legitimization_outcomes
 WHERE h_payto=my_h_payto
   AND is_active;

IF FOUND
THEN
  out_jrules=my_lorec.jnew_rules;
  out_aml_review=my_lorec.to_investigate;
END IF;

-- Get most recent reserve_in wire transfer, we also
-- allow that one for authentication!
SELECT reserve_pub
  INTO out_reserve_pub
  FROM reserves_in
 WHERE wire_source_h_payto=my_h_payto
 ORDER BY execution_date DESC
 LIMIT 1;

END $$;
