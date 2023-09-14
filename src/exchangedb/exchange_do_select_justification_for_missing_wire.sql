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
-- @author: Christian Grothoff

-- FIXME: this function is not working as intended at all yet, work in progress!

CREATE OR REPLACE FUNCTION exchange_do_select_justification_missing_wire(
  IN in_wire_target_h_payto BYTEA,
  IN in_current_time INT8,
  OUT out_payto_uri TEXT, -- NULL allowed
  OUT out_kyc_pending TEXT, -- NULL allowed
  OUT out_aml_status INT4, -- NULL allowed
  OUT out_aml_limit taler_amount) -- NULL allowed!
LANGUAGE plpgsql
AS $$
DECLARE
  my_required_checks TEXT[];
DECLARE
  my_aml_data RECORD;
DECLARE
  satisfied CURSOR FOR
  SELECT satisfied_checks
    FROM kyc_attributes
   WHERE h_payto=in_wire_target_h_payto
     AND expiration_time < in_current_time;
DECLARE
  i RECORD;
BEGIN

  -- Fetch payto URI
  out_payto_uri = NULL;
  SELECT payto_uri
    INTO out_payto_uri
    FROM wire_targets
   WHERE wire_target_h_payto=my_wire_target_h_payto;

  -- Check KYC status
  my_required_checks = NULL;
  SELECT string_to_array (required_checks, ' ')
    INTO my_required_checks
    FROM legitimization_requirements
    WHERE h_payto=my_wire_target_h_payto;

  -- Get last AML decision
  SELECT
      new_threshold
     ,kyc_requirements
     ,new_status
    INTO
      my_aml_data
     FROM aml_history
    WHERE h_payto=in_wire_target_h_payto
    ORDER BY aml_history_serial_id -- get last decision
      DESC LIMIT 1;
  IF FOUND
  THEN
    out_aml_limit=my_aml_data.new_threshold;
    out_aml_status=my_aml_data.kyc_status;
    -- Combine KYC requirements
    my_required_checks
       = array_cat (my_required_checks,
                    my_aml_data.kyc_requirements);
  ELSE
    out_aml_limit=NULL;
    out_aml_status=0; -- or NULL? Style question!
  END IF;

  OPEN satisfied;
  LOOP
    FETCH NEXT FROM satisfied INTO i;
    EXIT WHEN NOT FOUND;

    -- remove all satisfied checks from the list
    FOR i in 1..array_length(i.satisfied_checks)
    LOOP
      my_required_checks
        = array_remove (my_required_checks,
                        i.satisfied_checks[i]);
    END LOOP;
  END LOOP;

  -- Return remaining required checks as one string
  IF ( (my_required_checks IS NOT NULL) AND
       (0 < array_length(my_satisfied_checks)) )
  THEN
    out_kyc_pending
      = array_to_string (my_required_checks, ' ');
  END IF;

  RETURN;
END $$;
