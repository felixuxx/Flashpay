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

DROP FUNCTION IF EXISTS exchange_do_set_aml_lock;
CREATE FUNCTION exchange_do_set_aml_lock (
  IN in_h_payto BYTEA,
  IN in_now INT8,
  IN in_expiration INT8,
  OUT out_aml_program_lock_timeout INT8) -- set if we have an existing lock
LANGUAGE plpgsql
AS $$
BEGIN

UPDATE wire_targets
   SET aml_program_lock_timeout=in_expiration
 WHERE h_normalized_payto=in_h_payto
   AND ( (aml_program_lock_timeout IS NULL)
      OR (aml_program_lock_timeout < in_now) );
IF NOT FOUND
THEN
  SELECT aml_program_lock_timeout
    INTO out_aml_program_lock_timeout
    FROM wire_targets
   WHERE h_normalized_payto=in_h_payto;
ELSE
  out_aml_program_lock_timeout = 0;
END IF;

END $$;


COMMENT ON FUNCTION exchange_do_set_aml_lock(BYTEA, INT8, INT8)
  IS 'Tries to lock an account for running an AML program. Returns the timeout of the existing lock, 0 if there is no existing lock, and NULL if we do not know the account.';
