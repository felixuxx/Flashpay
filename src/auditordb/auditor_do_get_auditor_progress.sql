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
-- @author Christian Grothoff

CREATE OR REPLACE FUNCTION auditor_do_get_auditor_progress(
  IN in_keys TEXT[])
RETURNS INT8
LANGUAGE plpgsql
AS $$
DECLARE
  my_key TEXT;
  my_off INT8;
BEGIN
  FOREACH my_key IN ARRAY in_keys
  LOOP
    SELECT progress_offset
      INTO my_off
      FROM auditor_progress
      WHERE progress_key=my_key;
    RETURN my_off;
  END LOOP;
END $$;

COMMENT ON FUNCTION auditor_do_get_auditor_progress(TEXT[])
  IS 'Finds all progress offsets associated with the array of keys given as the argument and returns them in order';
