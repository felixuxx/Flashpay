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

DROP FUNCTION IF EXISTS exchange_do_insert_programmatic_legitimization_outcome;
CREATE OR REPLACE FUNCTION exchange_do_insert_programmatic_legitimization_outcome(
  IN in_h_payto BYTEA,
  IN in_decision_time INT8,
  IN in_expiration_time INT8,
  IN in_properties TEXT,
  IN in_new_rules TEXT,
  IN in_to_investigate BOOLEAN,
  IN ina_events TEXT[],
  IN in_notify_s TEXT,
  OUT out_account_unknown BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
  my_outcome_serial_id INT8;
  my_access_token BYTEA;
  my_max_dp INT4;
  my_i INT4;
  ini_event TEXT;
BEGIN

out_account_unknown=FALSE;

-- Note: in_payto_uri is allowed to be NULL *if*
-- in_h_payto is already in wire_targets
SELECT access_token
  INTO my_access_token
  FROM wire_targets
 WHERE wire_target_h_payto=in_h_payto;

-- Very strange, should never happen that we
-- take an AML decision on an unknown account!
IF NOT FOUND
THEN
  out_account_unknown=TRUE;
  RETURN;
END IF;
out_account_unknown=FALSE;

-- Did KYC measures get prescribed?
IF in_jmeasures IS NULL
THEN
  -- AML decision without measure: mark all
  -- active measures finished!
  UPDATE legitimization_measures
     SET is_finished=TRUE
   WHERE access_token=my_access_token
     AND NOT is_finished;
ELSE
  -- Find current maximum DP
  SELECT COALESCE(MAX(display_priority),0)
    INTO my_max_dp
    FROM legitimization_measures
   WHERE access_token=my_access_token
     AND NOT is_finished;

  -- First check if a perfectly equivalent legi measure
  -- already exists, to avoid creating tons of duplicates.
  UPDATE legitimization_measures
     SET display_priority=GREATEST(my_max_dp,display_priority)
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
      ,my_max_dp + 1);
  END IF;

  -- end if for where we had non-NULL in_jmeasures
END IF;

UPDATE legitimization_outcomes
   SET is_active=FALSE
 WHERE h_payto=in_h_payto
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
  (in_h_payto
  ,in_decision_time
  ,in_expiration_time
  ,in_properties
  ,in_new_measure_name
  ,in_to_investigate
  ,in_new_rules
  )
  RETURNING
    outcome_serial_id
  INTO
    my_outcome_serial_id;

-- FIXME: do we want/need programmatic
-- decisions in the AML history? We
-- have no justification or decider,
-- so IF we would need to change the table
-- significantly, which may break other things...

--INSERT INTO aml_history
--  (h_payto
--  ,outcome_serial_id
--  ,justification
--  ,decider_pub
--  ,decider_sig
--  ) VALUES
--  (in_h_payto
--  ,my_outcome_serial_id
--  ,in_justification
--  ,in_decider_pub
--  ,in_decider_sig
--  );

-- wake up taler-exchange-aggregator
INSERT INTO kyc_alerts
  (h_payto
  ,trigger_type)
  VALUES
  (in_h_payto,1)
   ON CONFLICT DO NOTHING;


FOR i IN 1..COALESCE(array_length(ina_events,1),0)
LOOP
  ini_event = ina_events[i];
  INSERT INTO kyc_events
    (event_timestamp
    ,event_type)
    VALUES
    (in_collection_time_ts
    ,ini_event);
END LOOP;

EXECUTE FORMAT (
   'NOTIFY %s'
  ,in_notify_s);

END $$;


COMMENT ON FUNCTION exchange_do_insert_programmatic_legitimization_outcome(BYTEA, INT8, INT8, TEXT, TEXT, BOOLEAN, TEXT[], TEXT)
  IS 'Inserts an AML decision that was taken automatically by an AML program into the database';
