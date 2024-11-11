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

DROP FUNCTION IF EXISTS exchange_do_insert_successor_measure;
CREATE FUNCTION exchange_do_insert_successor_measure(
  IN in_h_normalized_payto BYTEA,
  IN in_decision_time INT8,
  IN in_expiration_time INT8,
  IN in_new_measure_name TEXT, -- can be NULL
  IN in_jmeasures TEXT, -- can be NULL
  OUT out_last_date INT8,
  OUT out_account_unknown BOOLEAN,
  OUT out_legitimization_measure_serial_id INT8
)
LANGUAGE plpgsql
AS $$
DECLARE
  my_outcome_serial_id INT8;
  my_access_token BYTEA;
BEGIN

out_account_unknown=FALSE;
out_legitimization_measure_serial_id=0;

-- Check no more recent decision exists.
SELECT decision_time
  INTO out_last_date
  FROM legitimization_outcomes
 WHERE h_payto=in_h_normalized_payto
   AND is_active
 ORDER BY decision_time DESC, outcome_serial_id DESC;

IF FOUND
THEN
  IF out_last_date >= in_decision_time
  THEN
    -- Refuse to insert older decision.
    RETURN;
  END IF;
  UPDATE legitimization_outcomes
     SET is_active=FALSE
   WHERE h_payto=in_h_normalized_payto
     AND is_active;
ELSE
  out_last_date = 0;
END IF;

SELECT access_token
  INTO my_access_token
  FROM wire_targets
 WHERE h_normalized_payto=in_h_normalized_payto;

IF NOT FOUND
THEN
  IF in_payto_uri IS NULL
  THEN
    -- AML decision on an unknown account without payto_uri => fail.
    out_account_unknown=TRUE;
    RETURN;
  END IF;

  INSERT INTO wire_targets
    (wire_target_h_payto
    ,h_normalized_payto
    ,payto_uri)
    VALUES
    (in_h_full_payto
    ,in_h_normalized_payto
    ,in_payto_uri)
    RETURNING access_token
      INTO my_access_token;
END IF;


-- First check if a perfectly equivalent legi measure
-- already exists, to avoid creating tons of duplicates.
SELECT legitimization_measure_serial_id
  INTO out_legitimization_measure_serial_id
  FROM legitimization_measures
  WHERE access_token=my_access_token
    AND jmeasures=in_jmeasures
    AND NOT is_finished;

IF NOT FOUND
THEN
  -- Enable new legitimization measure
  INSERT INTO legitimization_measures
    (access_token
    ,start_time
    ,jmeasures
    ,display_priority)
    VALUES
    (my_access_token
    ,in_decision_time
    ,in_jmeasures
    ,1)
    RETURNING
      legitimization_measure_serial_id
    INTO
      out_legitimization_measure_serial_id;
END IF;

-- AML decision: mark all other active measures finished!
UPDATE legitimization_measures
  SET is_finished=TRUE
  WHERE access_token=my_access_token
    AND NOT is_finished
    AND legitimization_measure_serial_id != out_legitimization_measure_serial_id;

UPDATE legitimization_outcomes
   SET is_active=FALSE
 WHERE h_payto=in_h_normalized_payto
   -- this clause is a minor optimization to avoid
   -- updating outcomes that have long expired.
   AND expiration_time >= in_decision_time;

INSERT INTO legitimization_outcomes
  (h_payto
  ,decision_time
  ,expiration_time
  ,jproperties
  ,new_measure_name
  ,to_investigate
  ,jnew_rules
  )
  VALUES
  (in_h_normalized_payto
  ,in_decision_time
  ,in_expiration_time
  ,'{}'
  ,in_new_measure_name
  ,FALSE
  ,NULL
  )
  RETURNING
    outcome_serial_id
  INTO
    my_outcome_serial_id;

END $$;


COMMENT ON FUNCTION exchange_do_insert_successor_measure(BYTEA, INT8, INT8, TEXT, TEXT)
  IS 'Checks whether the AML officer is eligible to make AML decisions and if so inserts the decision into the table';
