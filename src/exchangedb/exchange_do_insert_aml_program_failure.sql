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

DROP FUNCTION IF EXISTS exchange_do_insert_aml_program_failure;
CREATE FUNCTION exchange_do_insert_aml_program_failure (
  IN in_legitimization_process_serial_id INT8,
  IN in_h_payto BYTEA,
  IN in_now INT8,
  IN in_error_code INT4,
  IN in_error_message TEXT,
  IN in_kyc_completed_notify_s TEXT,
  OUT out_update BOOLEAN) -- set to true if we had a legi process matching in_process_row and in_provider_name for this account
LANGUAGE plpgsql
AS $$
BEGIN


UPDATE legitimization_processes
   SET finished=TRUE
      ,error_code=in_error_code
      ,error_message=in_error_message
 WHERE h_payto=in_h_payto
   AND legitimization_process_serial_id=in_legitimization_process_serial_id;
out_update = FOUND;
IF NOT FOUND
THEN
  -- Note: in_legitimization_process_serial_id should always be 0 here.
  -- But we do not check and simply always create a new entry to at least
  -- not loose information about the event!
  INSERT INTO legitimization_processes
    (finished
    ,error_code
    ,error_message
    ,h_payto
    ,start_time
    ,provider_section
    ) VALUES (
     TRUE
    ,in_error_code
    ,in_error_message
    ,in_h_payto
    ,in_now
    ,'skip'
   );
END IF;

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


COMMENT ON FUNCTION exchange_do_insert_aml_program_failure(INT8, BYTEA, INT8, INT4, TEXT, TEXT)
  IS 'Stores information about an AML program run that failed into the legitimization_processes table. Either updates a row of an existing legitimization process, or creates a new entry.';
