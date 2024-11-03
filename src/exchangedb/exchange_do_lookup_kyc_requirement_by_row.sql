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

DROP FUNCTION IF EXISTS exchange_do_lookup_kyc_requirement_by_row;

CREATE FUNCTION exchange_do_lookup_kyc_requirement_by_row(
  IN in_h_normalized_payto BYTEA,
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
  my_wtrec RECORD;
  my_lorec RECORD;
BEGIN

-- Find the access token and the current account public key.
SELECT access_token
      ,target_pub
  INTO my_wtrec
  FROM wire_targets
 WHERE h_normalized_payto=in_h_normalized_payto;

IF NOT FOUND
THEN
  out_not_found = TRUE;
  out_kyc_required = FALSE;
  RETURN;
END IF;
out_not_found = FALSE;

out_account_pub = my_wtrec.target_pub;
out_access_token = my_wtrec.access_token;

-- Check if there are active measures for the account.
PERFORM
  FROM legitimization_measures
 WHERE access_token=out_access_token
   AND NOT is_finished
 LIMIT 1;

out_kyc_required = FOUND;

-- Get currently applicable rules.
-- Only one should ever be active per account.
SELECT jnew_rules
      ,to_investigate
  INTO my_lorec
  FROM legitimization_outcomes
 WHERE h_payto=in_h_normalized_payto
   AND is_active;

IF FOUND
THEN
  out_jrules=my_lorec.jnew_rules;
  out_aml_review=my_lorec.to_investigate;
END IF;

-- Check most recent reserve_in wire transfer, we also
-- allow that reserve public key for authentication!
SELECT reserve_pub
  INTO out_reserve_pub
  FROM reserves_in
 WHERE wire_source_h_payto
   IN (SELECT wire_source_h_payto
         FROM wire_targets
        WHERE h_normalized_payto=in_h_normalized_payto)
 ORDER BY execution_date DESC
 LIMIT 1;
-- FIXME: may want to turn this around and pass *in* the
-- reserve_pub as an argument and then not LIMIT 1 but check
-- if any reserve_pub ever matched (and just return a BOOL
-- to indicate if the kyc-auth is OK).

END $$;
