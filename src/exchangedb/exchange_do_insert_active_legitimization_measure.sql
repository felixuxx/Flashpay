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

DROP FUNCTION IF EXISTS exchange_do_insert_active_legitimization_measure;
CREATE FUNCTION exchange_do_insert_active_legitimization_measure(
  IN in_access_token BYTEA,
  IN in_start_time INT8,
  IN in_jmeasures TEXT,
  OUT out_legitimization_measure_serial_id INT8)
LANGUAGE plpgsql
AS $$
BEGIN

UPDATE legitimization_measures
   SET is_finished=TRUE
 WHERE access_token=in_access_token
   AND NOT is_finished;

INSERT INTO legitimization_measures
  (access_token
  ,start_time
  ,jmeasures
  ,display_priority)
  VALUES
  (in_access_token
  ,in_decision_time
  ,in_jmeasures
  ,1)
  RETURNING
    legitimization_measure_serial_id
  INTO
    out_legitimization_measure_serial_id;

END $$;


COMMENT ON FUNCTION exchange_do_insert_active_legitimization_measure(BYTEA, INT8, TEXT)
  IS 'Inserts legitimization measure for an account and marks all existing such measures as inactive';
